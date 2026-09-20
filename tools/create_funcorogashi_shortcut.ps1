$ErrorActionPreference = 'Stop'

$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot 'start_godot_separate_joycons.ps1')).Path
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath 'funcorogashi - Godot.lnk'
$powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcherPath + '"'
$shortcut.WorkingDirectory = $projectPath
$shortcut.Description = 'Open funcorogashi with separate horizontal Joy-Cons'
$shortcut.Save()

Write-Output "Created: $shortcutPath"
Write-Output 'This shortcut applies the Joy-Con settings only to the Godot process it starts.'
