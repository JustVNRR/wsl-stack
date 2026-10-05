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

# No parameter on purpose: the instance and the pack both come from lists -
# typing either by heart is a name you can get wrong.
#
# Then the pack's folder is copied into the instance and its install script runs
# there, in front of you. The packages belong to root, and the engine opens
# WSL's own passwordless root door to sudo for the length of the installs - the
# run never stops to ask, and nothing of it remains after. The copies and the
# runs are the engine's; the questions and the lines are here.

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

# The moves that make a pack travel live in the module, behind the
# engine. This file is the flow: which instance, which pack, and what it says
# on the way.

# 1. Which instance the pack goes into
$Distro = Select-Distro
$DistroName = $Distro.Name

# The copy and the install happen inside it, so it has to be up: WSL starts it
# on the way in, and this call waits for it.
Invoke-External { wsl.exe -d $DistroName --exec /bin/true } "Could not start '$DistroName'."

# 2. Which pack - the ones this repository carries and that instance lacks
$Catalog = Get-PackCatalog
if ($Catalog.AvailablePacks.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No pack found in $PacksRoot." -ForegroundColor (Get-MessageColour error)
    Write-Host "        A pack is a folder there carrying a pack.conf." -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# The engine provides what that instance carries ($null when its home cannot be
# named) and the ones a question may offer: an invisible pack arrives with the
# pack that requires it, never offered.
$Installed = $Manager.InstalledPacks($Distro)
if ($null -eq $Installed) {
    Write-Host ""
    Write-Host "[ABORT] '$DistroName' did not say where its user's home is." -ForegroundColor (Get-MessageColour error)
    exit 1
}

$Candidates = @($Manager.CandidatePacks($Distro, $Catalog))

if ($Candidates.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] '$DistroName' already has every pack this repository offers." -ForegroundColor (Get-MessageColour success)
    exit 0
}

# Said before the list, not after it: with the arrows the rows are drawn in
# place, and anything under them gets painted over.
if (@($Installed).Count -gt 0) {
    Write-Host ""
    Write-Host ("       Already in '$DistroName': {0}" -f (@($Installed) -join ", ")) -ForegroundColor (Get-MessageColour muted)
}

$Pack = Select-FromList -Title "Packs available for '$DistroName':" -Items $Candidates -Label {
    param($Entry)
    "{0,-12} {1}" -f $Entry.Name, $Entry.Description
}

if (-not $Pack) { Stop-Cancelled }

$PackName = $Pack.Name

# 3. What travels: the pack and whatever it requires, requirements first -
# resolved here by the same helper the engine resolves it with, so the lines
# below can name every pack before the copies start.
$ToInstall = @()
foreach ($Name in @($Catalog.ResolveSelection(@($PackName), $Installed))) {
    $Entry = $Catalog.GetPack($Name)
    if ($null -ne $Entry) { $ToInstall += $Entry }
}

# 4. Each pack's folder copied in, then what it does to install itself from
# inside it - the engine's gesture, and it says nothing: the lines come first.
foreach ($Entry in $ToInstall) {
    Write-Host ""
    Write-Host "==> Installing '$($Entry.Name)' in '$DistroName'..." -ForegroundColor (Get-MessageColour info)
    if ($Entry.Name -ne $PackName) {
        Write-Host "    It comes with '$PackName', which requires it." -ForegroundColor (Get-MessageColour muted)
    }
}

$Report = $Manager.AddPack($Distro, $PackName)

# Exit code 2: the pack asked a question and the answer was no (the claude
# pack asks about a second copy installed on Windows). Its folder went back
# out, and the command ends on exit 0: nothing is broken, nothing to run
# again.
if ($Report.Outcome -eq "declined") {
    Write-Host "       The pack's files were removed: it is not installed in '$DistroName'." -ForegroundColor (Get-MessageColour hint)
    exit 0
}

if ($Report.Outcome -eq "copy-failed") {
    Write-Host "[ABORT] Could not copy the pack's files into '$DistroName' (exit code $($Report.ExitCode))." -ForegroundColor (Get-MessageColour error)
    Write-Host "        The message above says what refused: the instance, or Windows." -ForegroundColor (Get-MessageColour hint)
    exit $Report.ExitCode
}

# A half-installed pack is worse than none: the Makefile loads whatever folder
# is there, so the menu would offer commands whose tool was never installed.
# The folder went back out - and only it: what the install already wrote stays,
# and running this again picks up there.
if ($Report.Outcome -eq "failed") {
    Write-Host ""
    Write-Host "[FAIL] The installation did not complete (exit code $($Report.ExitCode))." -ForegroundColor (Get-MessageColour error)
    Write-Host "       The pack's files were removed." -ForegroundColor (Get-MessageColour hint)
    Write-Host "       Whatever the install had already put in place is still there - run this again to finish." -ForegroundColor (Get-MessageColour hint)
    exit $Report.ExitCode
}

exit 0
