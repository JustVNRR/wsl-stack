# The window's furniture, out of the command file: the faces, the chart's
# loader and the frame every window wears. Dot-sourced by gui.ps1, so these
# functions land at the entry's scope and the windows call them from there.

# The window's faces, shipped in the repository: assets\fonts\VT323 (the
# retro terminal face) and Font Awesome 6 Free Solid (every button's icon).
# WPF reads them straight from the folder - no install, no dependency on a
# Windows font - and the families are asked of WPF itself rather than spelled
# out: the two files carry different family names under different name-table
# entries, and a guessed name would fail to a silent tofu. Missing files:
# the XAML's own face stands.
function Initialize-GuiFonts {
    param([string]$AssetsDir)

    $result = @{ UiFont = $null; IconFont = $null }
    # The Uri overload, NOT the string one: handed a plain path, WPF answers
    # an EMPTY collection without a word (measured), and the whole retro face
    # fell back silently. And a folder-loaded family's Source comes back as
    # "./#Family Name" - a relative reference - so the family travels as an
    # OBJECT, never as a string for XAML.
    foreach ($dir in Get-GuiFontFolders -AssetsDir $AssetsDir) {
        try {
            $FontUri = [Uri]("file:///" + ($dir -replace '\\', '/') + "/")
            foreach ($family in [Windows.Media.Fonts]::GetFontFamilies($FontUri)) {
                # The cache keeps serving a family whose file was deleted -
                # one glyph asked for says whether it still draws, and a dead
                # one would crash the first measure (see Test-UiFontUsable).
                if ("$($family.Source)" -like "*VT323*" -and (Test-UiFontUsable $family)) { $result.UiFont = $family }
                if ("$($family.Source)" -like "*Font Awesome*" -and (Test-UiFontUsable $family)) { $result.IconFont = $family }
            }
        } catch { }
    }
    return $result
}

# The folders that carry faces: the font home's subfolders that HOLD a font
# file right now - one folder per face, the shipped ones and every upload
# (its own folder, a path WPF never saw). The filesystem is the truth: WPF's
# folder scan keeps serving a family whose file was deleted and misses one
# whose file appeared, so the lists never hang on the scan alone (measured
# both ways).
function Get-GuiFontFolders {
    param([string]$AssetsDir)

    $fontHome = Join-Path $AssetsDir "fonts"
    if (-not (Test-Path $fontHome)) { return @() }
    return @(Get-ChildItem $fontHome -Directory | Where-Object {
        @(Get-ChildItem $_.FullName -File | Where-Object { $_.Extension -in ".ttf", ".otf" }).Count -gt 0
    } | ForEach-Object { $_.FullName })
}

# The chart of every window: loaded on its own and merged in code - a
# Source= reference needs a base URI the loose parser never hands the inner
# dictionary (its setter dies on a null one: "baseUri cannot be null"), and
# every window gets its own copy.
function Get-ThemeDictionary {
    $ThemePath = Join-Path $PSScriptRoot "theme.xaml"
    $dictionary = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($ThemePath)))

    # The machine's chosen theme, over the fresh copy: every key it tells
    # replaces the chart's own, the rest keeps the default (a theme may be
    # partial). The two versions travel in one file - the chosen one is
    # taken, and a file without blocks is a theme with a single version.
    # The name is taken for its file name alone - a stale name (the file
    # since deleted) leaves the defaults standing.
    if ($script:GuiSettings -and $script:GuiSettings.ColourSet) {
        $SetPath = Join-Path $script:AssetsDir ("colours\" + [IO.Path]::GetFileNameWithoutExtension($script:GuiSettings.ColourSet) + ".xaml")
        if (Test-Path $SetPath) {
            try {
                $set = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($SetPath)))
                foreach ($name in @($script:GuiSettings.ColourVariant, "Dark")) {
                    if ($name -and $set.Contains($name) -and $set[$name] -is [System.Windows.ResourceDictionary]) {
                        $set = $set[$name]
                        break
                    }
                }
                foreach ($key in @($set.Keys)) {
                    if ($dictionary.Contains($key)) { $dictionary[$key] = $set[$key] }
                }
            } catch { }
        }
    }
    return $dictionary
}

