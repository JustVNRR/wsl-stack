# The classes this file names, pulled in by the file itself: the menu is
# built from [WslMenu] rows below, and the manager below that.
using module .\src\windows\WslModel\WslModel.psd1
using module .\src\windows\WslUI.psm1

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
# THE WAY IN: one command at the root, the commands themselves in src\windows\WslCommands\
# ==============================================================================
# Bare, it asks which command: the list, walked with the arrows and taken with
# Enter, Escape to cancel. With a command, it runs it.
#
#   .\wsl.ps1                       the menu
#   .\wsl.ps1 archive               archive an instance
#   .\wsl.ps1 archive -Format tar.xz
#
# Almost none of the commands behind it takes a name on the command line: they
# list what exists - this template's instances only, the ones carrying the
# marker - or, for start and stop, what can still be acted on, and you pick.
# delete_archive is the exception: called by name, kept out of the menu.
#
#
# The module is imported here, once, for the whole run: its functions are
# visible to every command launched below (they run in this session), and THE
# manager is made here too - the engine every command calls, handed over.
#
# The list is asked through src\windows\WslUI.psm1: one WslMenuItem per row of the
# chain below - the word, the line, the gesture - and the trio answers both
# ways in, the menu and the command line alike.
# ==============================================================================

$Scripts = Join-Path $PSScriptRoot "src\windows"

# The commands themselves: one file per word, in their own folder - what the
# menu rows and the command line both end at.
$CommandFiles = Join-Path $Scripts "WslCommands"

# THE module, imported here: its words and colours - every line below takes
# one - its functions, and the families behind them. The guard prints
# uncoloured: the table it would ask is the module that is missing.
$StackModule = Join-Path $Scripts "WslStack\WslStack.psd1"
if (-not (Test-Path $StackModule)) {
    Write-Host ""
    Write-Host "[ABORT] src\windows\WslStack\WslStack.psd1 is missing - the src\windows\ folder is incomplete."
    exit 1
}
Import-Module $StackModule -Force

# The gesture, one block for every command: the row and the run context arrive
# as parameters - nothing is read from a scope at call time (measured: a
# closure that read its variables by name worked on one machine and came up
# empty on another). The entry below runs it at its own scope, and NOT through
# a class method: a method collects what it runs and takes the console away
# from every native underneath - the child loses its terminal and its stdout
# is thrown away, which is what blinded a build's whiptail (measured).
$Gesture = {
    param($Command, $Run)
    # The commands whose answers came from the console's conversation: they
    # arrived whole, and the words that built them are spent - the command
    # takes its answers and nothing else.
    if ($Run.ContainsKey("Answers")) {
        & (Join-Path $Run.Scripts "$($Command.Key).ps1") -Form $Run.Answers -Manager $Run.Manager
        return
    }
    # The tokens after the command, in words: `-Name` starts a parameter and
    # the tokens up to the next one are its values - the command's own
    # parameters then bind by name, the way they read on the command line.
    # Handed over positionally instead, the token '-Format' was taken for the
    # VALUE of the next parameter (measured: archive -Format tar.xz died on
    # the value '-Format'). A parameter with no value is a switch ($true), and
    # a name the command does not know still lands in its $Ignored, which
    # refuses it. Anything before the first `-Name` rides positionally, as it
    # came.
    $Named = @{}
    $Loose = @()
    $Key = $null
    foreach ($Token in @($Run.Args)) {
        $Word = "$Token"
        if ($Word.StartsWith("-") -and $Word.Length -gt 1) {
            $Key = $Word.Substring(1)
            $Named[$Key] = @()
            continue
        }
        if ($Key) { $Named[$Key] += ,$Token } else { $Loose += $Token }
    }
    foreach ($Name in @($Named.Keys)) {
        $Values = @($Named[$Name])
        $Named[$Name] = if ($Values.Count -eq 0) { $true } elseif ($Values.Count -eq 1) { $Values[0] } else { $Values }
    }
    & (Join-Path $Run.Scripts "$($Command.Key).ps1") @Named @Loose -Manager $Run.Manager
}

