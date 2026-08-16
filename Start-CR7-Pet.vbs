Option Explicit

Dim shell, fileSystem, appRoot, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

appRoot = fileSystem.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
    & appRoot & "\CR7Pet.ps1"""

shell.Run command, 0, False