# The icon buttons ask for the face through a DynamicResource, and the
# FAMILY OBJECT is handed to the window by the dresser: a folder-loaded
# family's Source is a code-side reference - turned back into a string for
# XAML it fails to resolve, and WPF falls back silently (the icons came out
# as empty boxes). An object needs no resolution.
function Set-WindowPhosphorFrame {
    param($Win, $UiFont, [int]$UiFontSize = 15)

    if ($UiFont) {
        # The chosen size is a ZOOM over the 15-point base, not a font size of
        # its own: the transform scales the chrome with the text - the
        # buttons, the rows, the window - where bigger text inside fixed
        # 15-point furniture reads wrong. A window IGNORES a LayoutTransform
        # of its own (measured: set on the Window, the 19-point choice moved
        # nothing), so the content carries it; a frame Border stays outside,
        # its line and glow whole. The fixed widths scale with it, or the
        # zoomed content would clip; the layouts still measure at 15.
        $scale = $UiFontSize / 15.0
        $Win.FontFamily = $UiFont
        $Win.FontSize = 15
        $content = $Win.Content
        if ($content -is [System.Windows.Controls.Border]) { $content = $content.Child }
        if ($content) { $content.LayoutTransform = [System.Windows.Media.ScaleTransform]::new($scale, $scale) }
        if ($Win.Width) { $Win.Width = $Win.Width * $scale }
    }

    # The frame treatment, once per window: no chrome, a transparent window,
    # and the phosphor border + glow drawn in code - every popup gets it
    # without carrying XAML for it, and drag by their background like the
    # main window does. The main window wears its own and is tagged
    # 'framed', so it passes through here untouched.
    if ($Win.Tag -ne 'framed') {
        $Win.Tag = 'framed'
        $Win.WindowStyle = [System.Windows.WindowStyle]::None
        $Win.AllowsTransparency = $true
        $Win.Background = [System.Windows.Media.Brushes]::Transparent

        $content = $Win.Content
        $Win.Content = $null
        $border = New-Object System.Windows.Controls.Border
        # The frame's three colours come off the window's own chart - one
        # name each - so a game file recolours the frame like everything
        # else.
        $border.BorderBrush = $Win.FindResource("AppFrameBrush")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $border.Background = $Win.FindResource("AppBackgroundBrush")
        $border.Margin = [System.Windows.Thickness]::new(14)
        $effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $effect.Color = $Win.FindResource("AppGlowColor")
        $effect.BlurRadius = 10
        $effect.ShadowDepth = 0
        $effect.Opacity = 0.30
        $border.Effect = $effect
        $border.Child = $content
        $Win.Content = $border

        $Win.Add_MouseLeftButtonDown({
            param($source, $e)
            $node = $e.OriginalSource
            try {
                while ($node -and $node -ne $source) {
                    if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                        $node -is [System.Windows.Controls.TextBox] -or
                        $node -is [System.Windows.Controls.Primitives.ScrollBar] -or
                        $node -is [System.Windows.Controls.ComboBox]) { return }
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                }
                $source.DragMove()
            } catch { }
        })

        # The arrival - and, a beat behind it, the fleet window's exit.
        # The popup lands through a short fade waited on ContentRendered -
        # AFTER its first layout and render, never on Loaded (started
        # before, the animation competed with the window's own first pass
        # and stuttered - the creation form, the heaviest). And only once
        # the popup has rendered does the fleet window sink away and hide:
        # while the popup was building, the window stood - the screen is
        # never empty in between. The main window is tagged 'framed' and
        # never comes through here; the gate carries its return.
        $Win.Opacity = 0
        $Win.Add_ContentRendered({
            param($source, $e)
            $fade = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(180)))
            $fade.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
            $fade.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
            $source.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
            # The fleet window follows, a touch slower, and hides at the
            # end - unless the dialog is already gone (a flash close), in
            # which case the gate's return has taken over. Both names are
            # script-scope: this block outlives the function that built it.
            if ($script:window) {
                $sink = [System.Windows.Media.Animation.DoubleAnimation]::new(1, 0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220)))
                $sink.Add_Completed({
                    param($source, $e)
                    if ($script:DialogDepth -gt 0) { $script:window.Hide() }
                })
                $script:window.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $sink)
            }
        })
    }
}

# THE GUI'S OWN SETTINGS - the window's face: the family, its size, the
# theme and its version (dark or light); saved under LOCALAPPDATA (a
# machine's taste does not live in the repository; the chart in
# theme.xaml stays the default). Missing file, missing keys or a broken
# one: the shipped face stands.
function Get-GuiSettings {
    $settings = [PSCustomObject]@{ FontFamily = "VT323"; FontSize = 15; ColourSet = "phosphor"; ColourVariant = "Dark" }
    $path = Join-Path $env:LOCALAPPDATA "wsl-stack\gui-settings.json"
    if (Test-Path $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($saved.FontFamily) { $settings.FontFamily = "$($saved.FontFamily)" }
            if ($saved.FontSize) { $settings.FontSize = [int]$saved.FontSize }
            if ($saved.ColourSet) { $settings.ColourSet = "$($saved.ColourSet)" }
            if ($saved.ColourVariant) { $settings.ColourVariant = "$($saved.ColourVariant)" }
        } catch { }
    }
    return $settings
}

function Save-GuiSettings {
    param($Settings)

    $dir = Join-Path $env:LOCALAPPDATA "wsl-stack"
    $null = New-Item -ItemType Directory -Path $dir -Force
    $Settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir "gui-settings.json") -Encoding utf8NoBOM
}

