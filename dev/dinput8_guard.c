/*
 * dinput8.dll - Crash guard for BOB2 (Win10/Win11)
 *
 * Intercepts:
 *   1. EXCEPTION_BREAKPOINT (0x80000003) - DebugBreak assertions in 2.13 renderer
 *   2. STATUS_SXS_INVALID_DEACTIVATION (0xc0150010) - SxS activation context error
 *      triggered when "More GFX" options tab enumerates display modes via COM
 *
 * Lets ALL other exceptions pass through to the game's own SEH handlers.
 *
 * Also, since 1.9.0, the Squadron Room's AUTOSTART: when the Room has
 * written SquadronRoom\autostart.txt beside this DLL, the front end is
 * steered straight into a campaign (see the AUTOSTART section). Without
 * that file nothing in this DLL touches the game.
 *
 * Build:
 *   i686-w64-mingw32-gcc -shared -o dinput8.dll dinput8_guard.c \
 *       -lkernel32 -luser32 -lole32 -Wl,--kill-at -O2
 */

#define WIN32_LEAN_AND_MEAN
#define CINTERFACE
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <emmintrin.h>

/* Must match $FixVersion in BOB2_Setup.ps1 - the log line is how you tell
 * which build is actually deployed in the game folder. */
#define BOB2FIX_VERSION "1.9.3"

/* ==================== LOGGING ==================== */

static FILE *g_logFile = NULL;
static DWORD g_bpCount = 0;
static DWORD g_sxsCount = 0;
static DWORD g_avCount = 0;
static HMODULE g_rcombo = NULL;
static DWORD g_rcomboBase = 0;
static DWORD g_rcomboSize = 0;
static DWORD g_startTick = 0;
static HINSTANCE g_ourDLL = NULL;

static void OpenLog(void) {
    char dllPath[MAX_PATH];
    char logPath[MAX_PATH];
    char *lastSlash;

    g_startTick = GetTickCount();

    if (GetModuleFileNameA(g_ourDLL, dllPath, MAX_PATH)) {
        lastSlash = strrchr(dllPath, '\\');
        if (lastSlash) {
            lastSlash[1] = '\0';
            wsprintfA(logPath, "%sbob2guard.log", dllPath);
            g_logFile = fopen(logPath, "w");
        }
    }
    if (!g_logFile) {
        g_logFile = fopen("bob2guard.log", "w");
    }
    if (g_logFile) {
        fprintf(g_logFile,
                "[0.000] === BOB2 Win11 Fix v" BOB2FIX_VERSION
                " - crash guard (built " __DATE__ ") ===\n");
        fflush(g_logFile);
    }
}

static void LogMsg(const char *fmt, ...) {
    if (!g_logFile) return;
    va_list args;
    va_start(args, fmt);
    DWORD elapsed = GetTickCount() - g_startTick;
    fprintf(g_logFile, "[%u.%03u] ", elapsed / 1000, elapsed % 1000);
    vfprintf(g_logFile, fmt, args);
    fprintf(g_logFile, "\n");
    fflush(g_logFile);
    va_end(args);
}

/* ==================== CRASH GUARD ==================== */

/*
 * Vectored Exception Handler - intercepts:
 *   1. EXCEPTION_BREAKPOINT (0x80000003) - INT 3 / DebugBreak from 2.13 renderer
 *   2. STATUS_SXS_INVALID_DEACTIVATION (0xc0150010) - SxS context error from
 *      "More GFX" tab COM enumeration
 *
 * ALL other exceptions are passed through to the game's own SEH.
 */
#define BOB2_SXS_INVALID_DEACTIVATION 0xc0150010