# The words, one chain: one WslMenuItem per command - the word, the line, the
# gesture. The order is the one the documentation uses, and it starts with the
# window - gui, the mouse-first way in - then list, the answer to "what do I
# have?", then the rest along an instance's life. Each line says what the
# command does and stops there: a menu is read at a glance. The longest is 40
# characters - 61
# columns numbered, 58 behind the arrow marker, measured - so an 80-column
# window shows them whole and the cut never eats a word that mattered. What
# deserves a sentence is in docs\wsl\commands.md.
$Menu = [WslMenu]::new("WSL Stack").
    Add("gui",          "open graphical fleet manager",             $Gesture).
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
    Add("wslconfig",    "open the Windows-wide WSL settings",       $Gesture).
    Add("migrate",      "move the fleet to another folder",         $Gesture)

# With a word, the command line routes it; bare, the repository asks its first
# question - which command - and it is a question like the ones inside the
# commands: the same menu, walked with the arrows, cancelled with Escape.
if ($Command) {
    # The word names its command, whatever its case. A word the menu does not
    # carry may still be a command file - delete_archive is one, called by
    # name and kept out of the menu - and a word neither knows is said here,
    # with the list it should have come from.
    $Chosen = $Menu.Dispatch($Command)
    if (-not $Chosen -and (Test-Path (Join-Path $CommandFiles "$Command.ps1"))) {
        $Chosen = [PSCustomObject]@{ Key = $Command; Action = $Gesture }
    }
    if (-not $Chosen) {
        Write-Host ""
        Write-Host "[ABORT] Invalid command '$Command'. Available commands:" -ForegroundColor (Get-MessageColour error)
        foreach ($Item in $Menu.Items) {
            Write-Host "          $($Item.Key)" -ForegroundColor (Get-MessageColour hint)
        }
        exit 1
    }
} else {

    $Chosen = $Menu.Prompt()
    if (-not $Chosen) { Stop-Cancelled -What "run" }
}

$Script = Join-Path $CommandFiles "$($Chosen.Key).ps1"
if (-not (Test-Path $Script)) {
    Write-Host ""
    Write-Host "[ABORT] $Script is missing - the src\windows\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}

# The engine, made once: every command receives this same manager - the command
# asks, the manager acts through the model, and nothing else reaches the disk
# or wsl.exe.
$Manager = New-InstanceManager

# The console's conversations, one arm per command that asks - the window's
# popups have their caller in gui.ps1, and these are theirs. The answers
# ride the run context; the words they were built from are spent.
$Answers = $null
if ($Chosen.Key -eq "build") {
    . (Join-Path $CommandFiles "..\cli\Controllers\Build.ps1")
    Write-Host ""
    Write-Host "==> Creating a new instance" -ForegroundColor (Get-MessageColour info)
    $Answers = Read-BuildAnswers -Manager $Manager -RepoRoot $PSScriptRoot -Options $RemainingArgs
    if ($null -eq $Answers) { exit 1 }
}

# Whatever followed the command travels in this run context: the gesture
# rebuilds it into named parameters and loose values (see above), so a command
# that has options binds them by name, and one handed a name it does not know
# refuses it. With the commands' folder and the manager above, that is
# everything the gesture takes its parameters from.
$Run = @{
    Scripts = $CommandFiles
    Args    = $RemainingArgs
    Manager = $Manager
}
if ($null -ne $Answers) { $Run.Answers = $Answers }

& $Chosen.Action $Chosen $Run

# A console build that went through opens the shell its summary promised -
# the window's runner does the same on its side.
if ($Chosen.Key -eq "build" -and $LASTEXITCODE -eq 0) {
    try {
        $Manager.Refresh()
        $New = @($Manager.Instances | Where-Object { $_.Name -eq $Answers.Name })[0]
        if ($New) { $New.OpenShell() }
    } catch {
        Write-Host "The shell window could not be opened: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour warning)
    }
}

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
