[CmdletBinding()]
param (
    # Injected by wsl.ps1, or instantiated on-demand if executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())
)

$ErrorActionPreference = "Stop"

# One working folder, no guessing: instances in <Root>\<name>, every archive in
# <Root>\archives - the engine holds both roots.
$ArchiveFolder = $Manager.ArchivesRoot

# The family's shared half: the marker, and the Windows-side look - stored next
# to the tar, re-applied here.
$InstanceLib = Join-Path $PSScriptRoot "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# 1. What there is to restore from. An empty folder is not an error to work
# around: it says how to fill it.
if (-not (Test-Path $ArchiveFolder)) {
    Write-Host ""
    Write-Host "[ABORT] There are no archives: $ArchiveFolder does not exist." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing to restore:" -ForegroundColor (Get-MessageColour hint)
    Write-Host "            - Create one with  .\wsl.ps1 archive" -ForegroundColor (Get-MessageColour hint)
    Write-Host "            - Or move the existing ones back into $ArchiveFolder" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# An archive is a folder - the tar, and the look it was taken with - so this
# lists folders that hold one, read through the engine like everything else
# that shows the fleet: most recent first, usually the one wanted back.
$Archives = @($Manager.List().Archives)

if ($Archives.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] The archives folder is empty: $ArchiveFolder" -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing to restore:" -ForegroundColor (Get-MessageColour hint)
    Write-Host "            - Create one with  .\wsl.ps1 archive" -ForegroundColor (Get-MessageColour hint)
    Write-Host "            - Or move the existing ones back into $ArchiveFolder" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# 2. Pick one: nothing cancels, as everywhere else.
$Chosen = Select-FromList -Title "Archives in $ArchiveFolder (most recent first):" -Items $Archives -Label {
    param($Entry)
    $Tar = Get-ChildItem -Path $Entry.FullName -Filter "*.tar*" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    "{0}  -  {1}, {2}" -f $Entry.Name, (Format-Size $Tar.Length),
        $Entry.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
}

if (-not $Chosen) { Stop-Cancelled -What "created" }

# 3. Name the new instance
Write-Host ""
Write-Host "Restoring $($Chosen.Name) as a new instance." -ForegroundColor (Get-MessageColour info)
$Name = [string](Read-Host "Name of the new instance (Enter to cancel)")
if ([string]::IsNullOrWhiteSpace($Name)) { Stop-Cancelled -What "created" }
$Name = $Name.Trim()

if (-not (Test-InstanceName $Name)) {
    Write-Host ""
    Write-Host "[ABORT] '$Name' is not usable as an instance name" -ForegroundColor (Get-MessageColour error)
    Write-Host "        (letters, digits, '.', '_' and '-' only)." -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Nothing was created." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

# Removing an instance is unregister.ps1's job, with its typed-name
# confirmation: this script does not do it, it names the command.
if ((Get-DistroNames) -contains $Name) {
    Write-Host ""
    Write-Host "[ABORT] An instance named '$Name' already exists." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Remove it first, then run this again:" -ForegroundColor (Get-MessageColour hint)
    Write-Host "          .\wsl.ps1 unregister        (pick '$Name' in the list)" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# The install folder must be free too: a leftover folder of that name would
# end up inside the new instance's disk.
$InstallPath = [System.IO.Path]::GetFullPath((Join-Path $Manager.InstancesRoot $Name))
if (Test-Path $InstallPath) {
    Write-Host ""
    Write-Host "[ABORT] A folder with that name already exists:" -ForegroundColor (Get-MessageColour error)
    Write-Host "        $InstallPath" -ForegroundColor (Get-MessageColour hint)
    Write-Host "        Move or delete it, then run this again." -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# 4. Import. Version 2, like build.ps1: a tar does not carry the version it
# came from, and WSL 1 is not what this repository builds. The import, the
# marker, the look and Docker's entry are the engine's.
$ChosenTar = Get-ChildItem -Path $Chosen.FullName -Filter "*.tar*" -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host ""
Write-Host "==> Creating '$Name' from $($Chosen.Name)" -ForegroundColor (Get-MessageColour info)
Write-Host "  * Archive          : $($ChosenTar.FullName) ($(Format-Size $ChosenTar.Length))" -ForegroundColor (Get-MessageColour muted)
Write-Host "  * Install folder   : $InstallPath" -ForegroundColor (Get-MessageColour muted)
Write-Host ""

try {
    $null = $Manager.RestoreFromArchive($Chosen.FullName, $Name)
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
    Write-Host "        The archive is untouched. A half-registered '$Name' may be left" -ForegroundColor (Get-MessageColour warning)
    Write-Host "        behind:  .\wsl.ps1 unregister        (pick '$Name' in the list)" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host "       '$Name' restored from an archive" -ForegroundColor (Get-MessageColour success)
Write-Host "============================================================" -ForegroundColor (Get-MessageColour success)
Write-Host ""
Write-Host "  * Install folder   : " -NoNewline; Write-Host "$InstallPath" -ForegroundColor (Get-MessageColour info)
Write-Host "  * From             : " -NoNewline; Write-Host "$($Chosen.Name)" -ForegroundColor (Get-MessageColour info)
Write-Host ""
Write-Host "  The archive is kept." -ForegroundColor (Get-MessageColour hint)
Write-Host "  Windows Terminal: restart it to see the icon, the font and the colour" -ForegroundColor (Get-MessageColour muted)
Write-Host "  scheme that came back with the archive." -ForegroundColor (Get-MessageColour muted)
Write-Host ""
