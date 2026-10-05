# The colour of a message, on schemes written out here: no terminal window, no
# settings file, no instance, no console.
#
# The rule it checks: a scheme keeps two versions of each colour, the one read
# on its own background is the one used, and where a scheme offers nothing
# readable - a light scheme whose white is its own background - that kind is
# written in the scheme's own text colour.
#
# The colours below are the real values of schemes Windows Terminal ships,
# except the fourth, written as a list - the other way a scheme may be written.
#
# Usage:  pwsh -NoProfile -File tests\message-test.ps1

$ErrorActionPreference = "Stop"

# Read out of the terminal like the commands read it: a run inside a Windows
# Terminal window (WT_PROFILE_ID set) must answer like one anywhere else, so
# the theme below is the only one in play.
Remove-Item Env:\WT_PROFILE_ID -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\scripts\WslStack\WslStack.psd1") -Force

$Failures = 0
function Check {
    param([string]$Name, $Got, $Expected)
    if ("$Got" -eq "$Expected") {
        Write-Output "OK   $Name"
    } else {
        Write-Output "FAIL $Name : expected '$Expected', got '$Got'"
        $script:Failures++
    }
}

# The scheme a command resolved for its window - set rather than read: there is
# no window to be in. Set inside the module itself - the resolved scheme is the
# message module's own state, and reaching into a module is how a test sets it.
function Use-Theme {
    param($Scheme)
    $MessageModule = (Get-Module WslStack).NestedModules | Where-Object { $_.Name -eq 'WslStack.Message' }
    & $MessageModule {
        param($Inner)
        $script:MessageThemeRead = $true
        $script:MessageTheme = [PSCustomObject]@{
            Background = $Inner.background
            Foreground = $Inner.foreground
            Scheme     = $Inner
        }
    } $Scheme
}

$OneHalfDark = [PSCustomObject]@{
    name = "One Half Dark"; background = "#282C34"; foreground = "#DCDFE4"
    black = "#282C34"; red = "#E06C75"; green = "#98C379"; yellow = "#E5C07B"
    blue = "#61AFEF"; purple = "#C678DD"; cyan = "#56B6C2"; white = "#DCDFE4"
    brightBlack = "#5A6374"; brightRed = "#E06C75"; brightGreen = "#98C379"; brightYellow = "#E5C07B"
    brightBlue = "#61AFEF"; brightPurple = "#C678DD"; brightCyan = "#56B6C2"; brightWhite = "#DCDFE4"
}

$OneHalfLight = [PSCustomObject]@{
    name = "One Half Light"; background = "#FAFAFA"; foreground = "#383A42"
    black = "#383A42"; red = "#E45649"; green = "#50A14F"; yellow = "#C18301"
    blue = "#0184BC"; purple = "#A626A4"; cyan = "#0997B3"; white = "#FAFAFA"
    brightBlack = "#4F525D"; brightRed = "#DF6C75"; brightGreen = "#98C379"; brightYellow = "#E4C07A"
    brightBlue = "#61AFEF"; brightPurple = "#C678DD"; brightCyan = "#56B5C1"; brightWhite = "#FFFFFF"
}

# Its quiet grey is its own background, and reading it would put the footnotes
# out of sight - the one case where a kind has to look further than its colour.
$SolarizedDark = [PSCustomObject]@{
    name = "Solarized Dark"; background = "#002B36"; foreground = "#839496"
    black = "#002B36"; red = "#DC322F"; green = "#859900"; yellow = "#B58900"
    blue = "#268BD2"; purple = "#D33682"; cyan = "#2AA198"; white = "#EEE8D5"
    brightBlack = "#073642"; brightRed = "#CB4B16"; brightGreen = "#586E75"; brightYellow = "#657B83"
    brightBlue = "#839496"; brightPurple = "#6C71C4"; brightCyan = "#93A1A1"; brightWhite = "#FDF6E3"
}

Write-Output "--- nothing to read: the names every console has always had ---"
# A console window, VS Code, CI: the names this project used before this file
# existed.
Check "error   -> Red" (Get-MessageColour error) "Red"
Check "warning -> Yellow" (Get-MessageColour warning) "Yellow"
Check "success -> Green" (Get-MessageColour success) "Green"
Check "info    -> Cyan" (Get-MessageColour info) "Cyan"
Check "muted   -> DarkGray" (Get-MessageColour muted) "DarkGray"
Check "hint    -> White" (Get-MessageColour hint) "White"
Check "danger  -> DarkRed" (Get-MessageColour danger) "DarkRed"
Check "and it is a colour a console takes" ((Get-MessageColour error).GetType().Name) "ConsoleColor"

