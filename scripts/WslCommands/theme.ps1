[CmdletBinding()]
param (
    # Injected by wsl.ps1, or made below once the shared half is loaded: the
    # type cannot be named here - a parameter is bound before this file's first
    # line runs, and a fresh pwsh knows nothing of the classes (measured:
    # "Unable to find type [WslInstanceManager]" at bind).
    $Manager
)

# What an instance wears: its icon, its font and its colours - the three things
# Windows Terminal takes from the profile this repository writes.
#
# The instance comes first, once, then the commands - and each comes back here
# when done, so changing the icon and then the font is one visit.

$ErrorActionPreference = "Stop"

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

$Choices = @(
    @{ Name = "icon";  About = "the tile in the tab" },
    @{ Name = "font";  About = "what the whole terminal is written in" },
    @{ Name = "color"; About = "the background, the text, and sixteen colours" }
)

foreach ($Choice in $Choices) {
    $Script = Join-Path $PSScriptRoot "$($Choice.Name).ps1"
    if (-not (Test-Path $Script)) {
        Write-Host ""
        Write-Host "[ABORT] scripts\WslCommands\$($Choice.Name).ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
        exit 1
    }
}

# 1. Which instance, and then which of the three. Escape walks back up the way
# it came: from the theme menu to the list of instances, so another one can be
# picked, and from the list to the prompt.
$Visited = $false

while ($true) {
    # The menu this one was reached from goes first: the instance list gets a
    # screen of its own.
    Clear-MenuScreen

    $Distro = Select-Distro -AllowCancel
    if (-not $Distro) { break }
    $DistroName = $Distro.Name

    Clear-MenuScreen

    # The menu comes back until Escape says the visit to THIS one is over: the
    # level below clears the screen, and this one is drawn on a clean one.
    $Default = 0
    while ($true) {
        Write-Host ""
        $Chosen = Select-FromList -Title "Theme of '$DistroName'" -Items $Choices -Label {
            param($Choice)
            "{0,-6} {1}" -f $Choice.Name, $Choice.About
        } -DefaultIndex $Default

        if (-not $Chosen) { break }

        $Default = [array]::IndexOf($Choices, $Chosen)

        # The command named takes the screen and clears it itself, the way it came in.
        # Hands both -DistroName and the shared -Manager over to the child command.
        & (Join-Path $PSScriptRoot "$($Chosen.Name).ps1") -DistroName $DistroName -Manager $Manager
        $Visited = $true
    }
}

# Coming out: the menu goes with the visit. Ending on the menu you have just
# finished with reads like the command never returned.
Clear-MenuScreen

if (-not $Visited) {
    Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
    exit 0
}

# The visit is over, and this is the moment Terminal can be asked to look again:
# a reload cannot land on a pane that is running a menu, so the change shows
# when you leave, not while you are still in there.
Update-TerminalSettings

# And nothing is said: the change is in the tab, and a line explaining that
# would be one line too many.
exit 0