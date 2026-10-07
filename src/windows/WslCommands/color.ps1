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

# What a terminal's colours are: the colour scheme of its profile - the
# background, the text, and the sixteen colours a program may ask for by number.
# Reached through `.\wsl.ps1 theme`.
#
# The list is every scheme this machine can be told to use: those Terminal ships
# and those the user added or wrote over. Each is shown in its own colours, and
# the one in use is marked.
#
# It keeps asking, like the two commands beside it: Escape leaves.

$ErrorActionPreference = "Stop"

# Read-TerminalJson comes from the message module, imported by the entry: the
# walk that knows what a string is lives there, once.

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

Clear-MenuScreen

$OurFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$DistroName.json"
if (-not (Test-Path $OurFragment)) {
    Write-Host ""
    Write-Host "[WARNING] This instance has no Terminal profile of ours - the colours would not show." -ForegroundColor (Get-MessageColour warning)
    Write-Host "          Build it again, or set them by hand in Ctrl+," -ForegroundColor (Get-MessageColour muted)
}

$Escape = [char]27
$Coloured = Test-ColourOutput

Write-Host ""
Write-Host "Reading the colour schemes Windows Terminal has..." -ForegroundColor (Get-MessageColour muted)

$Schemes = Get-ColorSchemes
if ($Schemes.Count -eq 0) {
    Write-Host ""
    Write-Host "[ABORT] No colour scheme could be read on this machine." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}
$Rows = @($Schemes.Keys | Sort-Object)

$Default = 0
$Changed = $false

while ($true) {
    # Read again every turn: the scheme in use is what the list marks, and the
    # turn before may have changed it.
    $Current = (Get-InstanceAppearance -Name $DistroName).ColorScheme

    $Picked = Select-FromList -Title "Colours of '$DistroName'" -Items $Rows -Label {
        param($Name)

        $Scheme = $Schemes[$Name]

        # Padded, and padded INSIDE the colours: every row has to end at the
        # same column, or the painted blocks come out raggeder the longer the
        # names get. The mark gets a column of its own for the same reason.
        $Here = if ($Name -eq $Current) { "(current)" } else { "" }
        $Text = "{0,-20} {1,-11}" -f $Name, $Here

        # The mark in red, found before the row is read - and the colour goes
        # around the word INSIDE the padded text: padding a string that carries
        # escapes would count them as letters and break the column.
        if ($Here -and $Coloured) {
            $Text = $Text -replace [regex]::Escape($Here), ("{0}[91m{1}{0}[39m" -f $Escape, $Here)
        }
        $Sample = $Text

        # The scheme itself, painted: what is being chosen is a look, and a name
        # says nothing to the eye.
        #
        # The reset comes first: a label cut by a narrow window would otherwise
        # leave the terminal wearing the colours of the row it was cut in.
        if ($Coloured -and $Scheme -and $Scheme.background -and $Scheme.foreground) {
            $Sample = "{0}[0m{0}[48;2;{1}m{0}[38;2;{2}m{3}{0}[0m" -f $Escape,
                (ConvertTo-Rgb $Scheme.background), (ConvertTo-Rgb $Scheme.foreground), $Text
        }

        # And nothing else: the painted row is the whole preview.
        $Sample
    } -DefaultIndex $Default

    if (-not $Picked) { break }

    # The menu has been answered: the screen goes clean, and the answer takes its
    # place - then the screen again, so the list comes back on its own.
    Clear-MenuScreen

    $Default = [array]::IndexOf($Rows, $Picked)

    # The profile is ours to write: the icon and the font stay as they are, the
    # scheme is the one just chosen - the instance's own gesture, called through
    # the engine. A machine without the profile throws, and its sentence says
    # it.
    try {
        $null = $Manager.SetColourScheme($Distro, $Picked)
    } catch {
        Write-Host ""
        Write-Host "[ABORT] $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
        Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
        exit 1
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