# The families the gui may wear, the cheap half: the repository's font
# folder - VT323, and whatever was uploaded beside it (Font Awesome is
# icons, not a face). The installed-font half is asked lazily, when the
# settings window opens - the detection draws glyphs and has no business on
# the launch path.
function Get-GuiFontChoices {
    param([string]$AssetsDir)

    $families = @()
    $seen = @{}
    foreach ($dir in Get-GuiFontFolders -AssetsDir $AssetsDir) {
        try {
            $uri = [Uri]("file:///" + ($dir -replace '\\', '/') + "/")
            foreach ($family in [Windows.Media.Fonts]::GetFontFamilies($uri)) {
                if ("$($family.Source)" -like "*Font Awesome*") { continue }
                # A family whose file was deleted keeps being served by the
                # font cache: asked for one glyph, the dead ones answer
                # themselves (see Test-UiFontUsable) - and never get offered.
                if (-not (Test-UiFontUsable $family)) { continue }
                $name = "$($family.FamilyNames.Values | Select-Object -First 1)"
                if (-not $name) { $name = "$($family.Source)" -replace '^\./#', '' }
                if ($seen.ContainsKey($name)) { continue }
                $seen[$name] = $true
                $families += [PSCustomObject]@{ Name = $name; Family = $family; Folder = $dir }
            }
        } catch { }
    }
    return @($families | Sort-Object Name)
}

# The themes the window may wear: the little files under assets\colours,
# by file name - each carries its dark and light versions. The chart in
# theme.xaml is the fallback. One file dropped there is one more theme.
function Get-GuiColourSets {
    param([string]$AssetsDir)

    $root = Join-Path $AssetsDir "colours"
    if (-not (Test-Path $root)) { return @() }
    return @(Get-ChildItem $root -File -Filter *.xaml | Sort-Object Name | ForEach-Object { $_.BaseName })
}

# Whether the theme's file carries a light version: the header's sun/moon
# button has nothing to switch otherwise (a flat file is a theme with one
# version). A missing or broken file: nothing to switch either.
function Test-GuiThemeHasLight {
    param([string]$AssetsDir, [string]$Name)

    if (-not $Name) { return $false }
    $path = Join-Path $AssetsDir ("colours\" + [IO.Path]::GetFileNameWithoutExtension($Name) + ".xaml")
    if (-not (Test-Path $path)) { return $false }
    try {
        $theme = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($path)))
        return ($theme.Contains("Light") -and $theme["Light"] -is [System.Windows.ResourceDictionary])
    } catch {
        return $false
    }
}

# Widen a window to what its content asks - measured at the face it wears -
# without ever narrowing it under its own width, and never past the cap (the
# screen keeps a breath, and 1100 stays the hard one). With -Shrink the
# window fits the content EXACTLY (clamped): for the windows whose declared
# width is a guess rather than a need - a wrapping form's is a need, since
# its text measures unwrapped under an infinite constraint. The measurement
# is the device width: a zoom riding inside the content comes into its
# parent's desire, so a wide face neither clips nor folds its long lines.
function Set-WindowFitToContent {
    param($Win, [double]$Cap = 1100, [switch]$Shrink)

    $content = $Win.Content
    if (-not $content) { return }
    # PositiveInfinity, not Infinity: the short name does not exist and
    # PowerShell answers $null in silence - the measure then runs at 0x0 and
    # widens nothing (measured the hard way).
    $content.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $needed = [Math]::Ceiling($content.DesiredSize.Width) + 2
    $cap = [Math]::Min($Cap, [System.Windows.SystemParameters]::WorkArea.Width - 80)
    $fitted = [Math]::Min($needed, $cap)
    if ($Shrink) {
        $Win.Width = [Math]::Max($Win.MinWidth, $fitted)
    } else {
        $Win.Width = [Math]::Max($Win.Width, $fitted)
    }
}

# A family whose file is gone still EXISTS: the font cache keeps serving the
# folder's entry, the family object builds fine, and the first glyph read
# throws deep in the text stack, where nothing catches - the process dies
# (measured: FileNotFoundException through TextBlock.MeasureOverride). One
# glyph asked for here answers the same question, catchable.
function Test-UiFontUsable {
    param($UiFont)

    if (-not $UiFont) { return $false }
    try {
        $typeface = New-Object Windows.Media.Typeface($UiFont,
            [Windows.FontStyles]::Normal, [Windows.FontWeights]::Normal, [Windows.FontStretches]::Normal)
        $ft = New-Object Windows.Media.FormattedText("x",
            [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight,
            $typeface, [double]12, [Windows.Media.Brushes]::Black, [double]1)
        $null = $ft.Width
        return $true
    } catch {
        return $false
    }
}

# The saved family's object: the folders first (their faces travel as
# objects), then the machine's installed list by name. A name that matches
# nothing - a settings file pointing at a font since deleted - comes back
# $null and the caller keeps the shipped face.
function Resolve-UiFont {
    param([string]$AssetsDir, [string]$Name)

    if (-not $Name) { return $null }
    $found = @(Get-GuiFontChoices -AssetsDir $AssetsDir | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    if ($found -and (Test-UiFontUsable $found.Family)) { return $found.Family }
    $system = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { "$($_.Source)" })
    if ($system -contains $Name) {
        $family = [Windows.Media.FontFamily]::new($Name)
        if (Test-UiFontUsable $family) { return $family }
    }
    return $null
}
