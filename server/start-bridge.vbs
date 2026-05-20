' Silent launcher: runs start-bridge.bat with no visible window.
' Resolves its own location so it works regardless of where the repo lives.
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = scriptDir
sh.Run """" & scriptDir & "\start-bridge.bat""", 0, False
