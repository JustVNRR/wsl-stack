# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # Injected by wsl.ps1, or made below once the shared half is loaded: the
    # type cannot be named here - a parameter is bound before this file's first
    # line runs, and a fresh pwsh knows nothing of the classes (measured:
    # "Unable to find type [WslInstanceManager]" at bind).
    $Manager
)

# No parameter on purpose: the instance comes from the list - a name typed by
# heart is a name you can get wrong.

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

# One working folder, no guessing: provided by the engine. Read here, not
# higher: the manager may be the one the load just settled.
$Root = $Manager.InstancesRoot

# 1. Which instance
$Distro = Select-Distro
if (-not $Distro) { Stop-Cancelled }
$DistroName = $Distro.Name

$BeforeBytes = Get-VhdxSize $Distro.Path

Write-Host ""
Write-Host "==> Reclaiming space in '$DistroName'" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Disk file now    : $(Format-Size $BeforeBytes)" -ForegroundColor (Get-MessageColour muted)
Write-Host ""
Write-Host "  This compacts the instance's virtual disk: the space its filesystem has" -ForegroundColor (Get-MessageColour muted)
Write-Host "  freed over time comes back to Windows. Nothing inside is touched." -ForegroundColor (Get-MessageColour muted)

# 2. A copy first, yes by default: compacting rewrites the disk's metadata -
# exactly what a backup a minute before turns into a non-event.
Write-Host ""
if (-not (Confirm-YesNo "Archive it first?")) {
    Write-Host "  No archive - compacting on its own." -ForegroundColor (Get-MessageColour muted)
} else {
    # Typing an existing name is how an archive is replaced - said, not done
    # quietly.
    $ArchiveDir = Join-Path $Manager.ArchivesRoot $DistroName
    if (Test-Path $ArchiveDir) {
        Write-Host "  '$DistroName' exists: replacing its archive." -ForegroundColor (Get-MessageColour warning)
    }
    try {
        Write-Host "==> Creating safety archive..." -ForegroundColor (Get-MessageColour info)
        $null = $Manager.Archive($Distro, $DistroName, "tar.gz")
    } catch {
        Write-Host ""
        Write-Host "[ABORT] The archive did not complete - nothing was compacted: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
        Write-Host "        The instance is exactly as it was." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }
}

# 3. Compact. Delegated to the engine: it compacts the disk, tracks the delta,
# and automatically restarts the instance if it was running beforehand.
Write-Host ""
Write-Host "==> Compacting the virtual disk..." -ForegroundColor (Get-MessageColour info)
try {
    $Result = $Manager.Shrink($Distro)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        The instance is untouched." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$DistroName' compacted" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Disk file        : " -NoNewline
Write-Host "$(Format-Size $Result.Before) -> $(Format-Size $Result.After)" -ForegroundColor (Get-MessageColour info)
if ($Result.Freed -gt 0) {
    Write-Host "  * Reclaimed        : " -NoNewline; Write-Host "$(Format-Size $Result.Freed)" -ForegroundColor (Get-MessageColour success)
} else {
    Write-Host "  * Reclaimed        : " -NoNewline
    Write-Host "nothing - the disk held no space to give back" -ForegroundColor (Get-MessageColour muted)
}

# 4. Left the way it was found (reported from the engine's return).
if ($Result.WasRunning) {
    if ($Result.Restarted) {
        Write-Host "'$DistroName' is running again." -ForegroundColor (Get-MessageColour success)
    } else {
        Write-Host "Could not start '$DistroName' - start it with: wsl -d $DistroName" -ForegroundColor (Get-MessageColour warning)
    }
    Write-Host ""
}