Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strPath = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = strPath

' Launch QuickShare background launcher silently
If fso.FileExists(strPath & "\QuickShareStudio.exe") Then
    WshShell.Run """" & strPath & "\QuickShareStudio.exe""", 0, False
Else
    WshShell.Run "cmd /c """ & strPath & "\QuickShareSilent.bat""", 0, False
End If
