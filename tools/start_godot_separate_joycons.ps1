param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$godotName = 'Godot_v4.7.2-stable_win64.exe'
$godotPath = $null
$searchRoots = @($env:OneDrive, $env:OneDriveConsumer, $env:USERPROFILE) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
    Select-Object -Unique
foreach ($root in $searchRoots) {
    $directCandidate = Join-Path $root $godotName
    if (Test-Path -LiteralPath $directCandidate -PathType Leaf) {
        $godotPath = $directCandidate
        break
    }
    foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue) {
        $childCandidate = Join-Path $directory.FullName $godotName
        if (Test-Path -LiteralPath $childCandidate -PathType Leaf) {
            $godotPath = $childCandidate
            break
        }
    }
    if ($godotPath) {
        break
    }
}
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $godotPath) {
    throw "Godot executable was not found below the user profile or OneDrive folders: $godotName"
}
if (-not (Test-Path -LiteralPath (Join-Path $projectPath 'project.godot') -PathType Leaf)) {
    throw "Godot project was not found: $projectPath"
}

$env:SDL_JOYSTICK_HIDAPI_COMBINE_JOY_CONS = '0'
$env:SDL_JOYSTICK_HIDAPI_VERTICAL_JOY_CONS = '0'

if ($CheckOnly) {
    Write-Output "Godot: $godotPath"
    Write-Output "Project: $projectPath"
    Write-Output "Combine Joy-Cons: $env:SDL_JOYSTICK_HIDAPI_COMBINE_JOY_CONS"
    Write-Output "Vertical Joy-Cons: $env:SDL_JOYSTICK_HIDAPI_VERTICAL_JOY_CONS"
    exit 0
}

Start-Process -FilePath $godotPath -ArgumentList @('--editor', '--path', $projectPath)
