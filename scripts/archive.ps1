[CmdletBinding()]
param (
    # Injected by wsl.ps1, or instantiated on-demand if executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root()),

    [ValidateSet("tar", "tar.gz", "tar.xz")]
    [string]$Format = "tar.gz"
)

# No parameter on purpose: the instance comes from the list - a name typed by
# heart is a name you can get wrong.

$ErrorActionPreference = "Stop"

# The folder the engine writes in: instances in <Root>\<name>, archives in
# <Root>\archives - the folder build.ps1 proposes, so everything this
# repository manages sits under one folder.
$ArchiveFolder = $Manager.ArchivesRoot

# The family's shared half: the marker that tells our instances from any other,
# and the Windows-side look - not in the tar, so it travels next to it.
$InstanceLib = Join-Path $PSScriptRoot "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# 1. Which instance. Ours only: the list vouches for them.
$Distro = Select-Distro
$DistroName = $Distro.Name

$DiskBytes = Get-VhdxSize $Distro.Path

# 2. The export stops the instance - WSL terminates it to read a consistent
# disk - and unsaved work is gone: ask rather than surprise.
$StoppedByUs = $false
if ((Get-DistroNames -Running) -contains $DistroName) {
    Write-Host ""
    Write-Host "  '$DistroName' is running, and this needs it stopped." -ForegroundColor (Get-MessageColour warning)
    Write-Host "  Save what you have open in there: stopping it loses anything unsaved." -ForegroundColor (Get-MessageColour warning)
    $StopIt = [string](Read-Host "Stop it now? [Y/n]")
    if ($StopIt -match "^[nN]") {
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
    $null = $Manager.Stop($Distro)
    Write-Host "  Stopped." -ForegroundColor (Get-MessageColour muted)
    $StoppedByUs = $true
}

# 3. The name. An archive is a folder: the tar AND the look - an icon and a
# colour scheme are Windows settings, not a tar's. The instance's name is
# proposed, a taken name gets the next free suffix, and typing an existing name
# is how an archive is replaced.
if (-not (Test-Path -Path $ArchiveFolder)) {
    New-Item -ItemType Directory -Path $ArchiveFolder -Force | Out-Null
}

$Proposal = $DistroName
$Suffix = 0
while (Test-Path (Join-Path $ArchiveFolder $Proposal)) {
    $Suffix++
    $Proposal = "$DistroName-$Suffix"
}

$Existing = @(Get-ChildItem -Path $ArchiveFolder -Directory | Sort-Object Name)
Write-Host ""
if ($Existing.Count -eq 0) {
    Write-Host "No archive yet in $ArchiveFolder." -ForegroundColor (Get-MessageColour muted)
} else {
    Write-Host "Archives already in ${ArchiveFolder}:" -ForegroundColor (Get-MessageColour info)
    foreach ($Entry in $Existing) {
        $Tar = Get-ChildItem -Path $Entry.FullName -Filter "*.tar*" -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $Size = 0
        if ($Tar) { $Size = $Tar.Length }
        Write-Host ("  {0,-30} {1,10}  {2}" -f $Entry.Name, (Format-Size $Size),
            $Entry.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) -ForegroundColor (Get-MessageColour muted)
    }
}
Write-Host ""
$Answer = [string](Read-Host "Name of the archive? [$Proposal]")
$Chosen = if ([string]::IsNullOrWhiteSpace($Answer)) { $Proposal } else { $Answer.Trim() }

if ($Chosen -match '[\\/]') {
    Write-Host ""
    Write-Host "[ABORT] '$Chosen' is a path. Give a name - it lands in:" -ForegroundColor (Get-MessageColour error)
    Write-Host "        $ArchiveFolder" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

$ArchiveDir = [System.IO.Path]::GetFullPath((Join-Path $ArchiveFolder $Chosen))
$Destination = Join-Path $ArchiveDir "$Chosen.$Format"

# The proposal never lands on a taken name, so this is a typed name - and
# typing an existing name is how an archive is replaced. Said, not done quietly.
if (Test-Path -Path $ArchiveDir) {
    Write-Host "  '$Chosen' exists: replacing its archive." -ForegroundColor (Get-MessageColour warning)
}

# 4. Say what it costs before it costs it: the archive holds used data, usually
# much smaller than the disk - "usually" is not a guarantee, and a full drive
# stops the export.
$FreeBytes = (Get-PSDrive -Name (Split-Path -Qualifier $Destination).TrimEnd(':')).Free
Write-Host ""
Write-Host "==> Backing up '$DistroName'" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Instance disk    : $(Format-Size $DiskBytes)" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Free on target   : $(Format-Size $FreeBytes)" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Archive          : $Destination ($Format)" -ForegroundColor (Get-MessageColour muted)

if ($DiskBytes -gt 0 -and $FreeBytes -lt $DiskBytes) {
    Write-Host "  * Note             : less free space than the disk's size." -ForegroundColor (Get-MessageColour warning)
    Write-Host "                       The archive holds used data and is normally much smaller;" -ForegroundColor (Get-MessageColour muted)
    Write-Host "                       if it does not fit, the export stops and its partial file is deleted." -ForegroundColor (Get-MessageColour muted)
}

# 5. Export - the engine writes the tar and puts the look beside it; a partial
# tar is removed inside the instance's own Archive before the failure travels.
$Started = Get-Date
try {
    $Report = $Manager.Archive($Distro, $Chosen, $Format)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        The partial archive was removed. Nothing else was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

$Archive = $Report.Archive
$Elapsed = (Get-Date) - $Started

Write-Host ""
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       Backup of '$DistroName' written" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
# The look goes next to the tar, once the export succeeded: a half-written
# archive folder is worse than one missing the look.
$Look = $Report.Look
Write-Host "  * Look             : font '$($Look.Font)', colours '$($Look.ColorScheme)'$(if ($Look.IconCopied) { ", icon copied" })" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Docker Desktop   : $(if ($Look.Docker -eq "yes") { "knows this instance" } elseif ($Look.Docker -eq "no") { "does not know it" } else { "not installed, or unreadable" })" -ForegroundColor (Get-MessageColour muted)
if (-not (Test-FontInstalled $Look.Font)) {
    Write-Host "                       '$($Look.Font)' is not installed on Windows" -ForegroundColor (Get-MessageColour warning)
}

Write-Host "  * Archive          : " -NoNewline; Write-Host "$ArchiveDir" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Tar              : " -NoNewline; Write-Host "$($Archive.Name) ($(Format-Size $Archive.Length))" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Instance disk    : " -NoNewline; Write-Host "$(Format-Size $DiskBytes)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Time             : " -NoNewline; Write-Host "$([int]$Elapsed.TotalMinutes) min $($Elapsed.Seconds) s" -ForegroundColor (Get-MessageColour info)
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor (Get-MessageColour muted)
Write-Host "To restore it as a new instance:" -ForegroundColor (Get-MessageColour hint)
Write-Host "  .\wsl.ps1 restore        (it lists the archives, this one included)" -ForegroundColor (Get-MessageColour hint)
Write-Host "------------------------------------------------------------" -ForegroundColor (Get-MessageColour muted)
Write-Host ""

# 6. What becomes of the instance now that its archive is on disk. The copy
# exists either way; only the user knows what they want. The default is the
# state it was found in, marked in the list: Enter takes it, and so does a
# read nobody could make (Escape, no console) - what the old prompt did with
# anything that was not a, b or c.
$Choices = @("Start", "Delete", "Leave")
$Default = if ($StoppedByUs) { "Start" } else { "Leave" }
$AfterExport = Select-FromList -Title "What should happen to '$DistroName' now?" `
    -Items $Choices -DefaultIndex $Choices.IndexOf($Default) -Label {
        param($Wanted)
        $Text = switch ($Wanted) {
            "Start" { "Start it" }
            "Delete" { "Delete it (the archive stays)" }
            "Leave" { "Leave it stopped" }
        }
        if ($Wanted -eq $Default) { "$Text  (default)" } else { $Text }
    }
if (-not $AfterExport) { $AfterExport = $Default }
Write-Host ""

if ($AfterExport -eq "Start") {
    # `--exec` runs a command and returns: the instance comes back up without
    # this script opening a shell in it.
    try {
        $null = $Manager.Start($Distro)
        Write-Host "'$DistroName' is running." -ForegroundColor (Get-MessageColour success)
    } catch {
        Write-Host "Could not start '$DistroName' - start it with: wsl -d $DistroName" -ForegroundColor (Get-MessageColour warning)
    }
    Write-Host ""
} elseif ($AfterExport -eq "Delete") {
    # The archive exists, so this is a decision, not an accident - but it still
    # goes through unregister.ps1: the typed name is what this repository asks
    # for before destroying anything.
    $UnregisterScript = Join-Path $PSScriptRoot "unregister.ps1"
    if (Test-Path $UnregisterScript) {
        # unregister.ps1 takes no name: it lists and the user picks again.
        Write-Host "Pick '$DistroName' in the list below, and type its name to confirm." -ForegroundColor (Get-MessageColour muted)
        & $UnregisterScript -Manager $Manager
        if ($LASTEXITCODE -eq 0) {
            Write-Host "The archive is the only copy of '$DistroName' left." -ForegroundColor (Get-MessageColour muted)
        }
    } else {
        Write-Host "unregister.ps1 is not next to this script. To delete it, run:" -ForegroundColor (Get-MessageColour warning)
        Write-Host "  wsl --unregister $DistroName" -ForegroundColor (Get-MessageColour hint)
    }
    Write-Host ""
} else {
    Write-Host "'$DistroName' is left stopped." -ForegroundColor (Get-MessageColour muted)
    Write-Host ""
}
