# The classes this file names, pulled in by the file itself: a type resolves
# for its own reader, whoever launched the command.
using module ..\WslModel\WslModel.psd1
[CmdletBinding()]
param (
    # The instance, when the theme menu has already asked which one: how the
    # level above hands over. Not an option, and not documented as one.
    [string]$DistroName,

    # Injected by wsl.ps1 - the engine every command acts through, made once
    # in the entry. A command is never run by hand any more: the entry loads
    # the module and hands this over, and the `using` above names the type, so
    # it binds from the first line.
    [WslInstanceManager]$Manager
)

# What an instance is written in: the font of its Terminal profile - the whole
# terminal, prompt and icons included. Reached through `.\wsl.ps1 theme`.
#
# The list is the fonts Windows has that carry the glyphs a prompt is drawn
# with, asked of GDI+ rather than read off the registry - those are the family
# names a Terminal profile takes - and measured on the font file rather than
# guessed from the name: a font without them draws a box where the prompt has a
# folder, and offering it would be offering the problem.
#
# One font is in the list whether it carries icons or not: the one in use.
#
# No console can show a font in itself - a terminal writes every row in the
# font IT is set to - so the preview is the choice itself: the profile changes,
# and the next tab is written in it.
#
# It keeps asking, like the icon command: Escape leaves.

$ErrorActionPreference = "Stop"

# 1. Which instance. Given, or asked.
$HandedOver = [bool]$DistroName
if ($HandedOver) {
    $Distro = $Manager.FindByName($DistroName)
    if (-not $Distro) {
        Write-Host ""
        Write-Host "[ABORT] No instance named '$DistroName' is registered here." -ForegroundColor (Get-MessageColour error)
        exit 1
    }
} else {
    $Distro = Select-Distro
    $DistroName = $Distro.Name
}

# The menus it came through - the way in, the theme menu, the instance it picked
# - come off the screen: this command asks its own question.
Clear-MenuScreen

$OurFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$DistroName.json"
if (-not (Test-Path $OurFragment)) {
    Write-Host ""
    Write-Host "[WARNING] This instance has no Terminal profile of ours - the font would not show." -ForegroundColor (Get-MessageColour warning)
    Write-Host "          Build it again, or set the font by hand in Ctrl+," -ForegroundColor (Get-MessageColour muted)
}

# Every font Windows has that a terminal can use, with what it can draw: the
# module reads the machine once for it - the window's appearance form reads the
# same list, so the two cannot drift.
Write-Host ""
Write-Host "Reading the fonts Windows has..." -ForegroundColor (Get-MessageColour muted)

$Fonts = @(Get-UsableFonts)

$Default = 0
$Changed = $false

while ($true) {
    # Read again every turn: the font in use is what the list marks, and the turn
    # before may have changed it.
    $Current = (Get-InstanceAppearance -Name $DistroName).FontName

    # And the one in use is always in the list, sorted in among the others,
    # whether it carries icons or not: on a machine where no font carries them
    # it is the only row there is.
    $Rows = @($Fonts)
    if ($Current -and -not @($Rows | Where-Object { $_.Name -eq $Current }).Count) {
        $Rows = @(($Rows + @{ Name = $Current }) | Sort-Object @{ Expression = { $_.Name } })
    }

    $Picked = Select-FromList -Title "Font of '$DistroName'" -Items $Rows -Label {
        param($Font)
        $Here = if ($Font.Name -eq $Current) { "(current)" } else { "" }
        "{0,-33} {1}" -f $Font.Name, $Here
    } -DefaultIndex $Default -Note "Get more Nerd Fonts at https://www.nerdfonts.com"

    if (-not $Picked) { break }

    # The menu has been answered: the screen goes clean, and the question takes
    # its place - then the screen again, so the list comes back on its own.
    Clear-MenuScreen

    # By name, not by reference: the row of the font in use is made again on
    # every turn, so the object the last turn handed back is not in this list.
    $Default = [array]::IndexOf(@($Rows | ForEach-Object { $_.Name }), $Picked.Name)

    # The profile is ours to write: the icon and the colours stay, the font is
    # the one just chosen - the instance's own gesture, called through the
    # engine. A machine without the profile throws, and its sentence says it.
    try {
        $null = $Manager.SetFont($Distro, $Picked.Name)
    } catch {
        Write-Host ""
        Write-Host "[ABORT] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
    }

    if (-not (Test-FontInstalled $Picked.Name)) {
        Write-Host "  Not installed on Windows: '$($Picked.Name)' - the profile points at it anyway." -ForegroundColor (Get-MessageColour warning)
    }

    Clear-MenuScreen
    $Changed = $true
}

# Leaving, by Escape or by a change made: the menu goes too, so the level above
# draws its own on a clean screen instead of under this one.
Clear-MenuScreen

if (-not $Changed) {
    # Handed over: the level above owns the goodbye.
    if ($HandedOver) { exit 0 }
    Stop-Cancelled
}

# Ask Terminal to look again, and only when run on its own: behind the theme
# menu this is asked when IT is over (see theme.ps1) - a reload only lands with
# the prompt back and the pane idle.
if (-not $HandedOver) { Update-TerminalSettings }
exit 0
