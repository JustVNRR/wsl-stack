[CmdletBinding()]
param (
    # The instance's name. The letters AND the colours are read from it, so one
    # name is the whole icon - and the same name always draws the same one.
    [string]$Name,

    # A monogram and colours given by hand - whatever is given wins over -Name.
    # Nothing here is required.
    [string]$Text,
    [string]$Top,
    [string]$Bottom,
    [string]$TextColor,

    [int]$Size = 256,

    # For a caller that reports on its own: the build says what it drew, and
    # the drawing has nothing to add.
    [switch]$Quiet,

    # The table itself, one row per line, for the command that asks which
    # colours to use. Nothing is drawn.
    [switch]$ListPairs,

    # The letters this name would be drawn with, and nothing else: for a caller
    # that has to offer them as a default before drawing anything.
    [switch]$Letters,

    # One line of JSON on the output stream: the letters and the three colours,
    # as drawn. The caller notes them in its own file, one per instance. Said
    # with this, the drawing keeps its chatter to itself.
    [switch]$What,

    [string]$Out = "terminal-icon.png"
)

# Generates the Windows Terminal profile icon of an instance, and the icon of
# any other project: the script depends on nothing in this repository, so
# copying this single file is enough to reuse it.
#
#   .\make-icon.ps1 -Name wagon -Out D:\WSL\wagon\terminal-icon.png
#   .\make-icon.ps1 -Name wagon -What -Out ...       # and say what was drawn,
#                                                    # one line of JSON
#   .\make-icon.ps1 -Text ML -Top "#3B82F6"          # by hand, for another use
#   .\make-icon.ps1 -ListPairs                       # the colours a name can get
#   .\make-icon.ps1 -Letters -Name wagon             # the letters it would be drawn with
#
# The monogram width, the corner radius and the gradient direction are fixed on
# purpose: chosen by eye for legibility at tab size (~16 px), where a gradient
# reads as a flat colour and fine detail disappears.
#
# Two GDI+ details worth keeping if this is ever rewritten:
#   - FillMode.Winding. Glyph outlines overlap, and the default (Alternate)
#     treats an overlap as a hole: the D's stem gets a hairline vertical seam.
#   - centring on the glyph INK bounds, not the font em box. The em box keeps
#     room for descenders this monogram does not have, so the text sits high.

# The pairs a name chooses from: a flat background, and the text colour that
# reads on it - picked by eye, a choice rather than a calculation. The first row
# is the orange this repository shipped for years; the others are its
# neighbours.
$Palette = @(
    @{ Name = "orange";   Top = "#CF7040"; Bottom = "#B95E30"; Text = "#FFFFFF" },
    @{ Name = "blue";     Top = "#3B82F6"; Bottom = "#2563EB"; Text = "#FFFFFF" },
    @{ Name = "green";    Top = "#2E8B57"; Bottom = "#1F5C3E"; Text = "#FFFFFF" },
    @{ Name = "purple";   Top = "#7C5CBF"; Bottom = "#5B3F9E"; Text = "#FFFFFF" },
    @{ Name = "red";      Top = "#C0453B"; Bottom = "#93291F"; Text = "#FFFFFF" },
    @{ Name = "teal";     Top = "#148F8A"; Bottom = "#0E6B67"; Text = "#FFFFFF" },
    @{ Name = "graphite"; Top = "#4B5563"; Bottom = "#374151"; Text = "#FFFFFF" },
    @{ Name = "sand";     Top = "#E3C567"; Bottom = "#C9A73F"; Text = "#2A2410" }
)

# The two letters a name is read by: one piece gives its first two letters
# (wagon -> WA); several give the first letter of the first two (my-project ->
# MP). A piece opening on a digit is not a word: Ubuntu-22.04 -> UB, not U2. A
# one-letter name gives one letter.
function Get-Letters {
    param([string]$Instance)

    $Pieces = @($Instance -split '[-_.]' | Where-Object { $_ -match '^[A-Za-z]' })
    if ($Pieces.Count -ge 2) {
        return ($Pieces[0].Substring(0, 1) + $Pieces[1].Substring(0, 1)).ToUpper()
    }

    $Word = @($Instance -split '[-_.]' | Where-Object { $_ })[0]
    if (-not $Word) { return "?" }
    if ($Word.Length -ge 2) { return $Word.Substring(0, 2).ToUpper() }
    return $Word.ToUpper()
}

# Which row of the table a name gets. Not .NET's GetHashCode(): it is seeded per
# process, so the same name would come back a different colour every run - the
# one thing an icon must never do. This one is written out and gives the same
# answer on any machine; neighbours in a list (test1, test2) must not collide.
function Get-PaletteIndex {
    param([string]$Instance)

    $Hash = [long]0
    foreach ($Character in $Instance.ToLowerInvariant().ToCharArray()) {
        $Hash = ($Hash * 31 + [int]$Character) % 1000003
    }
    return [int]($Hash % $Palette.Count)
}

