[CmdletBinding()]
param (
    # The instance, when the theme menu has already asked which one: how the
    # level above hands over. Not an option - and not a command of wsl.ps1.
    [string]$DistroName,

    # Injected by wsl.ps1 (through theme.ps1), or instantiated on-demand if
    # executed standalone
    [WslInstanceManager]$Manager = [WslInstanceManager]::new([WslInstanceManager]::Root())
)

# The icon is a file, not a setting: terminal-icon.png in the instance's own
# folder, the one the Terminal profile points at. This command draws another
# over it, or copies an image there - the instance owns the file and the path,
# through the engine. Nothing has to be stopped for it: an icon belongs to a
# tab as it is opened.
#
# It keeps asking - one change keeps the others, so two changes are one visit.
# Escape leaves.

$ErrorActionPreference = "Stop"

$InstanceLib = Join-Path $PSScriptRoot "instance.ps1"
if (-not (Test-Path $InstanceLib)) {
    Write-Host ""
    Write-Host "[ABORT] scripts\instance.ps1 is missing - the scripts\ folder is incomplete." -ForegroundColor (Get-MessageColour error)
    exit 1
}
. $InstanceLib

# One script draws every icon, whether an instance is built or its icon is
# redrawn years later: the letters and the colours cannot drift apart.
$IconScript = Join-Path (Split-Path -Path $PSScriptRoot -Parent) "assets\make-icon.ps1"
if (-not (Test-Path $IconScript)) {
    Write-Host ""
    Write-Host "[ABORT] assets\make-icon.ps1 is missing - the checkout is incomplete." -ForegroundColor (Get-MessageColour error)
    Write-Host "        Nothing was modified." -ForegroundColor (Get-MessageColour muted)
    exit 1
}

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

# The menus it came through come off the screen: a visit of four turns is one
# screen, not four stacked menus.
Clear-MenuScreen

# Worth saying before the question because it is what would make all of it
# invisible: an icon is only ever read through the fragment this repository
# writes.
$OurFragment = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack\$DistroName.json"
if (-not (Test-Path $OurFragment)) {
    Write-Host ""
    Write-Host "[WARNING] This instance has no Terminal profile of ours - the icon would not show." -ForegroundColor (Get-MessageColour warning)
    Write-Host "          Build it again, or set the icon by hand in Ctrl+," -ForegroundColor (Get-MessageColour muted)
}

# The escape character, and whether colours are worth writing: the second from
# WslUI.ps1, where it is written once for every command that shows a colour.
$Escape = [char]27
$Coloured = Test-ColourOutput

