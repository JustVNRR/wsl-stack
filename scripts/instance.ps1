# ==============================================================================
# WHAT EVERY COMMAND LOADS
# ==============================================================================
# The shared half, once per run: the module (the messages, and the instances'
# own family - the marker, the look, Docker Desktop, the engine on wsl.exe),
# then the classes for the scripts themselves, then the menus library
# (WslUI.ps1) - the last one that is not a module family yet.
#
# Same rule when a piece is missing: say so, rather than die with a PowerShell
# error that reads like the machine's fault.
# ==============================================================================

# ---------------------------------------------------------------------------
# THE MODULE
# ---------------------------------------------------------------------------
# The messages first - every line below is one - and the instances' own family
# beside them: the marker, the look, Docker Desktop, the engine on wsl.exe.
# Loaded once, before everything. The guard prints uncoloured: the table it
# would ask is the module that is missing.
$StackModule = Join-Path $PSScriptRoot "WslStack\WslStack.psd1"
if (-not (Test-Path $StackModule)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\WslStack\WslStack.psd1 is missing - the scripts\ folder is incomplete."
    exit 1
}
Import-Module $StackModule -Force

# ---------------------------------------------------------------------------
# THE MODEL
# ---------------------------------------------------------------------------
# The classes, in the order they must be read: a class settles the types it
# names the moment its file is parsed, so each file comes after the ones it
# names. Read again on every run - a terminal can outlive a pull, and what must
# run is the code on disk; pwsh 7 replaces a class it already held cleanly.
$ClassLibs = @("WslState.ps1", "WslTheme.ps1", "WslPack.ps1", "WslInstance.ps1", "WslPackCatalog.ps1", "WslInstanceManager.ps1")
$ClassesDir = Join-Path $PSScriptRoot "WslModel"
foreach ($ClassLib in $ClassLibs) {
    $ClassPath = Join-Path $ClassesDir $ClassLib
    if (-not (Test-Path $ClassPath)) {
        Write-Host ""
        Write-Host "[ABORT] scripts\WslModel\$ClassLib is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
        exit 1
    }
    . $ClassPath
}

# ---------------------------------------------------------------------------
# THE MENUS
# ---------------------------------------------------------------------------
# The menu's classes - the rows, the console, the ask; the doors and the
# helpers that go with them ride the module. Same rule when a piece is missing:
# say so, rather than die with a PowerShell error that reads like the machine's
# fault.
$MenuLib = Join-Path $PSScriptRoot "WslUI.ps1"
if (-not (Test-Path $MenuLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\WslUI.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $MenuLib
