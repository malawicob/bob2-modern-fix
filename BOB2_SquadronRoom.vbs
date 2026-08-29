' =====================================================================
'  The Squadron Room - console-free start
'  Part of BOB2 Windows 10/11 Fix
' =====================================================================
'
'  Same reasoning as BOB2_Config.vbs: wscript.exe is a GUI process with
'  no console of its own, so Run with intWindowStyle 0 starts PowerShell
'  hidden and nothing is ever drawn (Windows Terminal ignores
'  -WindowStyle Hidden on its own).
'
'  Run this directly to open the Squadron Room. It will be wired into the
'  launcher once tested.
' =====================================================================

Option Explicit

Dim sh, fso, here, ps1, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = fso.BuildPath(here, "BOB2_SquadronRoom.ps1")

If Not fso.FileExists(ps1) Then
    MsgBox "BOB2_SquadronRoom.ps1 is not next to this file." & vbCrLf & vbCrLf & _
           "Expected:" & vbCrLf & ps1, 16, "Battle of Britain II"
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"

' 0 = hidden window, False = do not wait for it to finish
sh.Run cmd, 0, False