# One turn of the menu: ask what the choice needs, then have the instance draw
# the icon or take the image in - and note what it is made of in its own file.
#
# A drawing that fails leaves the icon that was there: the drawing script
# writes the picture once, at the end.
function Invoke-IconChoice {
    param([hashtable]$Choice, [hashtable]$Recipe, [string]$Suggestion)

    # What the drawing script is told, by name: -Name gives the letters and the
    # colours, and whatever is put beside it wins - the recipe first, so only
    # the part being changed moves.
    #
    # A hashtable, not a list: handed a LIST the script reads its values in
    # order, not by name - "-Text" would land where a colour is expected and the
    # tile would be drawn in the colour of the word "-Text".
    $Draw = @{ Name = $DistroName }
    $Draw += $Recipe
    $Source = $null

    switch ($Choice.How) {
        "auto" {
            # Start again from the name - the kept letters and colours go with
            # it.
            $Draw = @{ Name = $DistroName }
        }
        "letters" {
            # Up to three: a tab is about sixteen pixels tall, and past three
            # letters stop being letters.
            $Question = if ($Suggestion) { "Letters, 1 to 3 [$Suggestion]" } else { "Letters, 1 to 3" }
            while ($true) {
                Write-Host -NoNewline "${Question}: "
                $Answer = [string](Read-Host).Trim()
                # Enter takes what is suggested - the letters the icon has now,
                # or the name's. With nothing to suggest it cancels, like every
                # other empty answer here.
                if ([string]::IsNullOrWhiteSpace($Answer)) {
                    if (-not $Suggestion) { Stop-Cancelled }
                    $Draw.Text = $Suggestion
                    break
                }
                if ($Answer -match '^[A-Za-z0-9]{1,3}$') {
                    $Draw.Text = $Answer.ToUpper()
                    break
                }
                Write-Host "  One to three letters or digits." -ForegroundColor (Get-MessageColour hint)
            }
        }
        "colours" {
            $Rows = @(& $IconScript -ListPairs | Where-Object { $_ })
            $Picked = Select-FromList -Title "Colours for '$DistroName'" -Items $Rows -Label {
                param($Row)
                $Field = $Row -split "`t"
                # Two hex codes say nothing to the eye: the letters are shown
                # in the colours of the pair. Only the background is exact - the
                # ink is white, or dark on the light tile.
                $Sample = $Suggestion
                if ($Coloured) {
                    $Ink = if ($Field[3] -eq "#FFFFFF") { "97" } else { "30" }
                    $Sample = "{0}[48;2;{1}m{0}[{2}m {3} {0}[0m" -f $Escape, (ConvertTo-Rgb $Field[1]), $Ink, $Suggestion
                }
                # The pair the icon is on now - choosing is easier when you
                # know where you are.
                $Here = if ($Recipe.Top -eq $Field[1] -and $Recipe.Bottom -eq $Field[2]) { "  (current)" } else { "" }
                "{0}  {1,-9}{2}" -f $Sample, $Field[0], $Here
            }
            if (-not $Picked) { Stop-Cancelled }
            $Field = $Picked -split "`t"
            $Draw.Top = $Field[1]
            $Draw.Bottom = $Field[2]
            $Draw.TextColor = $Field[3]
        }
        "image" {
            while (-not $Source) {
                $Answer = (Read-Answer "Path of the image, PNG JPG ICO or BMP (CTRL+C to abort)").Trim('"')
                if (-not (Test-Path -LiteralPath $Answer -PathType Leaf)) {
                    Write-Host "  No file at that path." -ForegroundColor (Get-MessageColour warning)
                    continue
                }
                if ((Split-Path -Leaf $Answer) -notmatch '\.(png|jpg|jpeg|ico|bmp)$') {
                    Write-Host "  The name has to end in .png, .jpg, .jpeg, .ico or .bmp." -ForegroundColor (Get-MessageColour hint)
                    continue
                }
                $Source = (Resolve-Path -LiteralPath $Answer).Path
            }
        }
    }

    # Nothing is announced: the menu comes straight back, and the icon in the
    # tab is the answer. A failure is the one thing worth saying.
    if ($Source) {
        # The instance takes the file in - its own terminal-icon.png. The
        # recipe stays: an image replaces the picture, not the drawing behind
        # it.
        $null = $Manager.SetIconImage($Distro, $Source)
    } else {
        try {
            # The instance draws the recipe and wears it - the drawn recipe
            # comes back settled.
            $null = $Manager.SetIcon($Distro, $Draw)
        } catch {
            Write-Host ""
            Write-Host "[ABORT] The icon could not be drawn: $($_.Exception.Message)" -ForegroundColor (Get-MessageColour error)
            Write-Host "        The icon that was there is still there." -ForegroundColor (Get-MessageColour muted)
            exit 1
        }
    }
}

# 2. The question, again and again
$Choices = @(
    @{ What = "By Default"; How = "auto" },
    @{ What = "text";       How = "letters" },
    @{ What = "colors";     How = "colours" },
    @{ What = "local file"; How = "image" }
)

$Default = 0
$Changed = $false

while ($true) {
    # Read again every turn: the questions offer what the icon is made of now.
    # The recipe is what makes one change keep the others - redraw the colours
    # and the letters you typed stay - whatever the icon on disk is.
    $Current = Get-IconRecipe -Name $DistroName
    $Suggested = $Current.Text
    if (-not $Suggested) {
        $Suggested = [string](@(& $IconScript -Letters -Name $DistroName | Select-Object -First 1)[0])
    }

    Write-Host ""
    $Chosen = Select-FromList -Title "Icon of '$DistroName'" -Items $Choices -Label {
        param($Choice) $Choice.What
    } -DefaultIndex $Default

    if (-not $Chosen) { break }

    # The menu has been answered: the screen goes clean, and the answer takes its
    # place - then the screen again, so the menu comes back on its own.
    Clear-MenuScreen

    # The same place next time: two changes are one visit.
    $Default = [array]::IndexOf($Choices, $Chosen)

    Invoke-IconChoice -Choice $Chosen -Recipe $Current -Suggestion $Suggested

    # And the question goes when the answer is in: the menu comes back where it
    # was.
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
