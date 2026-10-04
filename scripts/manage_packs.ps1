[CmdletBinding()]
param ()

# Several packs at once: every pack this checkout carries is shown, the ones
# the instance already has arrive checked, and what comes back is applied - the
# missing ones installed, the unchecked ones taken out.
#
# The asking and the applying live in scripts\packs.ps1 - build asks the same
# question. What is left here is the shape of this command.

$ErrorActionPreference = "Stop"

# The family's shared half: the instances, the menus, the packs, and the moves
# a pack makes.
$InstanceLib = Join-Path $PSScriptRoot "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# The packs question lives in its own file - the same checklist build asks.
$PromptsLib = Join-Path $PSScriptRoot "prompts.ps1"
if (-not (Test-Path $PromptsLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\prompts.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $PromptsLib

# 1. Which instance
$Distro = Select-Distro
$DistroName = $Distro.Name

Invoke-External { wsl.exe -d $DistroName --exec /bin/true } "Could not start '$DistroName'."

$InstanceHome = Get-InstanceHome -DistroName $DistroName
if (-not $InstanceHome) {
    Write-Host ""
    Write-Host "[ABORT] '$DistroName' did not say where its user's home is." -ForegroundColor (Get-MessageColour error)
    exit 1
}
$PacksDirectory = "$InstanceHome/.config/packs"

# 2. Every pack this checkout carries, and what that instance already has
$Catalog = Get-PackCatalog
if ($Catalog.AvailablePacks.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No pack found in $PacksRoot." -ForegroundColor (Get-MessageColour error)
    Write-Host "        A pack is a folder there carrying a pack.conf." -ForegroundColor (Get-MessageColour hint)
    exit 1
}
$Installed = @(Get-InstalledPacks -DistroName $DistroName -PacksDirectory $PacksDirectory)

# 3. The checklist, and what it says to do
$Selection = Select-Packs -Title "Packs for '$DistroName'" -Catalog $Catalog -Installed $Installed

if ($null -eq $Selection) {
    Write-Host ""
    Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
    exit 0
}
if ($Selection.ToAdd.Count -eq 0 -and $Selection.ToRemove.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] Nothing to do: '$DistroName' already has exactly that." -ForegroundColor (Get-MessageColour success)
    exit 0
}

# 4. What was asked for, in the one order that works
$Failure = Invoke-PackApply -DistroName $DistroName -PacksDirectory $PacksDirectory `
    -ToAdd $Selection.ToAdd -ToRemove $Selection.ToRemove
if ($null -ne $Failure) { exit $Failure.ExitCode }

# 5. Where things stand, read back from the instance: the folder is the state -
# what is there, not what this run meant to do.
$Now = @(Get-InstalledPacks -DistroName $DistroName -PacksDirectory $PacksDirectory)
Write-Host ""
Write-Host "==> '$DistroName' now carries: $(if ($Now.Count -gt 0) { $Now -join ', ' } else { 'no pack' })" -ForegroundColor (Get-MessageColour success)
if ($Selection.ToAdd.Count -gt 0) {
    Write-Host "    Open a shell in it to use them:  .\wsl.ps1 shell" -ForegroundColor (Get-MessageColour muted)
}
exit 0