# The table, for the command that offers it: one row per line, tab-separated -
# name, top, bottom, text colour. Read by another script, so it goes to the
# output stream, not the console.
if ($ListPairs) {
    foreach ($Row in $Palette) {
        "{0}`t{1}`t{2}`t{3}" -f $Row.Name, $Row.Top, $Row.Bottom, $Row.Text
    }
    return
}

if ($Letters) {
    if (-not $Name) { throw "The letters are read from a name: give a -Name." }
    Get-Letters $Name
    return
}

if (-not $Name -and -not $Text) {
    throw "Nothing to draw: give a -Name (the letters and the colours come from it) or a -Text."
}

$Row = $Palette[0]
if ($Name) {
    $Row = $Palette[(Get-PaletteIndex $Name)]
    if (-not $Text) { $Text = Get-Letters $Name }
}
if (-not $Top) { $Top = $Row.Top }
if (-not $Bottom) { $Bottom = $Row.Bottom }
if (-not $TextColor) { $TextColor = $Row.Text }

Add-Type -AssemblyName System.Drawing

$family = $null
foreach ($name in @("Cascadia Mono", "Cascadia Code", "Consolas", "Segoe UI")) {
    try { $family = New-Object System.Drawing.FontFamily($name); break } catch { }
}
if (-not $family) { throw "No usable font family found on this machine." }

# A glyph outline path, sized in pixels
function Get-Monogram([single]$PixelSize) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.FillMode = [System.Drawing.Drawing2D.FillMode]::Winding
    $path.AddString($Text, $family, [int][System.Drawing.FontStyle]::Bold, $PixelSize,
                     (New-Object System.Drawing.PointF(0, 0)),
                     [System.Drawing.StringFormat]::GenericTypographic)
    return $path
}

function ConvertTo-Color([string]$Html) {
    return [System.Drawing.ColorTranslator]::FromHtml($Html)
}

$bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
$canvas.SmoothingMode = 'AntiAlias'
$canvas.Clear([System.Drawing.Color]::Transparent)

# Rounded to a whole pixel: a fractional margin puts the tile edge mid-pixel,
# which softens it.
$margin = [single][Math]::Round($Size * 0.023)
$rect = New-Object System.Drawing.RectangleF($margin, $margin,
            [single]($Size - 2 * $margin), [single]($Size - 2 * $margin))

# Rounded square: radius is 22% of the side
$radius = [single]($rect.Width * 0.22)
$diameter = [single]($radius * 2)
$tile = New-Object System.Drawing.Drawing2D.GraphicsPath
$tile.AddArc($rect.X, $rect.Y, $diameter, $diameter, [single]180, [single]90)
$tile.AddArc(($rect.Right - $diameter), $rect.Y, $diameter, $diameter, [single]270, [single]90)
$tile.AddArc(($rect.Right - $diameter), ($rect.Bottom - $diameter), $diameter, $diameter, [single]0, [single]90)
$tile.AddArc($rect.X, ($rect.Bottom - $diameter), $diameter, $diameter, [single]90, [single]90)
$tile.CloseFigure()

$gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect, (ConvertTo-Color $Top), (ConvertTo-Color $Bottom), 90)
$canvas.FillPath($gradient, $tile)

# Sized from a reference render, then fitted to whichever side runs out first:
# a one-letter mark must not overflow the tile vertically.
$probe = Get-Monogram 100
$probeBounds = $probe.GetBounds()
$probe.Dispose()
$scale = [Math]::Min(($rect.Width * 0.74) / $probeBounds.Width,
                     ($rect.Height * 0.74) / $probeBounds.Height)

$monogram = Get-Monogram ([single](100 * $scale))
$bounds = $monogram.GetBounds()
$shift = New-Object System.Drawing.Drawing2D.Matrix
$shift.Translate([single]($rect.X + ($rect.Width - $bounds.Width) / 2 - $bounds.X),
                 [single]($rect.Y + ($rect.Height - $bounds.Height) / 2 - $bounds.Y))
$monogram.Transform($shift)
$canvas.FillPath((New-Object System.Drawing.SolidBrush((ConvertTo-Color $TextColor))), $monogram)

$target = [System.IO.Path]::GetFullPath($Out)
$bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
$bitmap.Dispose()

if ($What) {
    [PSCustomObject]@{
        Text      = $Text
        Top       = $Top
        Bottom    = $Bottom
        TextColor = $TextColor
    } | ConvertTo-Json -Compress
}

if (-not $Quiet -and -not $What) {
    Write-Host ("Wrote {0}" -f $target)
    Write-Host ("  {0}x{0} px, monogram '{1}', {2} -> {3}" -f $Size, $Text, $Top, $Bottom)
}
