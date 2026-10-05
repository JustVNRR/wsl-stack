[CmdletBinding()]
param (
    # Injected by wsl.ps1, or made below once the shared half is loaded: the
    # type cannot be named here - a parameter is bound before this file's first
    # line runs, and a fresh pwsh knows nothing of the classes (measured:
    # "Unable to find type [WslInstanceManager]" at bind).
    $Manager
)

# No parameter on purpose: the instance comes from the list of stopped ones - a
# name typed by heart is a name you can get wrong.

$ErrorActionPreference = "Stop"

# The family's shared half: the marker.
$InstanceLib = Join-Path $PSScriptRoot "..\instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# Run on its own, nothing was injected: the manager is made here, once the
# shared half is loaded and its class has a name.
if (-not $Manager) { $Manager = [WslInstanceManager]::new([WslInstanceManager]::Root()) }

# 1. Who can be started: our stopped instances, and only those.
$Distro = Select-EligibleInstance -Manager $Manager -State Stopped `
    -Title "Stopped instances - the ones that can be started:" `
    -None "Every registered instance is already running." -Nothing "Nothing to start."

$DistroName = $Distro.Name

# 2. Start it.
Write-Host ""
Write-Host "==> Starting '$DistroName'..." -ForegroundColor (Get-MessageColour info)
try {
    # Hand the gesture over to the engine - the one door every interface calls;
    # the state moves on the instance itself.
    $null = $Manager.Start($Distro)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        '$DistroName' is not running." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$DistroName' is running" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Install folder   : " -NoNewline; Write-Host "$($Distro.Path)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Disk file        : " -NoNewline; Write-Host "$(Format-Size (Get-VhdxSize $Distro.Path))" -ForegroundColor (Get-MessageColour info)
Write-Host ""
