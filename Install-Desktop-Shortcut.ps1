Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop = [Environment]::GetFolderPath('Desktop')
$startup = [Environment]::GetFolderPath('Startup')
$desktopShortcut = Join-Path $desktop 'CR7 Codex Pet.lnk'
$startupShortcut = Join-Path $startup 'CR7 Codex Pet.lnk'
$launcher = Join-Path $appRoot 'Start-CR7-Pet.vbs'
$icon = Join-Path $appRoot 'assets\cr7-pet.ico'

$shell = New-Object -ComObject WScript.Shell
function New-PetShortcut {
    param([string]$Path, [string]$Description)
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"{0}"' -f $launcher
    $shortcut.WorkingDirectory = $appRoot
    $shortcut.IconLocation = '{0},0' -f $icon
    $shortcut.Description = $Description
    $shortcut.Save()
}

New-PetShortcut -Path $desktopShortcut -Description 'Animated CR7 Codex desktop pet'
New-PetShortcut -Path $startupShortcut -Description 'Launch CR7 Codex Pet at sign-in'

foreach ($path in @($desktopShortcut, $startupShortcut)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Shortcut creation failed: $path"
    }
}

[pscustomobject]@{
    DesktopShortcut = $desktopShortcut
    StartupShortcut = $startupShortcut
}
