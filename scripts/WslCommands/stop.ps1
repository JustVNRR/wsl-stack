# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager
)

# No instance parameter on purpose: the instance comes from the list of running ones - a
# name typed by heart is a name you can get wrong.

$ErrorActionPreference = "Stop"

# 1. Who can be stopped: our running instances, and only those.
$Distro = Select-EligibleInstance -Manager $Manager -State Running `
    -Title "Running instances - the ones that can be stopped:" `
    -None "No instance is running." -Nothing "Nothing to stop."

$DistroName = $Distro.Name

# 2. Stopping is the one thing here that can lose work: what is open and
# unsaved goes with it, the disk is not touched. Asked once, default yes -
# picking the instance was already deliberate.
Write-Host ""
Write-Host "  '$DistroName' will be stopped." -ForegroundColor (Get-MessageColour warning)
Write-Host "  Whatever is open in there and not saved is lost; what is already" -ForegroundColor (Get-MessageColour warning)
Write-Host "  written on the disk stays exactly as it is." -ForegroundColor (Get-MessageColour warning)
if (-not (Confirm-YesNo "Stop it?")) { Stop-Cancelled }

Write-Host ""
Write-Host "==> Stopping '$DistroName'..." -ForegroundColor (Get-MessageColour info)
try {
    # Hand the gesture over to the engine - the one door every interface calls;
    # the state moves on the instance itself.
    $null = $Manager.Stop($Distro)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        '$DistroName' may still be running." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$DistroName' is stopped" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Install folder   : " -NoNewline; Write-Host "$($Distro.Path)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Disk file        : " -NoNewline; Write-Host "$(Format-Size (Get-VhdxSize $Distro.Path))" -ForegroundColor (Get-MessageColour info)
Write-Host ""
Write-Host "  Nothing on the disk was touched: closing an instance only ends what" -ForegroundColor (Get-MessageColour muted)
Write-Host "  was running. Start it again with  .\wsl.ps1 start" -ForegroundColor (Get-MessageColour muted)
Write-Host ""