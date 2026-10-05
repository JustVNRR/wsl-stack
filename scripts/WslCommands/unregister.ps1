[CmdletBinding()]
param (
    # Injected by wsl.ps1, or instantiated on-demand if executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())
)

# No parameter on purpose: the instance comes from the list, never from the
# command line, and the removal asks for the name to be typed before anything
# happens. This script never chooses its own target.

$ErrorActionPreference = "Stop"

# Where the instances live, provided by the engine.
$Root = $Manager.InstancesRoot

# The family's shared half: the marker that tells our instances from any other -
# a removal that cannot tell them apart targets whatever the registry holds.
$InstanceLib = Join-Path $PSScriptRoot "..\instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# ==============================================================================
# 1. WHICH DISTRO (from the list, always)
# ==============================================================================
# The list is the only way in. A folder left behind by an earlier removal is
# deleted by hand, not by naming it here.
$Ours = @($Manager.OursHere())
if ($Ours.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No instance of this template is registered on this machine." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing to remove." -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Build one with  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        (A folder left behind by an earlier removal is deleted by hand: $Root)" -ForegroundColor (Get-MessageColour muted)
    exit 1
}

$Distro = Select-Distro
if (-not $Distro) { Stop-Cancelled }

$DistroName = $Distro.Name
$InstallPath = $Distro.Path

# ==============================================================================
# 2. CONFIRMATION (destructive) - the gate build asks too, written once.
# ==============================================================================
if (-not (Confirm-Destruction -DistroName $DistroName -Lead "The WSL distribution '$DistroName' and ALL its data will be deleted:")) {
    Write-Host "[ABORT] Operation cancelled. No data was modified." -ForegroundColor (Get-MessageColour warning)
    exit 0
}

# The last moment to take a copy. Handed to the engine via Unregister($Instance, $ArchiveFirst).
Write-Host ""
$ArchiveFirst = Confirm-YesNo "Archive it before deleting?" -DefaultNo

# The same name is replaced without a word, otherwise - said, not quiet.
if ($ArchiveFirst) {
    $ArchiveDir = Join-Path $Manager.ArchivesRoot $DistroName
    if (Test-Path $ArchiveDir) {
        Write-Host "  '$DistroName' exists: replacing its archive." -ForegroundColor (Get-MessageColour warning)
    }
}

Write-Host "==> Stopping the distro processes..." -ForegroundColor (Get-MessageColour info)
Write-Host "==> Unregistering the distro..." -ForegroundColor (Get-MessageColour info)

# Hand execution to the engine: executes Archive if requested, unregisters, cleans folders and refreshes state
try {
    $Report = $Manager.Unregister($Distro, $ArchiveFirst)
    $Removed = $Report.Removed
} catch {
    Write-Host ""
    Write-Host "[ERROR] Could not unregister '$DistroName': $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    exit 1
}

# ==============================================================================
# 3. WHAT BECAME OF IT (reported; the removal itself was the instance's)
# ==============================================================================
if ($Removed.FolderState -eq "removed") {
    Write-Host "==> Removing installation folder ($InstallPath)..." -ForegroundColor (Get-MessageColour info)
} elseif ($Removed.FolderState -eq "removed with the distribution") {
    Write-Host "==> Installation folder already gone - wsl --unregister removes it with the distribution." -ForegroundColor (Get-MessageColour info)
} else {
    Write-Host "==> No installation folder found ($InstallPath)." -ForegroundColor (Get-MessageColour info)
}

# ==============================================================================
# 4. WINDOWS TERMINAL AND DOCKER (reported; the cleaning was the instance's)
# ==============================================================================
Write-Host "==> Cleaning Windows Terminal leftovers..." -ForegroundColor (Get-MessageColour info)
foreach ($SettingsPath in $Removed.Unreadable) {
    Write-Host "  * settings.json : ghost entries NOT pruned in $SettingsPath" -ForegroundColor (Get-MessageColour warning)
    Write-Host "                    (unreadable JSON - a // comment breaks ConvertFrom-Json; remove them by hand)" -ForegroundColor (Get-MessageColour muted)
}
if ($Removed.GhostsPruned -gt 0) {
    Write-Host "  * settings.json : pruned $($Removed.GhostsPruned) ghost '$DistroName' entries" -ForegroundColor (Get-MessageColour success)
}
if ($Removed.FragmentsRemoved -gt 0) {
    Write-Host "  * fragments     : removed $($Removed.FragmentsRemoved) appearance file(s)" -ForegroundColor (Get-MessageColour success)
}
if ($Removed.DockerError) {
    Write-Host "  * Docker Desktop : list not updated ($($Removed.DockerError))" -ForegroundColor (Get-MessageColour warning)
} elseif ($Removed.DockerRemoved) {
    Write-Host "  * Docker Desktop : '$DistroName' removed from the integrated distros" -ForegroundColor (Get-MessageColour success)
}

# ==============================================================================
# SUMMARY
# ==============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "                WSL Stack Instance Removed!                 " -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Distro          : " -NoNewline; Write-Host "$DistroName" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Install folder  : " -NoNewline
if ($Removed.FolderState -eq "removed") {
    Write-Host "$($Removed.FolderState)" -ForegroundColor (Get-MessageColour success)
} else {
    Write-Host "$($Removed.FolderState)" -ForegroundColor (Get-MessageColour muted)
}
Write-Host "  * Terminal ghosts : " -NoNewline; Write-Host "$($Removed.GhostsPruned) pruned" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Fragments       : " -NoNewline; Write-Host "$($Removed.FragmentsRemoved) removed" -ForegroundColor (Get-MessageColour info)

if ($Report.Archive) {
    Write-Host "  * Backup archive  : " -NoNewline; Write-Host "$($Report.Archive.Destination)" -ForegroundColor (Get-MessageColour success)
}

Write-Host ""
Write-Host " Restart Windows Terminal to refresh the profile list."
Write-Host ""