# ==============================================================================
# WHAT EVERY COMMAND LOADS
# ==============================================================================
# The module, once per run: the messages and the instances' own family (the
# marker, the look, Docker Desktop, the engine on wsl.exe), the pack moves,
# the questions, the menus. The classes do not pass through here: every file
# that names one pulls it by `using module` at its own top, and the model and
# the menus are then read once per window, not once per run - the chosen price
# of types that resolve in every file, whichever called in what shape. The
# module's functions stay fresh every run.
#
# Once per run: a run reaches this file twice - the entry loads it, then the
# command the entry runs loads it again - and the marker the first call leaves
# in the caller's scope says the work is done: the command (and the command's
# children) read it down the scope chain. The marker dies with the run, so the
# next run reads the disk again - a terminal can outlive a pull.
#
# Same rule when a piece is missing: say so, rather than die with a PowerShell
# error that reads like the machine's fault.
# ==============================================================================

# Second call in the same run: everything below is already loaded.
if ($WslStackLoaded) { return }

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

# The run's marker, for the second call - the command - and its children.
$WslStackLoaded = $true
