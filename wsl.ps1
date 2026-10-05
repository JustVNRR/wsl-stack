[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Command,

    # Nothing followed means an empty list, never $null: @($null) is a list of
    # one, and every command run bare would receive that stray argument.
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArgs = @()
)

# ==============================================================================
# THE WAY IN: one command at the root, the commands themselves in scripts\WslCommands\
# ==============================================================================
# Bare, it asks which command: the list, walked with the arrows and taken with
# Enter, Escape to cancel. With a command, it runs it.
#
#   .\wsl.ps1                       the menu
#   .\wsl.ps1 archive               archive an instance
#   .\wsl.ps1 archive -Format tar.xz
#
# None of the commands behind it takes an instance name on the command line:
# they list what exists - this template's instances only, the ones carrying the
# marker - or, for start and stop, what can still be acted on, and you pick.
# scripts\instance.ps1 is not a command: it holds what the other scripts share,
# and is not listed here.
#
# The shared half arrives through scripts\instance.ps1 - the one loader, once
# per run - and THE manager is made here: the engine every command calls,
# handed to the command; a command run on its own makes its own.
#
# The list is asked through scripts\WslUI.ps1: one WslMenuItem per row of the
# chain below - the word, the line, the gesture - and the trio answers both
# ways in, the menu and the command line alike.
# ==============================================================================

$Scripts = Join-Path $PSScriptRoot "scripts"

# The commands themselves: one file per word, in their own folder - what the
# menu rows and the command line both end at.
$CommandFiles = Join-Path $Scripts "WslCommands"

# The way in: scripts\instance.ps1, the one loader - the module (the words,
# and the colour the lines below take), the classes, the menus; each guarded
# there. It is loaded once per run: the command dispatched at the bottom
# loads it again and finds the run's marker set. The guard here prints
# uncoloured - nothing is loaded yet, not even the words.
$InstanceLib = Join-Path $Scripts "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete."
    exit 1
}
. $InstanceLib

# The gesture, one block for every command: the row and the run context arrive
# as parameters - nothing is read from a scope at call time (measured: a
# closure that read its variables by name worked on one machine and came up
# empty on another). The entry below runs it at its own scope, and NOT through
# a class method: a method collects what it runs and takes the console away
# from every native underneath - the child loses its terminal and its stdout
# is thrown away, which is what blinded a build's whiptail (measured).
$Gesture = {
    param($Command, $Run)
    $Extra = @($Run.Args)
    & (Join-Path $Run.Scripts "$($Command.Key).ps1") @Extra -Manager $Run.Manager
}

# The words, one chain: one WslMenuItem per command - the word, the line, the
# gesture. The order is the one the documentation uses, and it starts with the
# command that answers "what do I have?" - list, then the rest along an
# instance's life. Each line says what the command does and stops there: a
# menu is read at a glance. The longest description is 40 characters - 61
# columns numbered, 58 behind the arrow marker, measured - so an 80-column
# window shows them whole and the cut never eats a word that mattered. What
# deserves a sentence is in docs\wsl\commands.md.
$Menu = [WslMenu]::new("WSL Stack").
    Add("list",         "list our instances and the archives",      $Gesture).
    Add("build",        "build an instance from the image",         $Gesture).
    Add("start",        "start a stopped instance",                 $Gesture).
    Add("stop",         "stop a running instance",                  $Gesture).
    Add("restart",      "restart an instance",                      $Gesture).
    Add("shell",        "open a shell inside an instance",          $Gesture).
    Add("add_pack",     "install a pack into an instance",          $Gesture).
    Add("remove_pack",  "uninstall a pack from an instance",        $Gesture).
    Add("manage_packs", "choose the packs an instance should carry", $Gesture).
    Add("theme",        "choose the icon, font and colours",        $Gesture).
    Add("unregister",   "remove an instance",                       $Gesture).
    Add("archive",      "write an instance to a named archive",     $Gesture).
    Add("restore",      "rebuild an instance from an archive",      $Gesture).
    Add("duplicate",    "copy an instance under another name",      $Gesture).
    Add("shrink",       "reclaim the space an instance has freed",  $Gesture).
    Add("wslconfig",    "open the Windows-wide WSL settings",       $Gesture)

# With a word, the command line routes it; bare, the repository asks its first
# question - which command - and it is a question like the ones inside the
# commands: the same menu, walked with the arrows, cancelled with Escape.
if ($Command) {
    # The word names its command, whatever its case. A word nobody knows is
    # said here, with the list it should have come from.
    $Chosen = $Menu.Dispatch($Command)
    if (-not $Chosen) {
        Write-Host ""
        Write-Host "[ABORT] Invalid command '$Command'. Available commands:" -ForegroundColor (Get-MessageColour error)
        foreach ($Item in $Menu.Items) {
            Write-Host "          $($Item.Key)" -ForegroundColor (Get-MessageColour hint)
        }
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "  (a command can also be typed:  .\wsl.ps1 <command> [options])" -ForegroundColor (Get-MessageColour muted)

    $Chosen = $Menu.Prompt()
    if (-not $Chosen) { Stop-Cancelled -What "run" }
}

$Script = Join-Path $CommandFiles "$($Chosen.Key).ps1"
if (-not (Test-Path $Script)) {
    Write-Host ""
    Write-Host "[ABORT] $Script is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}

# The engine, made once: every command receives this same manager - the command
# asks, the manager acts through the model, and nothing else reaches the disk
# or wsl.exe.
$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())

# Whatever followed the command is handed over as it came: a command that has
# options keeps them, the others ignore them. With the commands' folder and the
# manager above, that is the run context the gesture takes its parameters from.
$Run = @{
    Scripts = $CommandFiles
    Args    = $RemainingArgs
    Manager = $Manager
}

& $Chosen.Action $Chosen $Run

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
