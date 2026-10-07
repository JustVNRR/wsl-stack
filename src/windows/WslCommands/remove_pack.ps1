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

# No parameter on purpose: the instance and the pack both come from lists.
#
# The pack's own remove.sh runs first - the copy INSIDE the instance, not the
# one in this checkout: what has to come out is what the code that installed it
# put in, and that code travelled with the pack. Then the folder goes, and the
# gmake menu loses the commands with it. The runs and the cleanup are the
# engine's; the questions and the lines are here.

$ErrorActionPreference = "Stop"

# The moves that take a pack out live in the module, behind the engine.
# This file is the flow: which instance, which pack, and the one question asked
# before anything leaves.

# 1. Which instance the pack comes out of
$Distro = Select-Distro
$DistroName = $Distro.Name

Invoke-External { wsl.exe -d $DistroName --exec /bin/true } "Could not start '$DistroName'."

# 2. Which pack - the ones a user chooses. A pack marked invisible in its own
# pack.conf is not offered: it leaves with the last pack that requires it. The
# engine answers both what the instance carries ($null when its home cannot be
# named) and what a user may take out; no guard on an empty catalog: a pack
# installed from another checkout is still a pack this command can take out.
$Installed = $Manager.InstalledPacks($Distro)
if ($null -eq $Installed) {
    Write-Host ""
    Write-Host "[ABORT] '$DistroName' did not say where its user's home is." -ForegroundColor (Get-MessageColour error)
    exit 1
}
if (@($Installed).Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] '$DistroName' carries no pack - there is nothing to remove." -ForegroundColor (Get-MessageColour success)
    exit 0
}

$Catalog = Get-PackCatalog
$Offered = @($Manager.RemovablePacks($Distro, $Catalog))
if ($Offered.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] '$DistroName' carries no pack you choose or remove by hand." -ForegroundColor (Get-MessageColour success)
    exit 0
}

$PackName = Select-FromList -Title "Packs installed in '$DistroName':" -Items $Offered

if (-not $PackName) { Stop-Cancelled }

# What leaves with it, planned by the engine: the chosen pack first, then every
# pack nothing installed requires any more - the other order would ask a
# remove.sh whether a neighbour still claims its packages while it can still
# say yes. -Missing names the ones installed before packs had a remove.sh.
$Plan = $Manager.RemovalPlan($Distro, $PackName)
$ToRemove = @($Plan.ToRemove)
$Also = @($ToRemove | Where-Object { $_ -ne $PackName })
$Missing = @($Plan.Missing)

# A pack a still-installed pack requires does not leave: the removal would
# break what stays. Refused before anything moves - nothing has been said or
# touched yet.
$Conflicts = @($Catalog.GetRemovalConflicts(@($Installed), @($ToRemove), @()))
if ($Conflicts.Count -gt 0) {
    Write-Host ""
    foreach ($Conflict in $Conflicts) {
        Write-Host ("[ABORT] '{0}' cannot be removed: required by {1}." -f $Conflict.Name, ($Conflict.Blockers -join " and ")) -ForegroundColor (Get-MessageColour error)
        Write-Host ("        Take {0} out first, or leave '{1}' where it is." -f ($Conflict.Blockers -join " and "), $Conflict.Name) -ForegroundColor (Get-MessageColour hint)
    }
    exit 1
}

# 3. What is about to happen, and only then the question. A pack without a
# remove.sh was installed before packs had one: its folder can leave, but
# nothing is undone on the system side - said, not discovered afterwards.
Write-Host ""
Write-Host "==> Removing from '$DistroName': $($ToRemove -join ', ')" -ForegroundColor (Get-MessageColour info)
foreach ($Name in $Also) {
    Write-Host "    '$Name' goes with '$PackName': nothing installed requires it any more." -ForegroundColor (Get-MessageColour muted)
}
if ($Missing.Count -gt 0) {
    Write-Host "    No remove.sh in: $($Missing -join ', ') - installed before packs had one." -ForegroundColor (Get-MessageColour warning)
    Write-Host "    Nothing of it is undone on the system side: only its files leave." -ForegroundColor (Get-MessageColour hint)
    Write-Host "    To take its tool out by hand, open a shell in '$DistroName'." -ForegroundColor (Get-MessageColour hint)
}
if (-not (Confirm-YesNo "Remove $($ToRemove -join ', ')?")) { Stop-Cancelled }

# 4. The narration for each pack that leaves on its own, then the engine's
# gesture: it runs each remove.sh from inside its own folder (it may ask for a
# password) and takes the folder out once the self-removal is behind us. It
# says nothing, so the lines come first.
foreach ($Name in $ToRemove) {
    if ($Missing -notcontains $Name) {
        Write-Host ""
        Write-Host "==> Removing '$Name'..." -ForegroundColor (Get-MessageColour info)
    }
}

$Report = $Manager.RemovePack($Distro, $PackName)

# The folder stays when the script failed: the pack is still half in place, and
# its files are what a second attempt needs.
if ($Report.Outcome -eq "self-failed") {
    Write-Host ""
    Write-Host "[FAIL] The pack could not remove itself (exit code $($Report.ExitCode))." -ForegroundColor (Get-MessageColour error)
    Write-Host "       Nothing was deleted: '$($Report.Name)' is still installed in '$DistroName'." -ForegroundColor (Get-MessageColour hint)
    exit $Report.ExitCode
}

if ($Report.Outcome -eq "folder-failed") {
    Write-Host ""
    Write-Host "[FAIL] The pack's folder could not be deleted (exit code $($Report.ExitCode))." -ForegroundColor (Get-MessageColour error)
    Write-Host "       '$($Report.Name)' is out of the gmake menu, but its files are still in the instance." -ForegroundColor (Get-MessageColour warning)
    exit $Report.ExitCode
}

# 5. The dependencies their remove.sh never named are taken back here, by the
# engine, silently: only a cleanup that stopped early is worth a line.
if (-not $Report.Cleaned) {
    # The packs are out either way; this is the tidy-up, not the removal.
    Write-Host ""
    Write-Host "[WARN] The cleanup stopped early (exit code $($Report.CleanupCode))." -ForegroundColor (Get-MessageColour warning)
    Write-Host "       They are gone, but some of their dependencies may remain." -ForegroundColor (Get-MessageColour hint)
}

Write-Host ""
Write-Host "$($ToRemove -join ', ') successfully uninstalled." -ForegroundColor (Get-MessageColour success)
exit 0
