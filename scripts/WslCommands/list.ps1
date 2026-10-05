[CmdletBinding()]
param (
    # Injected by wsl.ps1, or instantiated on-demand if executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())
)

# No parameter, and no question either: this command only reads, so it can be
# run at any moment. Its exit code says whether there was anything to show - 1
# when there is none, like the other commands' lists.

$ErrorActionPreference = "Stop"

# The family's shared half: the marker.
$InstanceLib = Join-Path $PSScriptRoot "..\instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# 1. Our instances, running or stopped, by name like every list in this family -
# and, with them, the archives on disk and the folders left behind: the engine's
# List() answers all three at once, what runs included (its batched question,
# asked once).
$Report = $Manager.List()
$All = @($Report.Instances)
if ($All.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No instance of this template is registered on this machine." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Build one with  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
    exit 1
}

Write-Host ""
Write-Host "Instances of this template:" -ForegroundColor (Get-MessageColour info)
for ($Index = 0; $Index -lt $All.Count; $Index++) {
    $Entry = $All[$Index]
    $State = if ($Entry.State -eq [WslState]::Running) { "running" } else { "stopped" }
    Write-Host ("  {0,2}.  {1,-30} {2,-8} {3,10}  {4}" -f ($Index + 1), $Entry.Name, $State,
        (Format-Size (Get-VhdxSize $Entry.Path)), $Entry.Path)
}

# 2. The archives: everything in that folder was written by archive.ps1, so
# there is nothing to tell apart.
$ArchiveFolder = $Manager.ArchivesRoot
$Archives = @($Report.Archives)

if ($Archives.Count -gt 0) {
    Write-Host ""
    Write-Host "Archives in ${ArchiveFolder} (most recent first):" -ForegroundColor (Get-MessageColour info)
    foreach ($Entry in $Archives) {
        $Tar = Get-ChildItem -Path $Entry.FullName -Filter "*.tar*" -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host ("      {0,-30} {1,10}  {2}" -f $Entry.Name, (Format-Size $Tar.Length),
            $Entry.LastWriteTime.ToString("yyyy-MM-dd HH:mm"))
    }
}

# 3. Marked folders that no instance claims - what an interrupted removal, or
# an outside `wsl --unregister`, leaves behind. The one place they show.
$Forgotten = @($Report.Forgotten)

if ($Forgotten.Count -gt 0) {
    Write-Host ""
    Write-Host "Folders left behind by an instance that is gone:" -ForegroundColor (Get-MessageColour hint)
    foreach ($FolderPath in $Forgotten) {
        $Folder = Get-Item -Path $FolderPath -ErrorAction SilentlyContinue
        if (-not $Folder) { continue }
        Write-Host ("      {0,-30} {1,10}  {2}" -f $Folder.Name,
            (Format-Size (Get-VhdxSize $Folder.FullName)), $Folder.FullName) -ForegroundColor (Get-MessageColour hint)
    }
    Write-Host "      No instance claims them, and no command removes them: delete them by hand." -ForegroundColor (Get-MessageColour muted)
}

Write-Host ""