static LONG CALLBACK VectoredHandler(PEXCEPTION_POINTERS ep) {
    DWORD code = ep->ExceptionRecord->ExceptionCode;

    /* Fast path: skip C++ exceptions and debug prints immediately (most common) */
    if (code == 0xE06D7363 || code == 0x406D1388 || code == 0x40010006) {
        return EXCEPTION_CONTINUE_SEARCH;
    }

    if (code == EXCEPTION_BREAKPOINT) {  /* 0x80000003 - INT 3 / DebugBreak */
        DWORD addr = (DWORD)(DWORD_PTR)(ep->ExceptionRecord->ExceptionAddress);
        ep->ContextRecord->Eip += 1;  /* skip 1-byte INT 3 instruction */
        g_bpCount++;
        if (g_bpCount <= 20 || (g_bpCount % 50) == 0) {
            LogMsg("BREAKPOINT skipped at 0x%08X (total: %u)", addr, g_bpCount);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (code == BOB2_SXS_INVALID_DEACTIVATION) {  /* 0xc0150010 - SxS context */
        DWORD addr = (DWORD)(DWORD_PTR)(ep->ExceptionRecord->ExceptionAddress);
        g_sxsCount++;
        LogMsg("SXS_INVALID_DEACTIVATION caught at 0x%08X (total: %u)", addr, g_sxsCount);
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (code == EXCEPTION_ACCESS_VIOLATION) {  /* 0xc0000005 */
        DWORD addr = (DWORD)(DWORD_PTR)(ep->ExceptionRecord->ExceptionAddress);

        /* Check if crash is inside RCombo.ocx (VB6 combo control used in More GFX) */
        if (g_rcomboBase == 0) {
            /* Lazy lookup - try to find RCombo.ocx */
            g_rcombo = GetModuleHandleA("RCombo.ocx");
            if (g_rcombo) {
                IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)g_rcombo;
                IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((char *)g_rcombo + dos->e_lfanew);
                g_rcomboBase = (DWORD)(DWORD_PTR)g_rcombo;
                g_rcomboSize = nt->OptionalHeader.SizeOfImage;
                LogMsg("RCombo.ocx found at 0x%08X size 0x%X", g_rcomboBase, g_rcomboSize);
            }
        }

        if (g_rcomboBase && addr >= g_rcomboBase && addr < (g_rcomboBase + g_rcomboSize)) {
            g_avCount++;
            if (g_avCount <= 50) {
                LogMsg("ACCESS_VIOLATION in RCombo.ocx at 0x%08X (offset 0x%04X, total: %u)"
                       " - logged only, NOT intercepted",
                       addr, addr - g_rcomboBase, g_avCount);
            }
            /*
             * DELIBERATELY NOT INTERCEPTED (changed 2026-08-04).
             *
             * Earlier builds tried to repair this: set EAX=0 and advance EIP by 2,
             * on the theory that offset 0x2944 is a 2-byte "mov eax,[ecx]"
             * dereferencing a null pointer, so the caller would just see NULL.
             *
             * A real "More GFX" crash showed that does not work. The log recorded:
             *     ACCESS_VIOLATION at offset 0x2944   <- skipped 2 bytes
             *     ACCESS_VIOLATION at offset 0x2946   <- the very next instruction
             * i.e. the following instruction uses the same bad pointer. Execution
             * then ran on through code that could not cope and ended up jumping to
             * address 0x00000003:
             *     EXCEPTION_ACCESS_VIOLATION in <UNKNOWN> at 0023:00000003
             *
             * So the "repair" turned a contained fault into corrupted control flow.
             * Skipping instructions blind is not a safe technique: you cannot fix a
             * null-pointer dereference by stepping over one instruction when the
             * surrounding code assumes that pointer is valid.
             *
             * The game installs its own SEH (crashes report "Exception handler
             * called in int CMIGApp::Run()"), so falling through to it is both
             * safer and more honest than corrupting the context.
             */
        }
    }

    /* Everything else: let the game's SEH handle it */
    return EXCEPTION_CONTINUE_SEARCH;
}

/* ==================== DINPUT8.DLL PROXY ==================== */

static HMODULE g_realDInput8 = NULL;

typedef HRESULT (WINAPI *PFN_DirectInput8Create)(
    HINSTANCE hinst, DWORD dwVersion, REFIID riidltf,
    LPVOID *ppvOut, LPVOID punkOuter);
typedef HRESULT (WINAPI *PFN_DllCanUnloadNow)(void);
typedef HRESULT (WINAPI *PFN_DllGetClassObject)(REFCLSID, REFIID, LPVOID*);
typedef HRESULT (WINAPI *PFN_DllRegisterServer)(void);
typedef HRESULT (WINAPI *PFN_DllUnregisterServer)(void);

static PFN_DirectInput8Create pfn_DirectInput8Create = NULL;
static PFN_DllCanUnloadNow pfn_DllCanUnloadNow = NULL;
static PFN_DllGetClassObject pfn_DllGetClassObject = NULL;
static PFN_DllRegisterServer pfn_DllRegisterServer = NULL;
static PFN_DllUnregisterServer pfn_DllUnregisterServer = NULL;

static BOOL LoadRealDInput8(void) {
    char sysDir[MAX_PATH];
    char path[MAX_PATH];

    GetSystemDirectoryA(sysDir, MAX_PATH);
    wsprintfA(path, "%s\\dinput8.dll", sysDir);

    g_realDInput8 = LoadLibraryA(path);
    if (!g_realDInput8) {
        LogMsg("ERROR: Failed to load real dinput8.dll (err=%u)", GetLastError());
        return FALSE;
    }

    pfn_DirectInput8Create = (PFN_DirectInput8Create)
        GetProcAddress(g_realDInput8, "DirectInput8Create");
    pfn_DllCanUnloadNow = (PFN_DllCanUnloadNow)
        GetProcAddress(g_realDInput8, "DllCanUnloadNow");
    pfn_DllGetClassObject = (PFN_DllGetClassObject)
        GetProcAddress(g_realDInput8, "DllGetClassObject");
    pfn_DllRegisterServer = (PFN_DllRegisterServer)
        GetProcAddress(g_realDInput8, "DllRegisterServer");
    pfn_DllUnregisterServer = (PFN_DllUnregisterServer)
        GetProcAddress(g_realDInput8, "DllUnregisterServer");

    LogMsg("Real dinput8.dll loaded OK");
    return TRUE;
}

__declspec(dllexport) HRESULT WINAPI DirectInput8Create(
    HINSTANCE hinst, DWORD dwVersion, REFIID riidltf,
    LPVOID *ppvOut, LPVOID punkOuter) {
    if (pfn_DirectInput8Create)
        return pfn_DirectInput8Create(hinst, dwVersion, riidltf, ppvOut, punkOuter);
    return E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI DllCanUnloadNow(void) {
    if (pfn_DllCanUnloadNow) return pfn_DllCanUnloadNow();
    return S_FALSE;
}

__declspec(dllexport) HRESULT WINAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID *ppv) {
    if (pfn_DllGetClassObject) return pfn_DllGetClassObject(rclsid, riid, ppv);
    return E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI DllRegisterServer(void) {
    if (pfn_DllRegisterServer) return pfn_DllRegisterServer();
    return E_FAIL;
}

__declspec(dllexport) HRESULT WINAPI DllUnregisterServer(void) {
    if (pfn_DllUnregisterServer) return pfn_DllUnregisterServer();
    return E_FAIL;
}

/* ==================== AUTOSTART (Squadron Room) ====================
 *
 * The game cannot be told to open on a campaign: no switch, no bdg.txt
 * key. But its front end is pointer driven. One MFC class, RFullPanelDial,
 * holds 55 static FullScreen page structs; every button and list row goes
 * through RFullPanelDial::OnSelectRlistbox(row,row), which reads the
 * current page's textlists[row].nextscreen and .onselect (a handler that
 * may veto or rewrite the target) and then LaunchScreen()s it. The intro
 * page has exactly ONE exit row: text 0, nextscreen = title, onselect =
 * CheckLobby, fired by IntroSmackInit's posted 0x406 the moment SKIP_VIDEOS
 * is on. IntroSmackInit is also where InitPreferences and ReadBDGValues
 * run, so the intro page is left alone and only its exit is redirected.
 *
 * What this does, when SquadronRoom\autostart.txt exists:
 *   1. checks the exe is the 2.13 build this was pinned against, byte for
 *      byte at every address it will touch; otherwise it does nothing
 *   2. a thread waits for the CRT dynamic initializers (introsmack.InitProc
 *      becomes non-zero) and writes ONE pointer: introsmack row 0's
 *      onselect now points at AutostartHook. A .data write, no code patch.
 *   3. AutostartHook runs on the game's UI thread inside the dispatcher,
 *      after IntroSmackInit: calls the original CheckLobby, sets gameside,
 *      gamestate, whichcamp and the player's name, and rewrites the target
 *      to campaignentername, so the game builds its Begin page exactly as
 *      it would after four clicks (CampaignEnterNameInit loads the clean
 *      node tree and the target table)
 *   4. a thread timer, dispatched by the game's own message loop once that
 *      handler has returned, presses BEGIN the way the button does:
 *      OnSelectRlistbox(1,1) -> LaunchMapFirstTime -> the campaign map
 *
 * Addresses are the shipping 2.13 exe (relocations stripped, always at
 * 0x00400000; .text byte identical to the analysed Bob213.exe). They were
 * pinned from the 2.12 PDB by static row patterns and byte signatures;
 * AUTOSTART.md in the fix folder records how. Function pointers that live
 * in .data (CheckLobby, LaunchMapFirstTime) are read at run time from the
 * page structs after the initializers have filled them in, so only the
 * data addresses and two code signatures are compiled in.
 */
#define AS_EXE_TIMESTAMP     0x5623a8e8u   /* Bob.exe 2.13, 18 Oct 2015 14:12:56 */
#define AS_EXE_BASE          0x00400000u
#define AS_TEXT_LO           0x00401000u
#define AS_TEXT_HI           0x006be5ecu
#define AS_INTROSMACK        0x00788e50u   /* RFullPanelDial::introsmack */
#define AS_TITLE             0x0078ce60u   /* RFullPanelDial::title */
#define AS_CAMPSELECT        0x0078ddc0u   /* RFullPanelDial::campaignselect */
#define AS_CAMPENTERNAME     0x00788180u   /* RFullPanelDial::campaignentername */
#define AS_LOADGAME          0x0078d0f0u   /* RFullPanelDial::loadgame: rows RAF, LW, back to title, LOAD (DoLoadGame) */
#define AS_LOADGAME_TEXT_RAF 0xa38u
#define AS_MPVIEW            0x0079e8f4u   /* RDialog::m_pView, the CMIGView (2.12 0x0079f9f4) */
#define VIEW_FULLPANE        0x108         /* CMIGView::m_pfullpane: the live front-end panel, NULL on the map */
#define AS_TITLE_TEXT_QUIT   0xfu          /* title row whose onselect is ConfirmExit */
#define AS_LOADGAME_TEXT_LW  0xa39u
#define AS_LOADGAME_TEXT_LOAD 0x494u
#define AS_GAMESTATE         0x04f4b358u   /* RFullPanelDial::gamestate  4 PILOT 5 COMMANDER */
#define AS_GAMESIDE          0x04f4b32cu   /* RFullPanelDial::gameside   0 RAF 1 LW */
#define AS_PLAYERNAME        0x04f1e753u   /* Save_Data + 0xE3, char[21] */
#define AS_SKIPVIDEOS        0x06158a03u   /* BDG_Values + 1651 */
#define AS_FAV               0x04efb050u   /* Miss_Man.camp.fav, CampaignZero::Fav, 46 bytes */
#define FAV_GROUP            6             /* int: RAF group filter, 0 any */
#define FAV_AC               10            /* int: RAF aircraft TYPE filter, 0 any */
#define FAV_SECTOR           14            /* int: RAF sector filter, 0 any */
#define FAV_SQUADRON         18            /* int: RAF SquadNum, the pilot's squadron */
#define FAV_FLOTTE           26            /* int: LW Luftflotte filter, 0 any */
#define FAV_GESCHTYPE        30            /* int: LW Geschwader type filter, 4 any */
#define FAV_GESCHWADER       34            /* int: LW index into Node_Data.geschwader, -1 any */
#define FAV_GRUPPE           38            /* int: LW 0 any, 1 I, 2 II, 3 III (ChangeAccelOn tests gruppe-1) */
#define AS_LW_FIRST_UNIT     160           /* SquadNum of the first Luftwaffe unit, I./JG 3 */
#define AS_ONSELECTRLISTBOX  0x00412fe8u   /* RFullPanelDial::OnSelectRlistbox(int,int) thiscall */
#define AS_LAUNCHSCREEN      0x00412f2eu   /* RFullPanelDial::LaunchScreen(FullScreen*) */
#define FS_TEXTLISTS         364           /* FullScreen::textlists[10], 24 bytes each */
#define FS_ROW               24
#define FS_INITPROC          604
#define RF_CURRENTSCREEN     0x17d         /* RFullPanelDial::m_currentscreen */
#define RF_WHICHCAMP         0x1a9         /* RFullPanelDial::whichcamp */

/* first bytes of the two code addresses this relies on */
static const unsigned char AS_SIG_DISPATCH[24] = {
    0x55,0x8b,0xec,0x8b,0x45,0x08,0x3b,0x45,0x0c,0x57,0x8b,0xf9,
    0x7f,0x03,0x8b,0x45,0x0c,0x8b,0x8f,0x7d,0x01,0x00,0x00,0x6b };
static const unsigned char AS_SIG_LAUNCH[16] = {
    0x55,0x8b,0xec,0x83,0xec,0x10,0x53,0x56,0x33,0xf6,0x8b,0xd9,0x89,0xb3,0xa5,0x01 };

typedef int (__attribute__((thiscall)) *PFN_OnSelect)(void *self, void **next);
typedef int (__attribute__((thiscall)) *PFN_OnSelectRlistbox)(void *self, int a, int b);

enum { AS_MODE_OFF = 0, AS_MODE_BEGIN = 1, AS_MODE_NAME = 2, AS_MODE_LOAD = 3 };

static struct {
    int  mode;
    int  side;
    int  role;
    int  phase;
    int  unit;      /* SquadNum of his own squadron or Gruppe, 0 = leave the game's default */
    char name[32];
    char save[MAX_PATH];
    volatile LONG armed;
} g_as;
static char g_asDonePath[MAX_PATH];
static PFN_OnSelect g_asOrigOnSelect = NULL;
static void *g_asFullpane = NULL;
static int g_asBeginTries = 0;

static void AsDone(const char *status) {
    FILE *f = fopen(g_asDonePath, "a");
    if (f) { fprintf(f, "status=%s\n", status); fclose(f); }
    LogMsg("autostart: status=%s", status);
}

static int AsReadRequest(void) {
    char dllPath[MAX_PATH], req[MAX_PATH], line[512], *slash;
    FILE *f;
    if (!GetModuleFileNameA(g_ourDLL, dllPath, MAX_PATH)) return 0;
    slash = strrchr(dllPath, '\\'); if (!slash) return 0;
    slash[1] = '\0';
    wsprintfA(req, "%sSquadronRoom\\autostart.txt", dllPath);
    wsprintfA(g_asDonePath, "%sSquadronRoom\\autostart.done", dllPath);
    f = fopen(req, "r");
    if (!f) return 0;
    memset(&g_as, 0, sizeof(g_as));
    while (fgets(line, sizeof(line), f)) {
        char *eq = strchr(line, '='), *v, *e;
        if (!eq) continue;
        *eq = '\0'; v = eq + 1;
        e = v + strlen(v); while (e > v && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ')) *--e = '\0';
        if      (!strcmp(line, "mode"))  g_as.mode  = !strcmp(v, "begin") ? AS_MODE_BEGIN : !strcmp(v, "name") ? AS_MODE_NAME : !strcmp(v, "load") ? AS_MODE_LOAD : AS_MODE_OFF;
        else if (!strcmp(line, "side"))  g_as.side  = atoi(v);
        else if (!strcmp(line, "role"))  g_as.role  = atoi(v);
        else if (!strcmp(line, "phase")) g_as.phase = atoi(v);
        else if (!strcmp(line, "unit"))  g_as.unit  = atoi(v);
        else if (!strcmp(line, "name"))  { strncpy(g_as.name, v, 20); g_as.name[20] = '\0'; }
        else if (!strcmp(line, "save"))  { strncpy(g_as.save, v, MAX_PATH - 1); }
    }
    fclose(f);
    /* one shot: the request becomes the report, so a plain Play never sees it */
    DeleteFileA(g_asDonePath);
    if (!MoveFileExA(req, g_asDonePath, MOVEFILE_REPLACE_EXISTING)) DeleteFileA(req);
    LogMsg("autostart: request mode=%d side=%d role=%d phase=%d unit=%d name=\"%s\"", g_as.mode, g_as.side, g_as.role, g_as.phase, g_as.unit, g_as.name);
    return 1;
}

static int AsVerifyExe(void) {
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *nt;
    const DWORD *isr = (const DWORD *)(AS_INTROSMACK + FS_TEXTLISTS);
    const DWORD *cer = (const DWORD *)(AS_CAMPENTERNAME + FS_TEXTLISTS);
    if ((DWORD)(DWORD_PTR)dos != AS_EXE_BASE) { LogMsg("autostart: exe base 0x%08X, expected 0x%08X", (DWORD)(DWORD_PTR)dos, AS_EXE_BASE); return 0; }
    nt = (IMAGE_NT_HEADERS *)((char *)dos + dos->e_lfanew);
    if (nt->FileHeader.TimeDateStamp != AS_EXE_TIMESTAMP) { LogMsg("autostart: exe timestamp 0x%08X, expected 0x%08X", nt->FileHeader.TimeDateStamp, AS_EXE_TIMESTAMP); return 0; }
    if (memcmp((const void *)AS_ONSELECTRLISTBOX, AS_SIG_DISPATCH, sizeof(AS_SIG_DISPATCH))) { LogMsg("autostart: OnSelectRlistbox signature differs"); return 0; }
    if (memcmp((const void *)AS_LAUNCHSCREEN, AS_SIG_LAUNCH, sizeof(AS_SIG_LAUNCH))) { LogMsg("autostart: LaunchScreen signature differs"); return 0; }
    /* the static halves of the page rows: text ids and nextscreen pointers */
    if (isr[0] != 0 || isr[1] != AS_TITLE) { LogMsg("autostart: introsmack row 0 is not (0, title)"); return 0; }
    if (cer[0] != 0x47e || cer[1] != AS_TITLE || cer[6] != 0x327 || cer[7] != 0) { LogMsg("autostart: campaignentername rows differ"); return 0; }
    if (*(const DWORD *)(AS_CAMPSELECT + FS_TEXTLISTS + FS_ROW + 4) != AS_CAMPENTERNAME) { LogMsg("autostart: campaignselect row 1 does not lead to campaignentername"); return 0; }
    {   /* the Load Game page, pinned 21 September 2026 from its 2.12 and 2.13 initializers:
         * static text and nextscreen of rows 0..2 (RAF tab, LW tab, back to the title) */
        const DWORD *lg = (const DWORD *)(AS_LOADGAME + FS_TEXTLISTS);
        if (lg[0] != AS_LOADGAME_TEXT_RAF || lg[1] != 0 || lg[6] != AS_LOADGAME_TEXT_LW || lg[7] != 0 || lg[12] != 0x47e || lg[13] != AS_TITLE) {
            LogMsg("autostart: loadgame rows differ"); return 0; }
    }
    return 1;
}

static int __attribute__((thiscall)) AutostartHook(void *self, void **next);
static void AsArmExitWatch(void);

static VOID CALLBACK AsBeginTimer(HWND hwnd, UINT msg, UINT_PTR id, DWORD now) {
    void *cur = g_asFullpane ? *(void **)((char *)g_asFullpane + RF_CURRENTSCREEN) : NULL;
    (void)hwnd; (void)msg; (void)now;
    if (cur != (void *)AS_CAMPENTERNAME) {
        if (++g_asBeginTries < 25) return;          /* five seconds, then leave the page to the player */
        KillTimer(NULL, id);
        LogMsg("autostart: Begin page never became current (screen 0x%08X), leaving it to the player", (DWORD)(DWORD_PTR)cur);
        AsDone("fallback");
        return;
    }
    KillTimer(NULL, id);
    /* HIS OWN UNIT. In pilot mode the Begin page carries the ControlFly
     * panel, three combos whose handlers write Miss_Man.camp.fav: on the
     * RAF side fav.squadron is the SquadNum, on the Luftwaffe side
     * fav.geschwader indexes Node_Data.geschwader and fav.gruppe is 0..2,
     * and the campaign then works from that unit. Left at the panel's
     * defaults the game took the first unit in its list, I./JG 3, which
     * is how Patrick flew a Kommandeur's 109 of a Gruppe he never chose.
     * LaunchMapFirstTime saves and restores the Fav block around its copy
     * of the campaign table in pilot mode, so writing it here, after the
     * panel is built and before BEGIN, is exactly what choosing it does.
     * Luftwaffe units sit three to a Geschwader in the game's tables, in
     * SquadNum order from 160, so the index pair is arithmetic (confirmed
     * by flight: geschwader zero based, gruppe one based with 0 = any). */
    if (g_as.role == 4 && g_as.unit > 0) {
        char *fav = (char *)AS_FAV;
        if (g_as.side == 1) {
            int g = (g_as.unit - AS_LW_FIRST_UNIT) / 3, k = (g_as.unit - AS_LW_FIRST_UNIT) % 3;
            if (g_as.unit >= AS_LW_FIRST_UNIT && g < 32) {
                *(int *)(fav + FAV_FLOTTE) = 0; *(int *)(fav + FAV_GESCHTYPE) = 4;
                /* gruppe is ONE based here, 0 meaning any: NodeData's ChangeAccelOn,
                 * the code that actually puts the player in the air, tests
                 * "fav.gruppe == 0 || unit's gruppe == fav.gruppe - 1". Written
                 * zero based, II./JG 26 flew as I./JG 26 (save read 163 for 164,
                 * 20 September 2026). The Geschwader index IS zero based and in
                 * SquadNum order: that same flight put him in JG 26 for index 1. */
                *(int *)(fav + FAV_GESCHWADER) = g; *(int *)(fav + FAV_GRUPPE) = k + 1;
                LogMsg("autostart: favourite unit %d -> geschwader %d gruppe %d (field %d)", g_as.unit, g, k, k + 1);
            } else LogMsg("autostart: unit %d is not a Luftwaffe SquadNum, leaving the game's default", g_as.unit);
        } else {
            if (g_as.unit < AS_LW_FIRST_UNIT) {
                *(int *)(fav + FAV_GROUP) = 0; *(int *)(fav + FAV_AC) = 0; *(int *)(fav + FAV_SECTOR) = 0;
                *(int *)(fav + FAV_SQUADRON) = g_as.unit;
                LogMsg("autostart: favourite squadron SquadNum %d", g_as.unit);
            } else LogMsg("autostart: unit %d is not an RAF SquadNum, leaving the game's default", g_as.unit);
        }
    }
    LogMsg("autostart: pressing BEGIN (OnSelectRlistbox row 1 on 0x%08X)", (DWORD)(DWORD_PTR)g_asFullpane);
    AsDone("begin");
    ((PFN_OnSelectRlistbox)AS_ONSELECTRLISTBOX)(g_asFullpane, 1, 1);
    LogMsg("autostart: BEGIN returned, campaign map should be up");
    AsDone("ok");
    AsArmExitWatch();
}

/* BACK TO THE SQUADRON ROOM. Leaving a campaign puts the game on its own
 * title menu and it keeps running, so the Room, which comes back when the
 * game closes, never appeared (Patrick, 21 September 2026). After the guard
 * has taken the player into his campaign this watches for that menu and
 * presses its own Quit (ConfirmExit: saves the preferences, restores the
 * display mode, closes the main window; no dialog).
 *
 * The front-end panel the guard steered is DESTROYED when the map opens
 * (CMIGView::LaunchMap) and the title menu afterwards is a new one, so it is
 * found fresh every tick: RDialog::m_pView, then the view's m_pfullpane,
 * which is NULL while the map or the 3D is up. It acts only after it has
 * seen that NULL, i.e. after the campaign was really reached. */
static int g_asSeenMap = 0;
static VOID CALLBACK AsExitWatch(HWND hwnd, UINT msg, UINT_PTR id, DWORD now) {
    char *view = *(char **)AS_MPVIEW;
    char *fp; void *cur; const DWORD *row; int k;
    (void)hwnd; (void)msg; (void)now;
    if (!view || IsBadReadPtr(view + VIEW_FULLPANE, 4)) return;
    fp = *(char **)(view + VIEW_FULLPANE);
    if (!fp) { g_asSeenMap = 1; return; }
    if (!g_asSeenMap || IsBadReadPtr(fp + RF_CURRENTSCREEN, 4)) return;
    cur = *(void **)(fp + RF_CURRENTSCREEN);
    if (cur != (void *)AS_TITLE) return;
    row = (const DWORD *)(AS_TITLE + FS_TEXTLISTS);
    for (k = 0; k < 10; k++, row += 6) {
        if (row[0] == AS_TITLE_TEXT_QUIT && row[1] == 0 && row[2] >= AS_TEXT_LO && row[2] < AS_TEXT_HI && row[3] == 0) break;
    }
    KillTimer(NULL, id);
    if (k >= 10) { LogMsg("autostart: back on the title menu, but no Quit row found; left to the player"); return; }
    LogMsg("autostart: the campaign was left for the title menu; pressing its Quit (row %d) to return to the Squadron Room", k);
    ((PFN_OnSelectRlistbox)AS_ONSELECTRLISTBOX)(fp, k, k);
}
static void AsArmExitWatch(void) {
    g_asSeenMap = 0;
    if (!SetTimer(NULL, 0, 500, AsExitWatch)) LogMsg("autostart: exit watch not started (err=%u)", GetLastError());
    else LogMsg("autostart: watching for the campaign to be left");
}

/* LOAD. The Load Game page's InitProc (SetUpLoadGame) builds the RAF list
 * with the file named by Save_Data.lastsavegame already selected; the game
 * read that name from settings.cfg at start-up, and the Squadron Room wrote
 * the pilot's own save there before launching. For a Luftwaffe pilot the
 * LW tab (row 1, SetUpLWLoadGame) rebuilds the list from the same name.
 * Row 3 is LOAD: DoLoadGame loads selectedfile and launches the map. So
 * this is two presses of the game's own buttons, nothing written. */
static int g_asLoadStep = 0;
static VOID CALLBACK AsLoadTimer(HWND hwnd, UINT msg, UINT_PTR id, DWORD now) {
    void *cur = g_asFullpane ? *(void **)((char *)g_asFullpane + RF_CURRENTSCREEN) : NULL;
    const DWORD *lg = (const DWORD *)(AS_LOADGAME + FS_TEXTLISTS);
    (void)hwnd; (void)msg; (void)now;
    if (cur != (void *)AS_LOADGAME) {
        if (++g_asBeginTries < 25) return;
        KillTimer(NULL, id);
        LogMsg("autostart: Load Game page never became current (screen 0x%08X), leaving it to the player", (DWORD)(DWORD_PTR)cur);
        AsDone("fallback");
        return;
    }
    if (lg[18] != AS_LOADGAME_TEXT_LOAD || lg[20] < AS_TEXT_LO || lg[20] >= AS_TEXT_HI) {
        KillTimer(NULL, id);
        LogMsg("autostart: LOAD row not as expected (text 0x%X, onselect 0x%08X), leaving the page to the player", lg[18], lg[20]);
        AsDone("fallback");
        return;
    }
    if (g_as.side == 1 && g_asLoadStep == 0) {
        g_asLoadStep = 1;
        LogMsg("autostart: Luftwaffe tab (OnSelectRlistbox row 1)");
        ((PFN_OnSelectRlistbox)AS_ONSELECTRLISTBOX)(g_asFullpane, 1, 1);
        return;                                   /* let the list build, press LOAD next tick */
    }
    KillTimer(NULL, id);
    LogMsg("autostart: pressing LOAD (OnSelectRlistbox row 3) for \"%s\"", g_as.save);
    AsDone("load");
    ((PFN_OnSelectRlistbox)AS_ONSELECTRLISTBOX)(g_asFullpane, 3, 3);
    cur = *(void **)((char *)g_asFullpane + RF_CURRENTSCREEN);
    if (cur == (void *)AS_LOADGAME) { LogMsg("autostart: still on the Load Game page after LOAD, the save did not load; left to the player"); AsDone("fallback"); }
    else { LogMsg("autostart: LOAD returned, campaign map should be up"); AsDone("ok"); AsArmExitWatch(); }
}

/* Runs on the game's UI thread, inside OnSelectRlistbox, as introsmack's
 * only row fires. ECX is the RFullPanelDial (row 0's this-delta is checked
 * to be zero before the hook is installed). */
static int __attribute__((thiscall)) AutostartHook(void *self, void **next) {
    int r = g_asOrigOnSelect ? g_asOrigOnSelect(self, next) : 1;
    if (!r) { LogMsg("autostart: CheckLobby vetoed the intro exit"); AsDone("lobby-veto"); return 0; }
    if (InterlockedExchange(&g_as.armed, 0) == 0) return r;
    g_asFullpane = self;
    /* What the title page would have done on the way past: TitleInit resets
     * the replay flags, in3d, incomms, gamestate and the window caption.
     * The side and phase pages only build their panels. Running the title
     * page's own InitProc here (read from the page struct, a thiscall with
     * no arguments) keeps that housekeeping exactly as the game does it;
     * gamestate is set again below. */
    {
        DWORD tip = *(DWORD *)(AS_TITLE + FS_INITPROC);
        if (tip >= AS_TEXT_LO && tip < AS_TEXT_HI) { ((int (__attribute__((thiscall)) *)(void *))tip)(self); LogMsg("autostart: ran TitleInit (0x%08X)", tip); }
        else LogMsg("autostart: title InitProc 0x%08X not in .text, skipped", tip);
    }
    if (g_as.mode == AS_MODE_LOAD) {
        *(DWORD *)AS_GAMESIDE = (DWORD)g_as.side;
        *(BYTE *)AS_SKIPVIDEOS = 1;
        *next = (void *)AS_LOADGAME;
        LogMsg("autostart: side=%d, intro exit rewritten to the Load Game page for \"%s\"", g_as.side, g_as.save);
        g_asBeginTries = 0; g_asLoadStep = 0;
        if (!SetTimer(NULL, 0, 200, AsLoadTimer)) { LogMsg("autostart: SetTimer failed (err=%u)", GetLastError()); AsDone("fallback"); }
        return 1;
    }
    *(DWORD *)AS_GAMESIDE = (DWORD)g_as.side;
    *(DWORD *)AS_GAMESTATE = (DWORD)g_as.role;
    *(DWORD *)((char *)self + RF_WHICHCAMP) = (DWORD)g_as.phase;
    memset((void *)AS_PLAYERNAME, 0, 21);
    strncpy((char *)AS_PLAYERNAME, g_as.name, 20);
    *(BYTE *)AS_SKIPVIDEOS = 1;
    *next = (void *)AS_CAMPENTERNAME;
    LogMsg("autostart: side=%d role=%d phase=%d name=\"%s\", intro exit rewritten to campaignentername", g_as.side, g_as.role, g_as.phase, g_as.name);
    if (g_as.mode == AS_MODE_BEGIN) {
        g_asBeginTries = 0;
        if (!SetTimer(NULL, 0, 200, AsBeginTimer)) { LogMsg("autostart: SetTimer failed (err=%u)", GetLastError()); AsDone("fallback"); }
    } else {
        AsDone("name-page");
    }
    return 1;
}

static DWORD WINAPI AsArmThread(LPVOID p) {
    DWORD waited = 0;
    DWORD *row = (DWORD *)(AS_INTROSMACK + FS_TEXTLISTS);   /* text, nextscreen, onselect, delta */
    DWORD old;
    (void)p;
    /* the dynamic initializers fill InitProc and onselect in; before that the
     * struct is the file image and there is nothing to hook */
    while ((*(DWORD *)(AS_INTROSMACK + FS_INITPROC) == 0 || row[2] == 0) && waited < 30000) { Sleep(2); waited += 2; }
    if (row[2] == 0) { LogMsg("autostart: initializers never ran (waited %u ms)", waited); AsDone("no-init"); return 0; }
    if (row[2] < AS_TEXT_LO || row[2] >= AS_TEXT_HI) { LogMsg("autostart: intro onselect 0x%08X is not in .text", row[2]); AsDone("mismatch"); return 0; }
    if (row[3] != 0) { LogMsg("autostart: intro onselect this-delta is %u, expected 0", row[3]); AsDone("mismatch"); return 0; }
    g_asOrigOnSelect = (PFN_OnSelect)row[2];
    if (!VirtualProtect(&row[2], 4, PAGE_READWRITE, &old)) { LogMsg("autostart: VirtualProtect failed (err=%u)", GetLastError()); AsDone("mismatch"); return 0; }
    row[2] = (DWORD)(DWORD_PTR)AutostartHook;
    VirtualProtect(&row[2], 4, old, &old);
    InterlockedExchange(&g_as.armed, 1);
    LogMsg("autostart: armed after %u ms (CheckLobby was 0x%08X, LaunchMapFirstTime is 0x%08X)", waited, (DWORD)(DWORD_PTR)g_asOrigOnSelect, *(DWORD *)(AS_CAMPENTERNAME + FS_TEXTLISTS + FS_ROW + 8));
    AsDone("armed");
    return 0;
}

static void AutostartInit(void) {
    HANDLE t;
    if (!AsReadRequest()) { LogMsg("no autostart request"); return; }
    if (g_as.mode == AS_MODE_OFF) { AsDone("off"); return; }
    if (g_as.phase < 0 || g_as.phase > 3 || (g_as.side != 0 && g_as.side != 1) || (g_as.role != 4 && g_as.role != 5)) { LogMsg("autostart: request out of range"); AsDone("bad-request"); return; }
    if (!AsVerifyExe()) { AsDone("mismatch"); return; }
    t = CreateThread(NULL, 0, AsArmThread, NULL, 0, NULL);
    if (t) CloseHandle(t); else { LogMsg("autostart: CreateThread failed (err=%u)", GetLastError()); AsDone("mismatch"); }
}

/* ==================== PERFORMANCE PATCHES (bob2guard.ini) ====================
 *
 * Two measured hotspots, from the August CPU profile of a real flight
 * (profiling/README.md): Lib3D::AddTransformedLine 23% of all process
 * time, WeatherClass::IlluminateCloudLo/Hi 16%. Neither is reachable by a
 * wrapper or a setting, both are reachable from here. Both are OFF unless
 * bob2guard.ini beside this DLL says otherwise:
 *
 *     cloudstep=32     texels of the cloud light map lit per frame (game: 256)
 *     lines=1          replace the line copy
 *
 * CLOUD STEP. The cloud light map is 512x512 texels; each texel is a ray
 * march of up to 512 steps through a 2048x2048 height map, twice (Lo and
 * Hi). WeatherClass::InitClouds sets CloudXStep = 256 texels per frame and
 * UpdateCloudLightMap does that many every frame, camera or no camera,
 * cloud on screen or not. A smaller step does less per frame and only
 * slows how fast the light map follows the sun (256: the whole map every
 * ~1024 frames; 32: every ~8192). A thread watches the field and writes the
 * configured value whenever the game has put 256 back, so a mission
 * re-init is covered too. A data write, nothing patched.
 *
 * LINES. The game already batches its lines: every one goes through
 * Renderer::AddPrimitive into one dynamic vertex buffer and out as one
 * DrawPrimitive per 1024 lines. What costs 23% is HOW each line is
 * written: two rep movsd into static scratch buffers, then twenty
 * fld/fstp pairs, one float at a time with an add between, into the
 * vertex buffer, which is mapped WRITE_DISCARD, i.e. write-combined
 * uncached memory. The replacement does the same three things and nothing
 * else: SetRenderState(0x404), AddPrimitive(2, PT_LINE_LIST, 0), then the
 * 80 bytes (SLine+4 for 40, SLine+0x40 for 40; that is exactly what the
 * original's twenty stores carry, verified from the bytes) as five 16-byte
 * stores from an aligned copy. The GetViewPort call the original makes is
 * dropped: its outputs are never used. Installed as a 5-byte jmp at the
 * function entry after the first 16 bytes are checked; the original bytes
 * go back on detach. Lines share one render state, no texture, their own
 * buffer, and are radix-sorted before drawing, so nothing about order or
 * state changes.
 *
 * Addresses are Bob.exe 2.13 (AUTOSTART.md has the exe identity check;
 * each patch also checks its own bytes). 2.12 for re-pinning: Weather
 * instance by the same thiscall scan, AddTransformedLine 0x005427e0,
 * SetRenderState/AddPrimitive via names213.json.
 */
#define PF_WEATHER           0x0556b690u   /* the WeatherClass instance (35 refs in .text) */
#define PF_CLOUDXSTEP        (PF_WEATHER + 13941)
#define PF_CLOUDXSTEP_GAME   256
#define PF_ADDTRANSFORMEDLINE 0x00541380u  /* Lib3D::AddTransformedLine, thiscall(SLine**) */
#define PF_SETRENDERSTATE    0x005274d0u   /* Renderer::SetRenderState, thiscall(ulong) */
#define PF_ADDPRIMITIVE      0x00529fe0u   /* Renderer::AddPrimitive, thiscall(int nverts, int primtype, int flags) -> vertex ptr */
#define PF_THERENDERER       0x00861d68u
static const unsigned char PF_SIG_ATL[16] = { 0x83,0xec,0x10,0xf6,0x05,0x90,0xbb,0xa4,0x00,0x01,0x75,0x1e,0x83,0x0d,0x90,0xbb };
static const unsigned char PF_SIG_SRS[8]  = { 0x8b,0x44,0x24,0x04,0x83,0xca,0xff,0x3b };
static const unsigned char PF_SIG_AP[8]   = { 0x8b,0x54,0x24,0x08,0x83,0xfa,0x02,0x53 };
static const unsigned char PF_SIG_UCLM[8] = { 0x53,0x55,0x56,0x57,0x8b,0xf1,0x33,0xdb };  /* UpdateCloudLightMap reads [esi+0x3675] */

typedef void (__attribute__((thiscall)) *PFN_SetRenderState)(void *self, unsigned flags);
typedef unsigned char *(__attribute__((thiscall)) *PFN_AddPrimitive)(void *self, int nverts, int primtype, int flags);

static int  g_pfCloudStep = 0;          /* 0: off */
static int  g_pfLines = 0;
static unsigned char g_pfAtlOriginal[5];
static int  g_pfAtlPatched = 0;
static volatile unsigned long g_pfLineCalls = 0;
static volatile unsigned long g_pfCloudWrites = 0;

static void __attribute__((thiscall)) PfLineFast(void *self, unsigned char **pline) {
    const unsigned char *ln = *pline;
    unsigned char tmp[80] __attribute__((aligned(16)));
    unsigned char *dst;
    (void)self;
    ((PFN_SetRenderState)PF_SETRENDERSTATE)((void *)PF_THERENDERER, 0x404);
    dst = ((PFN_AddPrimitive)PF_ADDPRIMITIVE)((void *)PF_THERENDERER, 2, 1, 0);
    memcpy(tmp, ln + 4, 40);
    memcpy(tmp + 40, ln + 0x40, 40);
    _mm_storeu_si128((__m128i *)(dst +  0), _mm_load_si128((const __m128i *)(tmp +  0)));
    _mm_storeu_si128((__m128i *)(dst + 16), _mm_load_si128((const __m128i *)(tmp + 16)));
    _mm_storeu_si128((__m128i *)(dst + 32), _mm_load_si128((const __m128i *)(tmp + 32)));
    _mm_storeu_si128((__m128i *)(dst + 48), _mm_load_si128((const __m128i *)(tmp + 48)));
    _mm_storeu_si128((__m128i *)(dst + 64), _mm_load_si128((const __m128i *)(tmp + 64)));
    g_pfLineCalls++;
}

static int PfReadIni(void) {
    char dllPath[MAX_PATH], ini[MAX_PATH], line[256], *slash;
    FILE *f;
    if (!GetModuleFileNameA(g_ourDLL, dllPath, MAX_PATH)) return 0;
    slash = strrchr(dllPath, '\\'); if (!slash) return 0;
    slash[1] = '\0';
    wsprintfA(ini, "%sbob2guard.ini", dllPath);
    f = fopen(ini, "r");
    if (!f) return 0;
    while (fgets(line, sizeof(line), f)) {
        char *eq = strchr(line, '=');
        if (!eq || line[0] == '#' || line[0] == ';') continue;
        *eq = '\0';
        if      (!strcmp(line, "cloudstep")) g_pfCloudStep = atoi(eq + 1);
        else if (!strcmp(line, "lines"))     g_pfLines = atoi(eq + 1);
    }
    fclose(f);
    return 1;
}

static int PfInstallLineHook(void) {
    unsigned char *entry = (unsigned char *)PF_ADDTRANSFORMEDLINE;
    unsigned char jmp[5];
    DWORD old, rel;
    if (memcmp(entry, PF_SIG_ATL, 16) || memcmp((void *)PF_SETRENDERSTATE, PF_SIG_SRS, 8) || memcmp((void *)PF_ADDPRIMITIVE, PF_SIG_AP, 8)) {
        LogMsg("perf: line hook NOT installed, code signature differs");
        return 0;
    }
    memcpy(g_pfAtlOriginal, entry, 5);
    rel = (DWORD)(DWORD_PTR)PfLineFast - (PF_ADDTRANSFORMEDLINE + 5);
    jmp[0] = 0xe9; memcpy(jmp + 1, &rel, 4);
    if (!VirtualProtect(entry, 16, PAGE_EXECUTE_READWRITE, &old)) { LogMsg("perf: VirtualProtect failed (err=%u)", GetLastError()); return 0; }
    memcpy(entry, jmp, 5);
    VirtualProtect(entry, 16, old, &old);
    FlushInstructionCache(GetCurrentProcess(), entry, 16);
    g_pfAtlPatched = 1;
    LogMsg("perf: line copy replaced (AddTransformedLine 0x%08X -> 0x%08X)", PF_ADDTRANSFORMEDLINE, (DWORD)(DWORD_PTR)PfLineFast);
    return 1;
}

static void PfRemoveLineHook(void) {
    unsigned char *entry = (unsigned char *)PF_ADDTRANSFORMEDLINE;
    DWORD old;
    if (!g_pfAtlPatched) return;
    if (VirtualProtect(entry, 16, PAGE_EXECUTE_READWRITE, &old)) {
        memcpy(entry, g_pfAtlOriginal, 5);
        VirtualProtect(entry, 16, old, &old);
        FlushInstructionCache(GetCurrentProcess(), entry, 16);
    }
    g_pfAtlPatched = 0;
}

/* Watches CloudXStep and keeps it at the configured value; logs the line
 * count every five seconds while either patch is on. */
static DWORD WINAPI PfThread(LPVOID p) {
    DWORD last = GetTickCount();
    unsigned long lastLines = 0;
    (void)p;
    for (;;) {
        Sleep(100);
        if (g_pfCloudStep > 0) {
            volatile int *step = (volatile int *)PF_CLOUDXSTEP;
            if (*step == PF_CLOUDXSTEP_GAME) { *step = g_pfCloudStep; g_pfCloudWrites++; LogMsg("perf: CloudXStep %d -> %d", PF_CLOUDXSTEP_GAME, g_pfCloudStep); }
        }
        if (GetTickCount() - last >= 5000) {
            unsigned long n = g_pfLineCalls;
            if (g_pfLines && n != lastLines) LogMsg("perf: %lu lines in the last 5 s (%lu/s)", n - lastLines, (n - lastLines) / 5);
            lastLines = n; last = GetTickCount();
        }
    }
    return 0;
}

static void PfInit(void) {
    HANDLE t;
    if (!PfReadIni()) { LogMsg("perf: no bob2guard.ini, patches off"); return; }
    if (g_pfCloudStep < 0 || g_pfCloudStep > 256) g_pfCloudStep = 0;
    LogMsg("perf: bob2guard.ini cloudstep=%d lines=%d", g_pfCloudStep, g_pfLines);
    if (!g_pfCloudStep && !g_pfLines) return;
    if (g_pfCloudStep && memcmp((void *)0x00631746u, PF_SIG_UCLM, 8)) { LogMsg("perf: cloud step NOT applied, UpdateCloudLightMap signature differs"); g_pfCloudStep = 0; }
    if (g_pfLines) { if (!PfInstallLineHook()) g_pfLines = 0; }
    if (g_pfCloudStep || g_pfLines) { t = CreateThread(NULL, 0, PfThread, NULL, 0, NULL); if (t) CloseHandle(t); }
}

/* ==================== DLLMAIN ==================== */

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinstDLL);
        g_ourDLL = hinstDLL;

        OpenLog();
        LogMsg("DllMain: DLL_PROCESS_ATTACH");

        if (!LoadRealDInput8()) {
            if (g_logFile) { fclose(g_logFile); g_logFile = NULL; }
            return FALSE;
        }

        PVOID handler = AddVectoredExceptionHandler(1, VectoredHandler);
        LogMsg("VEH installed: %s (breakpoint + SxS guard)", handler ? "YES" : "NO");
        LogMsg("Crash guard ACTIVE");
        AutostartInit();
        PfInit();
    }
    else if (fdwReason == DLL_PROCESS_DETACH) {
        PfRemoveLineHook();
        if (g_logFile) {
            LogMsg("=== Unloading (skipped %u breakpoints, %u SxS errors, %u RCombo AV) ===", g_bpCount, g_sxsCount, g_avCount);
            fclose(g_logFile);
            g_logFile = NULL;
        }
        if (g_realDInput8) {
            FreeLibrary(g_realDInput8);
            g_realDInput8 = NULL;
        }
    }
    return TRUE;
}
