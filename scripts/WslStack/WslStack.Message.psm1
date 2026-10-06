# ==============================================================================
# WHAT A LINE SAYS, AND THE COLOUR IT TAKES
# ==============================================================================
# A command never names a colour. It says what kind of line this is:
#
#   Write-Host "  Start Docker Desktop, then run this again." -ForegroundColor (Get-MessageColour hint)
#
# Six kinds are lines - error, warning, success, info, muted, hint - and the
# seventh, danger, is the DANGER banner: a box rather than a line.
#
# The colour is read from the colour scheme of the Windows Terminal profile
# this command runs in: of the two versions a scheme keeps of each colour, the
# one read on its background is used. Where a scheme offers nothing readable
# for a kind, that kind is written in the colour the scheme writes its own text
# in - the one colour it guarantees.
#
# With nothing to read - a console window, VS Code, a test, CI - the sixteen
# names a console has always had are used.
# ==============================================================================

# ---------------------------------------------------------------------------
# READING WINDOWS TERMINAL'S FILES
# ---------------------------------------------------------------------------
# Windows Terminal writes JSON with // comments and a comma before a closing
# bracket; PowerShell's reader refuses both. A blind replace is worse: the file
# holds a string of every punctuation mark ("wordDelimiters"), and taking a
# comma out of IT breaks the JSON elsewhere.
#
# So the walk below knows what a string is, and a file that still will not
# parse is no schemes at all, not a crash.
function Read-TerminalJson {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $Text = [System.IO.File]::ReadAllText($Path)
    } catch {
        return $null
    }

    try {
        $Out = New-Object System.Text.StringBuilder
        $InString = $false
        for ($Index = 0; $Index -lt $Text.Length; $Index++) {
            $Char = $Text[$Index]

            if ($InString) {
                $null = $Out.Append($Char)
                if ($Char -eq '\') {
                    $Index++
                    if ($Index -lt $Text.Length) { $null = $Out.Append($Text[$Index]) }
                    continue
                }
                if ($Char -eq '"') { $InString = $false }
                continue
            }

            if ($Char -eq '"') { $InString = $true; $null = $Out.Append($Char); continue }

            if ($Char -eq '/' -and ($Index + 1) -lt $Text.Length -and $Text[$Index + 1] -eq '/') {
                while ($Index -lt $Text.Length -and $Text[$Index] -ne "`n") { $Index++ }
                $null = $Out.Append("`n")
                continue
            }

            if ($Char -eq ',') {
                $Next = $Index + 1
                while ($Next -lt $Text.Length -and [char]::IsWhiteSpace($Text[$Next])) { $Next++ }
                if ($Next -lt $Text.Length -and ($Text[$Next] -eq '}' -or $Text[$Next] -eq ']')) { continue }
            }

            $null = $Out.Append($Char)
        }
        return ($Out.ToString() | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# The files Windows Terminal's profiles are written in - the same three
# Update-TerminalSettings names when it asks a window to read them again.
$TerminalSettings = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

# And the ones this repository writes for its instances: one per instance, by
# name, layered over the profile WSL made for it.
$OurFragments = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack"

# ---------------------------------------------------------------------------
# WHERE A SCHEME KEEPS THE SIXTEEN NAMES
# ---------------------------------------------------------------------------
# The sixteen names are two versions of eight colours; a scheme writes them one
# key each, or as a list of sixteen - in ANSI order, which is NOT the order a
# console numbers them in: red is the second row of the list and the fourth
# value of [ConsoleColor]. Reading the list by console number would paint every
# error green, and this table is the only place the two orders meet.
$SlotNames = [ordered]@{
    "Black"       = @{ Key = "black";        Index = 0 }
    "DarkRed"     = @{ Key = "red";          Index = 1 }
    "DarkGreen"   = @{ Key = "green";        Index = 2 }
    "DarkYellow"  = @{ Key = "yellow";       Index = 3 }
    "DarkBlue"    = @{ Key = "blue";         Index = 4 }
    "DarkMagenta" = @{ Key = "purple";       Index = 5 }
    "DarkCyan"    = @{ Key = "cyan";         Index = 6 }
    "Gray"        = @{ Key = "white";        Index = 7 }
    "DarkGray"    = @{ Key = "brightBlack";  Index = 8 }
    "Red"         = @{ Key = "brightRed";    Index = 9 }
    "Green"       = @{ Key = "brightGreen";  Index = 10 }
    "Yellow"      = @{ Key = "brightYellow"; Index = 11 }
    "Blue"        = @{ Key = "brightBlue";   Index = 12 }
    "Magenta"     = @{ Key = "brightPurple"; Index = 13 }
    "Cyan"        = @{ Key = "brightCyan";   Index = 14 }
    "White"       = @{ Key = "brightWhite";  Index = 15 }
}

# ---------------------------------------------------------------------------
# THE KIND OF LINE, AND THE COLOUR IT ASKS FOR
# ---------------------------------------------------------------------------
# What a kind is written in when there is no scheme to read: the names this
# project used before, which every console resolves its own way.
$WithoutScheme = [ordered]@{
    error   = "Red"
    warning = "Yellow"
    success = "Green"
    info    = "Cyan"
    muted   = "DarkGray"
    hint    = "White"
    danger  = "DarkRed"
}

# warning and hint part company here: a warning takes the colour a scheme keeps
# for cautions; a hint says what to do next and takes the colour that scheme
# writes its text in.
$FamilyOf = [ordered]@{
    error   = "red"
    warning = "yellow"
    success = "green"
    info    = "cyan"
    muted   = "quiet"
    hint    = "text"
    danger  = "red"
}

# The two versions a scheme keeps, named as a console names them. The last one
# wins a tie - the bright version, the one this project has always used,
# wherever a scheme gives the two the same value.
$VersionOfColour = [ordered]@{
    red    = @("DarkRed", "Red")
    yellow = @("DarkYellow", "Yellow")
    green  = @("DarkGreen", "Green")
    cyan   = @("DarkCyan", "Cyan")
    text   = @("Gray", "White")
    quiet  = @("DarkGray")
}

# Below this a line is not read, it is guessed - so a colour under it is
# refused and the scheme's text colour is used. It sits under the quiet grey of
# One Half Dark, the scheme this project has been read in.
$UnreadableBelow = 2.0

# The scheme is read once per command, not once per line: a command prints one
# line or two hundred, and both cost the same.
$MessageThemeRead = $false
$MessageTheme = $null

# A colour as three numbers, or nothing at all when the text is not a colour: a
# scheme is a file the user may have edited, and a broken one leaves the
# terminal's own names in place rather than stopping a command.
function Get-Rgb {
    param([string]$Hex)

    $Text = "$Hex".Trim()
    if ($Text.StartsWith("#")) { $Text = $Text.Substring(1) }
    if ($Text.Length -eq 3) { $Text = "$($Text[0])$($Text[0])$($Text[1])$($Text[1])$($Text[2])$($Text[2])" }
    if ($Text.Length -ne 6) { return $null }
    try {
        return @(
            [Convert]::ToInt32($Text.Substring(0, 2), 16),
            [Convert]::ToInt32($Text.Substring(2, 2), 16),
            [Convert]::ToInt32($Text.Substring(4, 2), 16)
        )
    } catch {
        return $null
    }
}

# How light a colour is, the way the contrast rule below counts it.
function Get-Luminance {
    param([string]$Hex)

    $Rgb = Get-Rgb $Hex
    if (-not $Rgb) { return $null }
    $Channel = {
        param($Value)
        $Part = $Value / 255
        if ($Part -le 0.03928) { return $Part / 12.92 }
        return [Math]::Pow(($Part + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * (& $Channel $Rgb[0]) + 0.7152 * (& $Channel $Rgb[1]) + 0.0722 * (& $Channel $Rgb[2])
}

# How far apart two colours are to the eye: 1 is the same colour, 21 is black on
# white. Anything under 3 is hard to read, and 1 means one of the two is the
# other - which is what a scheme whose white is its background says.
function Get-ContrastRatio {
    param([string]$A, [string]$B)

    $First = Get-Luminance $A
    $Second = Get-Luminance $B
    if ($null -eq $First -or $null -eq $Second) { return 0 }
    if ($First -lt $Second) { $Swap = $First; $First = $Second; $Second = $Swap }
    return [Math]::Round(($First + 0.05) / ($Second + 0.05), 2)
}

# How far apart two colours are, counted, not measured: it answers "which of
# these is the closest one" and nothing else, which is all it is asked.
function Get-ColourDistance {
    param([string]$A, [string]$B)

    $First = Get-Rgb $A
    $Second = Get-Rgb $B
    if (-not $First -or -not $Second) { return [double]::MaxValue }
    $Red = $First[0] - $Second[0]
    $Green = $First[1] - $Second[1]
    $Blue = $First[2] - $Second[2]
    return [double]($Red * $Red + $Green * $Green + $Blue * $Blue)
}

# One of the sixteen names, as the colour the scheme gives it - by its own key,
# or by its row in a scheme written as a list.
function Get-SchemeColour {
    param($Scheme, [string]$Name)

    $Where = $SlotNames[$Name]
    if (-not $Where -or -not $Scheme) { return $null }
    $Named = $Scheme.($Where.Key)
    if ($Named) { return "$Named" }
    $List = @($Scheme.palette)
    if ($List.Count -ge 16 -and $List[$Where.Index]) { return "$($List[$Where.Index])" }
    return $null
}

# Every colour scheme this machine can wear, by name: the name is what a profile
# takes, and what is behind it is what a list shows. The console's colour
# command and the window's appearance form both read this one set.
function Get-ColorSchemes {
    $Schemes = @{}

    # What Terminal ships, from the file inside its own package - readable by a
    # normal account, where the folder is not.
    # Asked one at a time: an array handed to -Name binds to a parameter that
    # takes one name, and the call is refused before it runs.
    $Packages = @()
    foreach ($PackageName in @("Microsoft.WindowsTerminal", "Microsoft.WindowsTerminalPreview")) {
        $Packages += @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
    }
    foreach ($Package in $Packages) {
        $Parsed = Read-TerminalJson -Path (Join-Path $Package.InstallLocation "defaults.json")
        foreach ($Scheme in @($Parsed.schemes)) {
            if ($Scheme -and $Scheme.name -and -not $Schemes.ContainsKey($Scheme.name)) {
                $Schemes[$Scheme.name] = $Scheme
            }
        }
    }

    # And what the user added, or wrote over: read last, so their own version of
    # a name wins over the one Terminal ships.
    foreach ($Path in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )) {
        $Parsed = Read-TerminalJson -Path $Path
        foreach ($Scheme in @($Parsed.schemes)) {
            if ($Scheme -and $Scheme.name) { $Schemes[$Scheme.name] = $Scheme }
        }
    }

    # And the schemes our instances wear when nothing above named them: leaving
    # one out would hide the scheme the instance is using now.
    $Ours = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\wsl-stack"
    foreach ($File in @(Get-ChildItem $Ours -Filter *.json -ErrorAction SilentlyContinue)) {
        $Parsed = Read-TerminalJson -Path $File.FullName
        $Named = @($Parsed.profiles)[0].colorScheme
        if ($Named -and -not $Schemes.ContainsKey($Named)) { $Schemes[$Named] = $null }
    }

    # The comma: a table written to the pipeline is unrolled into its entries,
    # and the caller would get the first pair instead of the table.
    return ,$Schemes
}

# The scheme the profile we are printing in wears. Windows Terminal names that
# profile in WT_PROFILE_ID; what it wears is written either in the user's own
# settings or in the fragment this repository writes for an instance, and a
# profile that says nothing itself takes the scheme of the profile defaults.
function Get-WindowColorScheme {
    param([string]$Guid)

    $Settings = @()
    foreach ($Path in $TerminalSettings) {
        $Parsed = Read-TerminalJson -Path $Path
        if ($Parsed) { $Settings += $Parsed }
    }

    foreach ($Parsed in $Settings) {
        foreach ($Profile in @($Parsed.profiles.list)) {
            if ("$($Profile.guid)" -eq $Guid -and $Profile.colorScheme) { return "$($Profile.colorScheme)" }
        }
    }

    foreach ($File in @(Get-ChildItem $OurFragments -Filter *.json -ErrorAction SilentlyContinue)) {
        $Entry = @((Read-TerminalJson -Path $File.FullName).profiles)[0]
        if ($Entry -and "$($Entry.updates)" -eq $Guid -and $Entry.colorScheme) { return "$($Entry.colorScheme)" }
    }

    foreach ($Parsed in $Settings) {
        if ($Parsed.profiles.defaults.colorScheme) { return "$($Parsed.profiles.defaults.colorScheme)" }
    }
    return $null
}

# The user's own version of the scheme first - they wrote it, and Terminal lets
# it win - then the one inside Terminal's package. Read last: asking for a
# package costs a fifth of a second.
function Get-WindowScheme {
    param([string]$Name)

    foreach ($Path in $TerminalSettings) {
        $Parsed = Read-TerminalJson -Path $Path
        foreach ($Scheme in @($Parsed.schemes)) {
            if ($Scheme -and "$($Scheme.name)" -eq $Name) { return $Scheme }
        }
    }

    $Packages = @()
    foreach ($PackageName in @("Microsoft.WindowsTerminal", "Microsoft.WindowsTerminalPreview")) {
        $Packages += @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
    }
    foreach ($Package in $Packages) {
        $Parsed = Read-TerminalJson -Path (Join-Path $Package.InstallLocation "defaults.json")
        foreach ($Scheme in @($Parsed.schemes)) {
            if ($Scheme -and "$($Scheme.name)" -eq $Name) { return $Scheme }
        }
    }
    return $null
}

# The scheme of this window, and nothing when it cannot be read: not in Windows
# Terminal, a profile with no scheme and no defaults, a scheme no file holds, or
# a colour missing from it.
function Get-MessageTheme {
    if ($MessageThemeRead) { return $MessageTheme }
    $script:MessageThemeRead = $true

    $Guid = "$env:WT_PROFILE_ID"
    if (-not $Guid) { return $null }

    $Name = Get-WindowColorScheme -Guid $Guid
    if (-not $Name) { return $null }

    $Scheme = Get-WindowScheme -Name $Name
    if (-not $Scheme -or -not $Scheme.background -or -not $Scheme.foreground) { return $null }

    $script:MessageTheme = [PSCustomObject]@{
        Background = "$($Scheme.background)"
        Foreground = "$($Scheme.foreground)"
        Scheme     = $Scheme
    }
    return $MessageTheme
}

# The name closest to the colour the scheme writes its own text in - every
# scheme read here keeps its text colour in one of the sixteen too, so this is
# a lookup, not a blend.
function Get-TextColour {
    param($Theme)

    $Nearest = $null
    $Closest = [double]::MaxValue
    foreach ($Name in $SlotNames.Keys) {
        $Hex = Get-SchemeColour -Scheme $Theme.Scheme -Name $Name
        if (-not $Hex) { continue }
        $Distance = Get-ColourDistance -A $Theme.Foreground -B $Hex
        if ($Distance -lt $Closest) { $Closest = $Distance; $Nearest = $Name }
    }
    if (-not $Nearest) { return "White" }
    return $Nearest
}

# The name of the candidates that is read best on a colour, or the fallback when
# none of them is read at all.
function Get-ReadableColour {
    param($Theme, [string]$Reference, [string[]]$Candidates, [string]$Fallback)

    $Best = $null
    $BestRatio = -1
    foreach ($Name in $Candidates) {
        $Hex = Get-SchemeColour -Scheme $Theme.Scheme -Name $Name
        if (-not $Hex) { continue }
        $Ratio = Get-ContrastRatio -A $Reference -B $Hex
        if ($Ratio -ge $BestRatio) { $BestRatio = $Ratio; $Best = $Name }
    }
    if (-not $Best) { return $Fallback }
    if ($BestRatio -lt $UnreadableBelow -and $Fallback) { return $Fallback }
    return $Best
}

# The colour of a kind of line, as a name PowerShell takes. Every command asks
# this and nothing else, so this is the whole of what the project knows about
# colours and schemes.
function Get-MessageColour {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("error", "warning", "success", "info", "muted", "hint", "danger")]
        [string]$Type
    )

    $Theme = Get-MessageTheme
    if (-not $Theme) { return [ConsoleColor]($WithoutScheme[$Type]) }

    $Candidates = @($VersionOfColour[$FamilyOf[$Type]])
    return [ConsoleColor](Get-ReadableColour -Theme $Theme -Reference $Theme.Background `
        -Candidates $Candidates -Fallback (Get-TextColour -Theme $Theme))
}

# The one box rather than a line, and the one place two colours are read
# together: the scheme's red as background, and whichever light name is read on
# that red - not on the terminal behind it.
function Write-DangerBanner {
    $Box = "DarkRed"
    $Ink = "White"

    $Theme = Get-MessageTheme
    if ($Theme) {
        $Box = Get-MessageColour danger
        $Ink = Get-ReadableColour -Theme $Theme -Reference (Get-SchemeColour -Scheme $Theme.Scheme -Name $Box) `
            -Candidates @("Gray", "White", "Black") -Fallback (Get-TextColour -Theme $Theme)
    }

    Write-Host " /!\ ================================================================ /!\" -ForegroundColor $Ink -BackgroundColor $Box
    Write-Host " |                     DANGER: TOTAL DATA LOSS IMMINENT               |" -ForegroundColor $Ink -BackgroundColor $Box
    Write-Host " \!/ ================================================================ \!/" -ForegroundColor $Ink -BackgroundColor $Box
}
