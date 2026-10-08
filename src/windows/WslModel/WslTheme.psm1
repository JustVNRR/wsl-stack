# ==============================================================================
# THE LOOK OF AN INSTANCE
# ==============================================================================
# What Windows Terminal shows for an instance: icon, colour scheme, font, tab
# title - and the recipe behind a drawn icon.
class WslTheme {
    [string]$IconPath
    [string]$ColorScheme
    [string]$FontName
    [string]$TabTitle

    # The letters and colours the icon is drawn from, so one change keeps the
    # others. Empty when the icon is an image of the user's, which has none.
    [string]$IconText
    [string]$IconTop
    [string]$IconBottom
    [string]$IconTextColor

    WslTheme() {}

    WslTheme([string]$icon, [string]$scheme, [string]$font, [string]$title) {
        $this.IconPath    = $icon
        $this.ColorScheme = $scheme
        $this.FontName    = $font
        $this.TabTitle    = $title
    }

    # The look every instance starts from: the one this repository reads and
    # ships. The pair - scheme and font - is written here, once, so no caller
    # carries it itself.
    static [WslTheme] Default([string]$tabTitle) {
        return [WslTheme]::new($null, "One Half Dark", "MesloLGS NF", $tabTitle)
    }

    # The look as one line - the font and the colours. Whoever shows it
    # decides where and when; the class only says what it is.
    [string] ToString() {
        return "font '$($this.FontName)', colours '$($this.ColorScheme)'"
    }

    # The font the Default names - the only one this repository installs. Is
    # it on Windows? Present only when both halves are: the file, and its
    # registry entry - one without the other is an interrupted install.
    [bool] FontMissing() {
        $FontRegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $DestFontPath = Join-Path (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts") "MesloLGS NF Regular.ttf"
        return -not ((Get-ItemProperty -Path $FontRegPath -Name "MesloLGS NF (TrueType)" -ErrorAction SilentlyContinue) -and (Test-Path $DestFontPath))
    }

    # Installs it for the user, best effort: a download that fails must not
    # fail a build. A file handed in - the repository's own, under assets -
    # is copied straight from there; the network is only the fallback.
    # Answers what happened for the caller to report.
    [object] EnsureFont([string]$From = "") {
        # Not named $FontName: that is this class's own member (and PowerShell
        # does not tell the two cases apart).
        $Face = "MesloLGS NF"
        $FontRegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $UserFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
        $DestFontPath = Join-Path $UserFontsDir "MesloLGS NF Regular.ttf"

        if (-not (Test-Path $FontRegPath)) {
            New-Item -Path $FontRegPath -Force | Out-Null
        }

        # The temporary file belongs to this run alone and is taken away in
        # the finally either way.
        $TempFontPath = Join-Path $env:TEMP "$([guid]::NewGuid().ToString('N')).ttf"
        try {
            $SourcePath = ""
            if ($From -and (Test-Path $From)) {
                $SourcePath = $From
            } else {
                $FontUrl = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
                Invoke-WebRequest -Uri $FontUrl -OutFile $TempFontPath -UseBasicParsing
                $SourcePath = $TempFontPath
            }

            if (-not (Test-Path $UserFontsDir)) {
                New-Item -ItemType Directory -Path $UserFontsDir -Force | Out-Null
            }
            if (-not (Test-Path $DestFontPath)) {
                Copy-Item -Path $SourcePath -Destination $DestFontPath -Force
            }
            if (-not (Get-ItemProperty -Path $FontRegPath -Name "$Face (TrueType)" -ErrorAction SilentlyContinue)) {
                New-ItemProperty -Path $FontRegPath -Name "$Face (TrueType)" -Value $DestFontPath -PropertyType String -Force | Out-Null
            }
            return [PSCustomObject]@{ State = "installed"; Error = "" }
        } catch {
            return [PSCustomObject]@{ State = "failed"; Error = "$($_.Exception.Message)" }
        } finally {
            Remove-Item -Path $TempFontPath -Force -ErrorAction SilentlyContinue
        }
    }
}