Write-Output ""
Write-Output "--- a dark scheme: what this project has always written in ---"
# The same value for both versions of each colour here - and that is the point:
# the scheme this project has been read in comes out unchanged.
Use-Theme $OneHalfDark
Check "error   -> Red" (Get-MessageColour error) "Red"
Check "warning -> Yellow" (Get-MessageColour warning) "Yellow"
Check "success -> Green" (Get-MessageColour success) "Green"
Check "info    -> Cyan" (Get-MessageColour info) "Cyan"
Check "muted   -> DarkGray (readable on it: 2.31)" (Get-MessageColour muted) "DarkGray"
Check "hint    -> White" (Get-MessageColour hint) "White"

Write-Output ""
Write-Output "--- a light scheme: the version that is read on it ---"
# One Half Light paints its bright half in pastels - white on it is its own
# background, and yellow, green and cyan all stay under 3. Its normal half
# reads at 3.0 and above, which is what these lines ask for.
Use-Theme $OneHalfLight
Check "error   -> DarkRed    (3.51, against 3.08)" (Get-MessageColour error) "DarkRed"
Check "warning -> DarkYellow (3.09, against 1.66)" (Get-MessageColour warning) "DarkYellow"
Check "success -> DarkGreen  (3.07, against 1.93)" (Get-MessageColour success) "DarkGreen"
Check "info    -> DarkCyan   (3.30, against 2.29)" (Get-MessageColour info) "DarkCyan"
Check "muted   -> DarkGray" (Get-MessageColour muted) "DarkGray"
Check "hint    -> Black, the colour it writes its text in" (Get-MessageColour hint) "Black"
Check "  ... which is its foreground, #383A42" (Get-SchemeColour -Scheme $OneHalfLight -Name "Black") "#383A42"

Write-Output ""
Write-Output "--- a quiet colour that cannot be read is not used ---"
# Its bright black sits on its own background: a footnote written in it would
# not be seen, so its text colour - one of its sixteen - is used instead.
Use-Theme $SolarizedDark
Check "muted -> Blue (its text colour), not DarkGray" (Get-MessageColour muted) "Blue"
Check "  ... which is its foreground, #839496" (Get-SchemeColour -Scheme $SolarizedDark -Name "Blue") "#839496"

Write-Output ""
Write-Output "--- a scheme written as a list ---"
# Sixteen rows in ANSI order, not console order: red is the second row here and
# the fourth value of [ConsoleColor] - read by console number, every error
# would come out green.
$AsList = [PSCustomObject]@{
    name = "Written as a list"; background = "#000000"; foreground = "#FFFFFF"
    palette = @(
        "#101010", "#202020", "#303030", "#404040", "#505050", "#606060", "#707070", "#808080",
        "#909090", "#A0A0A0", "#B0B0B0", "#C0C0C0", "#D0D0D0", "#E0E0E0", "#F0F0F0", "#FFFFFF"
    )
}
Check "dark red is the second row" (Get-SchemeColour -Scheme $AsList -Name "DarkRed") "#202020"
Check "bright red is the tenth, not the fourth" (Get-SchemeColour -Scheme $AsList -Name "Red") "#A0A0A0"
Check "and the footnotes' colour is the eighth" (Get-SchemeColour -Scheme $AsList -Name "Gray") "#808080"

Write-Output ""
Write-Output "--- a kind that is not one of the seven ---"
$Refused = $false
try { $null = Get-MessageColour "purple" } catch { $Refused = $true }
Check "an unknown kind is refused, not guessed" $Refused $true

Write-Output ""
Write-Output "--- the DANGER banner ---"
# Two colours read together, so it is drawn rather than asked for: the scheme's
# red as background, and its text read on that red.
$Box = Get-MessageColour danger
Check "the box is one of the scheme's two reds" (@("DarkRed", "Red") -contains $Box) $true
$Lines = @(Write-DangerBanner 6>&1)
Check "three lines" $Lines.Count 3
Check "and the middle one still says what it said" (@($Lines | Where-Object { "$_" -like "*DANGER: TOTAL DATA LOSS IMMINENT*" }).Count) 1
Check "the first and last are the rules around it" (@($Lines | Where-Object { "$_" -like "*====*" }).Count) 2

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
