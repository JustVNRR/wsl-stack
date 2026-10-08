# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager,

    # The folder the fleet goes to. Given, or asked.
    [string]$Target = "",

    # Must remain the VERY LAST parameter to allow valid PowerShell parsing
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Ignored
)

# The fleet moved to another folder, the registry never touched: every
# instance is ARCHIVED (the tar and its look - our own archive), then
# unregistered right away - the space frees as it goes, the disk never
# doubles - and when nothing is left but the archives folder, that folder
# travels (a rename on one volume, robocopy across, the originals kept). The
# working folder follows - but only once everything made it. The instances
# come back on the target side with .\wsl.ps1 restore.

$ErrorActionPreference = "Stop"

if ($Ignored) {
    Write-Host ""
    Write-Host "[ABORT] Unknown options after the command." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Run it on its own:  .\wsl.ps1 migrate" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

$SourceBase = $Manager.InstancesRoot

# 1. The folder to go to.
$Target = if ($Target) { $Target } else { Read-Answer -Question "Move the fleet from '$SourceBase' to" -What "moved" }
$Target = $Target.Trim().Trim('"').TrimEnd('\')
if ($Target -eq $SourceBase.TrimEnd('\')) {
    Write-Host ""
    Write-Host "  That is the working folder - nothing to move." -ForegroundColor (Get-MessageColour warning)
    exit 0
}

# The folder is made ready here - before anything is archived, so a target
# that cannot exist stops the run with nothing done. An existing folder is
# fine: nothing of it is erased, and its own `archives` is refused later.
try {
    $null = New-Item -ItemType Directory -Path $Target -Force -ErrorAction Stop
} catch {
    Write-Host ""
    Write-Host "[ABORT] '$Target' cannot be used: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    exit 1
}

# 2. The whole fleet: ours, under the working folder. Nothing to choose - it
# is the folder that moves. A fleet of zero is fine: the archives travel all
# the same, and with nothing at all the switch still happens - a target can
# be chosen before anything is built.
$Fleet = @([WslInstanceManager]::Ours() |
    Where-Object { (Split-Path -Path $_.Path -Parent).TrimEnd('\') -eq $SourceBase.TrimEnd('\') } |
    Sort-Object Name)
if ($Fleet.Count -eq 0) {
    Write-Host ""
    Write-Host "  No instance of ours in '$SourceBase' - nothing to archive; the archives travel all the same." -ForegroundColor (Get-MessageColour muted)
}

Write-Host ""
Write-Host "==> Archiving the fleet" -ForegroundColor (Get-MessageColour info)
Write-Host "  Instances that run are stopped one by one as they are archived - anything" -ForegroundColor (Get-MessageColour muted)
Write-Host "  unsaved in them is lost. Docker Desktop and the others keep running." -ForegroundColor (Get-MessageColour muted)

# 3. One by one: archived, then unregistered - the space frees as it goes. A
# failure stops the run there; what is already archived is unregistered, so
# running the command again picks up with the rest.
$Done = 0
foreach ($Instance in $Fleet) {
    Write-Host ""
    Write-Host "  * $($Instance.Name)" -ForegroundColor (Get-MessageColour info)
    try {
        $null = $Manager.Unregister($Instance, $true)
    } catch {
        Write-Host "    [FAIL] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
        break
    }
    Write-Host "    archived, then removed (the copy is in '$($Manager.ArchivesRoot)')." -ForegroundColor (Get-MessageColour muted)
    $Done++
}

if ($Done -ne $Fleet.Count) {
    Write-Host ""
    Write-Host "  * Working folder: $SourceBase (unchanged)" -ForegroundColor (Get-MessageColour warning)
    Write-Host "    $($Fleet.Count - $Done) instance(s) not archived - nothing moves until the whole fleet is." -ForegroundColor (Get-MessageColour muted)
    Write-Host "    The ones already archived are gone - run it again to carry on with the rest." -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# 4. Nothing left but the archives: they travel. Same volume: a rename.
# Across volumes: robocopy - the copies land on the target, the originals
# stay. A failure here is said, and the working folder does NOT follow: the
# source is still whole.
$SourceRoot = [System.IO.Path]::GetPathRoot($SourceBase)
$TargetFull = [System.IO.Path]::GetFullPath($Target)
$TargetRoot = [System.IO.Path]::GetPathRoot($TargetFull)
$IsSameVolume = ($SourceRoot.TrimEnd('\').ToUpperInvariant() -eq $TargetRoot.TrimEnd('\').ToUpperInvariant())

$OldArchives = Join-Path $SourceBase "archives"
$NewArchives = Join-Path $TargetFull "archives"
Write-Host ""
if (Test-Path $OldArchives) {
    Write-Host "  * Archives: $OldArchives -> $NewArchives" -ForegroundColor (Get-MessageColour info)
    if (Test-Path $NewArchives) {
        Write-Host "    [FAIL] '$NewArchives' already exists - nothing was moved. Move it away first." -ForegroundColor (Get-MessageColour error)
        exit 1
    } elseif ($IsSameVolume) {
        try {
            Move-Item -Path $OldArchives -Destination $NewArchives -ErrorAction Stop
        } catch {
            Write-Host "    [FAIL] the move failed: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
            exit 1
        }
    } else {
        $ArchivesSize = (Get-ChildItem -Path $OldArchives -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $Free = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($TargetRoot.TrimEnd('\'))'").FreeSpace
        if ($Free -lt ($ArchivesSize + 2GB)) {
            Write-Host "    [FAIL] not enough free space on '$($TargetRoot.TrimEnd('\'))' - $([Math]::Ceiling(($ArchivesSize + 2GB) / 1GB)) GB needed." -ForegroundColor (Get-MessageColour error)
            exit 1
        }
        # /E subdirectories, /COPY:DAT data, attributes and times, /Z
        # restartable (a long copy survives a hiccup), /R:3 /W:2 a short
        # retry. Codes under 8 are success.
        & robocopy.exe $OldArchives $NewArchives /E /COPY:DAT /Z /R:3 /W:2 | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Host "    [FAIL] robocopy reported errors (code $LASTEXITCODE) - the originals are untouched." -ForegroundColor (Get-MessageColour error)
            exit 1
        }
    }
    Write-Host "    done." -ForegroundColor (Get-MessageColour muted)
}

# 5. The working folder follows.
[WslInstanceManager]::SetRoot($TargetFull)
Write-Host ""
Write-Host "  * Working folder: $TargetFull" -ForegroundColor (Get-MessageColour success)
if (Test-Path $NewArchives) {
    Write-Host "    The instances are in '$NewArchives' - bring them back with  .\wsl.ps1 restore" -ForegroundColor (Get-MessageColour hint)
}
if (-not $IsSameVolume -and (Test-Path $OldArchives)) {
    Write-Host "    The originals under '$OldArchives' were kept - delete them after making sure everything is OK." -ForegroundColor (Get-MessageColour hint)
}
