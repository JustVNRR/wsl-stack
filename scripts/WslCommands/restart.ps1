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

# No parameter on purpose: the instance comes from the list of running ones - a
# name typed by heart is a name you can get wrong.

$ErrorActionPreference = "Stop"

# 1. Who can be restarted: our running instances, and only those.
$Distro = Select-EligibleInstance -Manager $Manager -State Running `
    -Title "Running instances - the ones that can be restarted:" `
    -None "No instance is running." -Nothing "Nothing to restart."

$DistroName = $Distro.Name

# 2. A restart is a stop with a start behind it, and stopping is the one thing
# here that can lose work: what is open and unsaved goes with it, the disk is
# not touched. Asked once, default yes.
Write-Host ""
Write-Host "  '$DistroName' will be stopped, then started again." -ForegroundColor (Get-MessageColour warning)
Write-Host "  Whatever is open in there and not saved is lost; what is already" -ForegroundColor (Get-MessageColour warning)
Write-Host "  written on the disk stays exactly as it is." -ForegroundColor (Get-MessageColour warning)
if (-not (Confirm-YesNo "Restart it?")) { Stop-Cancelled }

# 3. In the order that makes the second half a fresh boot: WSL reads
# /etc/wsl.conf and /etc/resolv.conf when the instance boots - the point of the
# command. Gesture by gesture: each half fails on its own, and each failure
# gets the line that says where the instance stands.
Write-Host ""
Write-Host "==> Stopping '$DistroName'..." -ForegroundColor (Get-MessageColour info)
try {
    $null = $Manager.Stop($Distro)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        '$DistroName' may still be running, and was not started again." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "==> Starting '$DistroName'..." -ForegroundColor (Get-MessageColour info)
try {
    $null = $Manager.Start($Distro)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        '$DistroName' is stopped - start it with  .\wsl.ps1 start" -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$DistroName' is running again" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Install folder   : " -NoNewline; Write-Host "$($Distro.Path)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Disk file        : " -NoNewline; Write-Host "$(Format-Size (Get-VhdxSize $Distro.Path))" -ForegroundColor (Get-MessageColour info)
Write-Host ""
Write-Host ""
