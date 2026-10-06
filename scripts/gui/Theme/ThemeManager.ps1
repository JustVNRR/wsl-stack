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
    $FontDir = Join-Path $AssetsDir "fonts"
    if (Test-Path $FontDir) {
        try {
            # The Uri overload, NOT the string one: handed a plain path, WPF
            # answers an EMPTY collection without a word (measured), and the
            # whole retro face fell back silently. And a folder-loaded family's
            # Source comes back as "./#Family Name" - a relative reference - so
            # the family travels as an OBJECT, never as a string for XAML.
            $FontUri = [Uri]("file:///" + ($FontDir -replace '\\', '/') + "/")
            foreach ($family in [Windows.Media.Fonts]::GetFontFamilies($FontUri)) {
                if ("$($family.Source)" -like "*VT323*") { $result.UiFont = $family }
                if ("$($family.Source)" -like "*Font Awesome*") { $result.IconFont = $family }
            }
        } catch { }
    }
    return $result
}

# The chart of every window: loaded on its own and merged in code - a
# Source= reference needs a base URI the loose parser never hands the inner
# dictionary (its setter dies on a null one: "baseUri cannot be null"), and
# every window gets its own copy.
function Get-ThemeDictionary {
    $ThemePath = Join-Path $PSScriptRoot "theme.xaml"
    [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml][System.IO.File]::ReadAllText($ThemePath)))
}

# The icon buttons ask for the face through a DynamicResource, and the
# FAMILY OBJECT is handed to the window by the dresser: a folder-loaded
# family's Source is a code-side reference - turned back into a string for
# XAML it fails to resolve, and WPF falls back silently (the icons came out
# as empty boxes). An object needs no resolution.
function Set-WindowPhosphorFrame {
    param($Win, $UiFont)

    if ($UiFont) {
        $Win.FontFamily = $UiFont
        $Win.FontSize = 15
    }

    # The frame treatment, once per window: no chrome, a transparent window,
    # and the phosphor border + glow drawn in code - the eight popups get it
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
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1F9E4C")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
        $border.Margin = [System.Windows.Thickness]::new(14)
        $effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $effect.Color = [System.Windows.Media.Color]::FromRgb(0x33, 0xFF, 0x66)
        $effect.BlurRadius = 10
        $effect.ShadowDepth = 0
        $effect.Opacity = 0.30
        $border.Effect = $effect
        $border.Child = $content
        $Win.Content = $border

        $Win.Add_MouseLeftButtonDown({
            param($sender, $e)
            $node = $e.OriginalSource
            try {
                while ($node -and $node -ne $sender) {
                    if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                        $node -is [System.Windows.Controls.TextBox] -or
                        $node -is [System.Windows.Controls.Primitives.ScrollBar] -or
                        $node -is [System.Windows.Controls.ComboBox]) { return }
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                }
                $sender.DragMove()
            } catch { }
        })
    }
}
