<#
.SYNOPSIS
    Installs the FFmpeg context menu converter.
.DESCRIPTION
    Adds "Convert with FFmpeg" to the right-click context menu for video and audio files.
    Must be run as Administrator.
#>

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Get the script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConverterScript = Join-Path $ScriptDir "convert-media.ps1"

# File extensions to register
$VideoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv', '.m4v')
$AudioExtensions = @('.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus')
$AllExtensions = $VideoExtensions + $AudioExtensions

# Registry paths
$MenuName = "ConvertWithFFmpeg"
$MenuLabel = "Convert with FFmpeg"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-ContextMenu {
    Write-Host "Installing FFmpeg context menu..." -ForegroundColor Green

    # Check if converter script exists
    if (-not (Test-Path $ConverterScript)) {
        throw "Converter script not found: $ConverterScript"
    }

    # Build the command
    $command = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ConverterScript`" `"%1`""

    foreach ($ext in $AllExtensions) {
        $regPath = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\$MenuName"

        Write-Host "  Registering $ext..." -ForegroundColor Cyan

        # Create the menu entry
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "(Default)" -Value $MenuLabel
        Set-ItemProperty -Path $regPath -Name "Icon" -Value "shell32.dll,145"

        # Create the command subkey
        $commandPath = "$regPath\command"
        if (-not (Test-Path $commandPath)) {
            New-Item -Path $commandPath -Force | Out-Null
        }
        Set-ItemProperty -Path $commandPath -Name "(Default)" -Value $command
    }

    Write-Host ""
    Write-Host "Installation complete!" -ForegroundColor Green
    Write-Host "Right-click any supported media file to see 'Convert with FFmpeg'" -ForegroundColor Yellow
}

function Uninstall-ContextMenu {
    Write-Host "Uninstalling FFmpeg context menu..." -ForegroundColor Yellow

    foreach ($ext in $AllExtensions) {
        $regPath = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell\$MenuName"

        if (Test-Path $regPath) {
            Write-Host "  Removing $ext..." -ForegroundColor Cyan
            Remove-Item -Path $regPath -Recurse -Force
        }
    }

    Write-Host ""
    Write-Host "Uninstallation complete!" -ForegroundColor Green
}

# Main
if ($Uninstall) {
    Uninstall-ContextMenu
}
else {
    Install-ContextMenu
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
