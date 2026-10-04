# ==============================================================================
# THE WAY IN: one command at the root, the scripts themselves in scripts\
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
# What this file loads, it loads once: the shared half (scripts\instance.ps1),
# and THE manager - the engine every command calls. The manager is made here
# and handed to the command; a command run on its own makes its own.
#
# The list is asked through scripts\WslUI.ps1: one WslCommand per row of the
# table below - the word, the line, the gesture - and the trio answers both
# ways in, the menu and the command line alike.
# ==============================================================================

$Scripts = Join-Path $PSScriptRoot "scripts"

# What a line says and the colour it takes. A command's own file loads it
# through scripts\instance.ps1, but the lines below are this file's - the ones
# it prints when there is no command to run. The guard prints uncoloured: the
# table it would ask is the file that is missing.
$MessageLib = Join-Path $Scripts "message.ps1"
if (-not (Test-Path $MessageLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\message.ps1 is missing - the scripts\ folder is incomplete."
    exit 1
}
. $MessageLib

# The order is the one the documentation uses, and it starts with the command
# that answers "what do I have?" - list, then the rest along an instance's life.
# Each line says what the command does and stops there: a menu is read at a
# glance. The longest description is 40 characters - 61 columns numbered, 58
# behind the arrow marker, measured - so an 80-column window shows them whole
# and the cut never eats a word that mattered. What deserves a sentence is in
# docs\wsl\commands.md.
$Commands = @(
    @{ Name = "list";       What = "list our instances and the archives" },
    @{ Name = "build";      What = "build an instance from the image" },
    @{ Name = "start";      What = "start a stopped instance" },
    @{ Name = "stop";       What = "stop a running instance" },
    @{ Name = "restart";    What = "restart an instance" },
    @{ Name = "shell";      What = "open a shell inside an instance" },
    @{ Name = "add_pack";   What = "install a pack into an instance" },
    @{ Name = "remove_pack"; What = "uninstall a pack from an instance" },
    @{ Name = "manage_packs"; What = "choose the packs an instance should carry" },
    @{ Name = "theme";      What = "choose the icon, font and colours" },
    @{ Name = "unregister"; What = "remove an instance" },
    @{ Name = "archive";    What = "write an instance to a named archive" },
    @{ Name = "restore";    What = "rebuild an instance from an archive" },
    @{ Name = "duplicate";  What = "copy an instance under another name" },
    @{ Name = "shrink";     What = "reclaim the space an instance has freed" },
    @{ Name = "wslconfig";  What = "open the Windows-wide WSL settings" }
)

# The shared half - the classes, the menus, the packs, the marker - read once,
# here: the manager just under is built on it, the command dispatched at the
# bottom loads it anyway, and the trio the list is asked with comes from it
# too (scripts\WslUI.ps1). Asking is that trio's job now, and it must not be
# written a second time here.
$InstanceLib = Join-Path $Scripts "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# The table above, as objects - built here, where the table lives: one
# WslCommand per row. The gesture is one block for every row: the command and
# a run context arrive as parameters, so nothing is read from a scope at call
# time - measured: a closure that read its variables by name came up empty on
# a machine where the same code ran on another.
$Dispatcher = [WslDispatcher]::new("WSL Stack")
$Gesture = {
    param($Command, $Run)
    $Extra = @($Run.Args)
    & (Join-Path $Run.Scripts "$($Command.Key).ps1") @Extra -Manager $Run.Manager
}
foreach ($Command in $Commands) {
    $null = $Dispatcher.Add([WslCommand]::new($Command.Name, $Command.What, $Gesture))
}

# Bare, the repository asks its first question - which command - and it is a
# question like the ones inside the commands: the same menu, walked with the
# arrows, cancelled with Escape.
if ($args.Count -eq 0) {
    Write-Host ""
    Write-Host "  (a command can also be typed:  .\wsl.ps1 <command> [options])" -ForegroundColor (Get-MessageColour muted)

    $Chosen = $Dispatcher.Ask()
    if (-not $Chosen) {
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was run." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
} else {
    # The command line is routed the same way the menu is: the word names its
    # command, whatever its case. A word nobody knows is said here, with the
    # table it should have come from.
    $Chosen = $Dispatcher.Dispatch("$($args[0])")
    if (-not $Chosen) {
        Write-Host ""
        Write-Host "[ABORT] Invalid command '$($args[0])'. Available commands:" -ForegroundColor (Get-MessageColour error)
        foreach ($Command in $Commands) {
            Write-Host "          $($Command.Name)" -ForegroundColor (Get-MessageColour hint)
        }
        exit 1
    }
}

$Script = Join-Path $Scripts "$($Chosen.Key).ps1"
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
# options keeps them, the others ignore them. With the scripts' folder and the
# manager above, that is the run context the gesture takes its parameters from.
$Rest = @()
if ($args.Count -gt 1) { $Rest = $args[1..($args.Count - 1)] }
$Run = @{
    Scripts = $Scripts
    Args    = $Rest
    Manager = $Manager
}

$Chosen.Execute($Run)

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
