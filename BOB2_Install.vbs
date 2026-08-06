' =====================================================================
'  BOB2 Install and Repair - console-free start
'  Part of BOB2 Windows 10/11 Fix
' =====================================================================
'
'  WHY THIS FILE EXISTS
'    Starting the launcher with "powershell -WindowStyle Hidden" is not
'    enough. When Windows Terminal is set as the default terminal
'    application - which it is by default on Windows 11 - it hosts the
'    console in its own window and ignores the requested show state
'    entirely. The result is a black "powershell.exe" window parked
'    behind the launcher for the whole session.
'
'    wscript.exe is a GUI process with no console of its own, and Run
'    with intWindowStyle 0 creates PowerShell hidden from the outset, so
'    nothing is ever drawn. The launcher additionally hides its own
'    console window at startup as a fallback.
'
'  This is started by BOB2.bat. You can also run it directly.
' =====================================================================

Option Explicit

Dim sh, fso, here, ps1, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = fso.BuildPath(here, "BOB2_Install.ps1")

If Not fso.FileExists(ps1) Then
    MsgBox "BOB2_Install.ps1 is not next to this file." & vbCrLf & vbCrLf & _
           "Expected:" & vbCrLf & ps1, 16, "Battle of Britain II"
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"

' 0 = hidden window, False = do not wait for it to finish
sh.Run cmd, 0, False
