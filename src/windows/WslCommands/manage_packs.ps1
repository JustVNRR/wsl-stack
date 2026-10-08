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

# Several packs at once: every pack this checkout carries is shown, the ones
# the instance already has arrive checked, and what comes back is applied - the
# missing ones installed, the unchecked ones taken out.
#
# The asking and the applying live in the module - build asks the same
# question. What is left here is the shape of this command.

$ErrorActionPreference = "Stop"

# 1. Which instance
$Distro = Select-Distro
if (-not $Distro) { Stop-Cancelled }
$DistroName = $Distro.Name

Invoke-External { wsl.exe -d $DistroName --exec /bin/true } "Could not start '$DistroName'."

# 2. Every pack this checkout carries, and what that instance already has
$Catalog = $Manager.Catalog
if ($Catalog.AvailablePacks.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No pack found in $PacksRoot." -ForegroundColor (Get-MessageColour error)
    Write-Host "        A pack is a folder there carrying a pack.conf." -ForegroundColor (Get-MessageColour hint)
    exit 1
}

# The engine provides the packs installed on this instance (or $null if home is unreachable)
$Installed = $Manager.InstalledPacks($Distro)
if ($null -eq $Installed) {
    Write-Host ""
    Write-Host "[ABORT] '$DistroName' did not say where its user's home is." -ForegroundColor (Get-MessageColour error)
    exit 1
}

# 3. The checklist, and what it says to do
$Selection = Select-Packs -Title "Packs for '$DistroName'" -Catalog $Catalog -Installed @($Installed) -Family (Get-InstanceFamily -DistroName $DistroName)

if ($null -eq $Selection) { Stop-Cancelled }
if ($Selection.ToAdd.Count -eq 0 -and $Selection.ToRemove.Count -eq 0) {
    Write-Host ""
    Write-Host "[OK] Nothing to do: '$DistroName' already has exactly that." -ForegroundColor (Get-MessageColour success)
    exit 0
}

# 4. Hand the changes over to the engine
# $Manager.ManagePacks runs Invoke-PackApply internally and returns a structured report.
# The 4th argument is the resume hint: "" lets the engine's own line stand.
$Report = $Manager.ManagePacks($Distro, $Selection.ToAdd, $Selection.ToRemove, "")

if ($null -ne $Report.Failure) {
    exit $Report.ExitCode
}

# 5. Where things stand, read back through the engine's report
$Now = @($Report.Now)
Write-Host ""
Write-Host "==> '$DistroName' now carries: $(if ($Now.Count -gt 0) { $Now -join ', ' } else { 'no pack' })" -ForegroundColor (Get-MessageColour success)
if ($Selection.ToAdd.Count -gt 0) {
    Write-Host "    Open a shell in it to use them:  .\wsl.ps1 shell" -ForegroundColor (Get-MessageColour muted)
}
exit 0