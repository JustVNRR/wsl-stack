[CmdletBinding()]
param (
    # Injected by wsl.ps1, or instantiated on-demand if executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())
)

# No parameter on purpose: the source comes from the list, never from the
# command line, and the copy's name is asked for.

$ErrorActionPreference = "Stop"

# The family's shared half: the marker, and the Windows-side look - captured
# off the source by the engine, re-applied to the copy after the import.
$InstanceLib = Join-Path $PSScriptRoot "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# 0. Which instance to copy
$Source = Select-Distro
$SourceDistro = $Source.Name

# 0-bis. The copy's name: typed, because there is nothing to pick from. The
# question comes back until the name is usable.
while ($true) {
    $Answer = [string](Read-Host "Name of the copy")
    if ([string]::IsNullOrWhiteSpace($Answer)) {
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was created." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
    if (Test-InstanceName $Answer.Trim()) {
        $NewDistroName = $Answer.Trim()
        break
    }
    Write-Host "  Letters, digits, '.', '_' and '-' only." -ForegroundColor (Get-MessageColour hint)
}

# This script never unregisters anything, so a name already taken is a dead
# end, not something to resolve - the engine answers whether the name is free.
if (-not $Manager.IsNameAvailable($NewDistroName)) {
    Write-Host ""
    Write-Host "[ABORT] An instance named '$NewDistroName' already exists." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Pick another name." -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

# The export stops the source - WSL terminates it to read a consistent disk -
# and unsaved work is gone: ask rather than surprise.
$StoppedByUs = $false
if ((Get-DistroNames -Running) -contains $SourceDistro) {
    Write-Host ""
    Write-Host "  '$SourceDistro' is running, and this needs it stopped." -ForegroundColor (Get-MessageColour warning)
    Write-Host "  Save what you have open in there: stopping it loses anything unsaved." -ForegroundColor (Get-MessageColour warning)
    if (-not (Confirm-YesNo "Stop it now?")) {
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
    $null = $Manager.Stop($Source)
    Write-Host "  Stopped." -ForegroundColor (Get-MessageColour muted)
    $StoppedByUs = $true
}

# 1-2. What it costs, measured by the engine: the copy reads the instance into
# an archive and unpacks it into the new folder, both at the same time - twice
# the disk is the peak checked here. The archive route rather than a raw disk
# copy (`--format vhd`): a vhd export is refused with ERROR_SHARING_VIOLATION
# while the WSL virtual machine is up - `--terminate` does not release it, only
# a full `--shutdown` does, and that stops every other instance. The copy pays
# the compression instead.
$Cost = $Manager.DuplicationCost($Source, $NewDistroName)

Write-Host ""
Write-Host "==> Duplicating '$SourceDistro' into '$NewDistroName'" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Source disk      : $(Format-Size $Cost.DiskBytes)" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Needed on $($Cost.DriveLetter)`:      : $(Format-Size $Cost.NeededBytes) (archive + copy at peak)" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Free on $($Cost.DriveLetter)`:        : $(Format-Size $Cost.FreeBytes)" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Install folder   : $($Cost.InstallPath)" -ForegroundColor (Get-MessageColour muted)

if ($Cost.FreeBytes -lt $Cost.NeededBytes) {
    Write-Host ""
    Write-Host "[ABORT] Not enough room on $($Cost.DriveLetter)`:" -ForegroundColor (Get-MessageColour error)
    Write-Host "        Needed: $(Format-Size $Cost.NeededBytes) - free: $(Format-Size $Cost.FreeBytes)." -ForegroundColor (Get-MessageColour warning)
    Write-Host "        Free some space, then run this again." -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

# 3. Copy: the source is only read. The temporary image is removed by the
# engine's own copy, in all cases - it is worth twice the disk, and leaving it
# would eat the room just checked for.
try {
    Write-Host "==> 1. Reading the source (the source itself is not modified)..." -ForegroundColor (Get-MessageColour info)
    Write-Host "==> 2. Registering '$NewDistroName' from it..." -ForegroundColor (Get-MessageColour info)
    $Report = $Manager.Duplicate($Source, $NewDistroName)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        The source was not modified." -ForegroundColor (Get-MessageColour muted)
    if ($_.Exception.Message -like "*import*") {
        Write-Host "        A half-registered '$NewDistroName' may be left behind:" -ForegroundColor (Get-MessageColour warning)
        Write-Host "        remove it with  .\wsl.ps1 unregister        (pick '$NewDistroName' in the list)" -ForegroundColor (Get-MessageColour hint)
    }
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$NewDistroName' is a copy of '$SourceDistro'" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Install folder   : " -NoNewline; Write-Host "$($Report.InstallPath)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Copy on disk     : " -NoNewline; Write-Host "$(Format-Size $Report.CopyBytes)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * WSL version      : " -NoNewline; Write-Host "$($Source.Version)" -ForegroundColor (Get-MessageColour info)
Write-Host ""
Write-Host "  Windows Terminal: the copy gets a profile of its own, with the icon," -ForegroundColor (Get-MessageColour muted)
Write-Host "  the font and the colours of the source. Restart Terminal to see it." -ForegroundColor (Get-MessageColour muted)
Write-Host ""

# Left the way it was found.
if ($StoppedByUs) {
    try {
        $null = $Manager.Start($Source)
        Write-Host "'$SourceDistro' is running again." -ForegroundColor (Get-MessageColour success)
    } catch {
        Write-Host "Could not restart '$SourceDistro' - start it with: wsl -d $SourceDistro" -ForegroundColor (Get-MessageColour warning)
    }
    Write-Host ""
}
