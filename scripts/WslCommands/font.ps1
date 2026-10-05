[CmdletBinding()]
param (
    # The instance, when the theme menu has already asked which one: how the
    # level above hands over. Not an option, and not documented as one.
    [string]$DistroName,

    # Injected by wsl.ps1 (through theme.ps1), or made below once the shared
    # half is loaded: the type cannot be named here - a parameter is bound
    # before this file's first line runs, and a fresh pwsh knows nothing of the
    # classes (measured: "Unable to find type [WslInstanceManager]" at bind).
    $Manager
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

# The glyphs a prompt is drawn with: the folder, and the powerline arrow that
# says a font was made for a terminal. Either one is enough to offer it.
$Folder = 0xF07B
$Arrow = 0xE0B0

# The fonts keys name every file after the face it holds - "MesloLGS NF Regular
# (TrueType)" - so one pass over them gives family -> file.
function Get-FontFiles {
    $Files = @{}
    foreach ($Root in @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
                        "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")) {
        $Key = Get-ItemProperty -Path $Root -ErrorAction SilentlyContinue
        if (-not $Key) { continue }
        foreach ($Property in $Key.psobject.properties) {
            $Face = ($Property.Name -replace '\s*\(TrueType\)\s*$', '').Trim()
            if (-not $Face -or $Files.ContainsKey($Face)) { continue }
            $Path = [string]$Property.Value
            if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $env:WINDIR "Fonts\$Path" }
            $Files[$Face] = $Path
        }
    }
    return $Files
}

# Which glyphs this family has, read off the font file itself: a character the
# font does not have maps to glyph zero - the box. Measured, not guessed by
# looking for ink where the glyph should be: a box has ink too.
#
# $null when the file could not be read is not the same answer as "no glyphs":
# the list then says nothing rather than something wrong.
function Get-FontGlyphMap {
    param([System.Collections.Hashtable]$Files, [string]$Family)

    $Path = $null
    if ($Files.ContainsKey($Family)) { $Path = $Files[$Family] }
    if (-not $Path) {
        foreach ($Face in $Files.Keys) {
            if ($Face -like "$Family *") { $Path = $Files[$Face]; break }
        }
    }
    if (-not $Path -or -not (Test-Path $Path)) { return $null }

    try {
        Add-Type -AssemblyName PresentationCore
        $Typeface = New-Object Windows.Media.GlyphTypeface (New-Object System.Uri $Path)
        # The comma: a dictionary written to the pipeline is unrolled into its
        # entries, and the caller would get a KeyValuePair with no ContainsKey
        # on it instead of the map.
        return ,$Typeface.CharacterToGlyphMap
    } catch {
        return $null
    }
}

# A terminal font is monospaced, measured rather than assumed - 'i' and 'W' take
# the same room in one - and it is what keeps the list readable: Windows carries
# a few hundred fonts and most are for reading prose.
function Test-MonospaceFont {
    param([string]$Family)

    $Font = $null
    $Bitmap = $null
    $Canvas = $null
    try {
        $Font = New-Object System.Drawing.Font($Family, 20)
        $Format = [System.Drawing.StringFormat]::GenericTypographic
        $Bitmap = New-Object System.Drawing.Bitmap(64, 64)
        $Canvas = [System.Drawing.Graphics]::FromImage($Bitmap)
        $Narrow = $Canvas.MeasureString("iiii", $Font, 1000, $Format).Width
        $Wide = $Canvas.MeasureString("WWWW", $Font, 1000, $Format).Width
        return ([Math]::Abs($Narrow - $Wide) -lt 0.05)
    } catch {
        return $false
    } finally {
        if ($Canvas) { $Canvas.Dispose() }
        if ($Bitmap) { $Bitmap.Dispose() }
        if ($Font) { $Font.Dispose() }
    }
}

# Every font Windows has that a terminal can use, by the name a profile takes,
# with what it can draw. Asked once: the answers cannot change while it runs.
Write-Host ""
Write-Host "Reading the fonts Windows has..." -ForegroundColor (Get-MessageColour muted)

Add-Type -AssemblyName System.Drawing
$Files = Get-FontFiles
$Families = @([System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name } | Sort-Object)

# A font's styles are families of their own to GDI+ - "JetBrainsMono NF
# ExtraBold" beside "JetBrainsMono NF" - and a profile takes the family: a name
# that is another family plus a style word is left out, and nothing else is.
$Styles = @("Regular", "Bold", "Italic", "Oblique", "Light", "SemiLight", "Medium",
            "Thin", "Black", "Heavy", "SemiBold", "Semibold", "DemiBold", "ExtraBold",
            "ExtraLight", "UltraLight", "Book", "Condensed", "Narrow")

# The symbol fonts Windows ships under its own names: monospaced, so the test
# above keeps them, and full of private-area glyphs, so the one below finds
# every icon in them. Not fonts to write in, whatever their glyphs say.
$SymbolFonts = @("Wingdings", "Wingdings 2", "Wingdings 3", "Webdings", "Symbol", "Marlett")

$Fonts = @()
foreach ($Family in $Families) {
    $Base = $Family
    foreach ($Style in $Styles) {
        if ($Family -like "* $Style") {
            $Base = $Family.Substring(0, $Family.Length - $Style.Length - 1)
            break
        }
    }
    if ($Base -ne $Family -and $Families -contains $Base) { continue }
    if (-not (Test-MonospaceFont -Family $Family)) { continue }
    if ($SymbolFonts -contains $Family) { continue }

    $Glyphs = Get-FontGlyphMap -Files $Files -Family $Family

    # A font with no plain capital A is a symbol font too - Windows' own piled
    # symbols: monospaced, and its private area makes it look like it carries
    # every icon. A prompt written in one is a row of boxes.
    if ($Glyphs -and -not $Glyphs.ContainsKey([int][char]"A")) { continue }

    $HasIcons = if ($Glyphs) { $Glyphs.ContainsKey($Folder) -or $Glyphs.ContainsKey($Arrow) } else { $null }
    $Fonts += @{ Name = $Family; Icons = $HasIcons }
}

# Only the ones a prompt can be written in, and nothing is marked beside them -
# a column that says "icons" on every row says nothing. A family whose file
# could not be read is left out too: that is not the same answer as "carries
# none".
$Fonts = @($Fonts | Where-Object { $_.Icons -eq $true } | Sort-Object @{ Expression = { $_.Name } })

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
