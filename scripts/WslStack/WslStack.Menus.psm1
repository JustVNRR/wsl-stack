# ==============================================================================
# THE MENUS: THE DOORS, AND THE HELPERS THE THEME FAMILY ASKS
# ==============================================================================
# What the commands call, over the classes: Select-FromList and Select-Distro
# build a WslMenu from raw items and a label; the small helpers beside them
# (Test-KeyInput, Test-ColourOutput, ConvertTo-Rgb, Clear-MenuScreen) are what
# the theme family calls by name. Both lived in scripts\menu.ps1, then in
# WslUI.ps1, which this family left to the classes.
#
# The ask hands the WslMenuItem back instead of running it: the engine is made
# by the caller only once a command really is about to run, and the CALLER runs
# the gesture itself, at its own scope, with the command and the caller's
# context travelling in its parameters. Never through a class method: a method
# collects what it runs and takes the console away from every native underneath
# - a build's whiptail could not draw (measured).
# ==============================================================================

# The classes, as instance.ps1 walks them for the scripts - and WslUI.ps1
# beside them, which carries the menu's own three: the doors here build
# [WslMenu] rows, and a module that cannot name a type cannot build one.
$ClassLibs = @("WslState.ps1", "WslTheme.ps1", "WslPack.ps1", "WslInstance.ps1", "WslPackCatalog.ps1", "WslInstanceManager.ps1")
$ClassesDir = Join-Path $PSScriptRoot "..\WslModel"
foreach ($ClassLib in $ClassLibs) {
    $ClassPath = Join-Path $ClassesDir $ClassLib
    if (-not (Test-Path $ClassPath)) {
        throw "scripts\WslModel\$ClassLib is missing - the scripts\ folder is incomplete."
    }
    . $ClassPath
}
$MenuClasses = Join-Path $PSScriptRoot "..\WslUI.ps1"
if (-not (Test-Path $MenuClasses)) {
    throw "scripts\WslUI.ps1 is missing - the scripts\ folder is incomplete."
}
. $MenuClasses

# ---------------------------------------------------------------------------
# THE SMALL HELPERS THE COMMANDS ALREADY CALLED
# ---------------------------------------------------------------------------
# The commands ask these by name (theme.ps1 and the three children, icon, font
# and color) - kept where they always lived, and spelled as functions because
# that is how their callers know them. What a console can show, and how it
# spells a colour: WslConsole answers the same questions for the lists.
# Test-KeyInput is WslConsole's HasKeyboard twin - a method cannot name $Host,
# measured, so the class reads it through Get-Variable and this reads it
# directly.

# Is there a keyboard we can read without hanging? Both checks are cheap and
# neither one blocks: CursorTop and KeyAvailable throw without a console, and
# a throw is an answer.
function Test-KeyInput {
    if ([Console]::IsInputRedirected) { return $false }
    try {
        $null = $Host.UI.RawUI.KeyAvailable
        return $true
    } catch {
        return $false
    }
}

# Both questions have to be yes: a console that reads the escape sequences, and
# somebody looking at them - a pipe is reading a file, not a screen.
function Test-ColourOutput {
    $Coloured = $false
    try { $Coloured = [bool]$Host.UI.SupportsVirtualTerminal } catch { $Coloured = $false }
    if ($env:WT_SESSION) { $Coloured = $true }
    if ($Coloured) { $Coloured = Test-KeyInput }
    return $Coloured
}

# "#CF7040" -> "207;112;64": how a terminal spells a colour.
function ConvertTo-Rgb {
    param([string]$Hex)

    $Hex = $Hex.TrimStart("#")
    return "{0};{1};{2}" -f [Convert]::ToInt32($Hex.Substring(0, 2), 16),
                           [Convert]::ToInt32($Hex.Substring(2, 2), 16),
                           [Convert]::ToInt32($Hex.Substring(4, 2), 16)
}

# A clean screen, for going down a level or coming back up one. The first
# version blanked exactly the rows each menu had drawn - row numbers are
# absolute and the console moves, so one scroll made every remembered row a row
# off. Clearing is one call and cannot drift; the price, chosen: what was above
# goes with it.
function Clear-MenuScreen {
    try { Clear-Host } catch { }
}

# ---------------------------------------------------------------------------
# THE DOORS - WHAT THE SCRIPTS CALL, OVER THE CLASSES
# ---------------------------------------------------------------------------
# The same list, for the commands as they are written: Select-FromList builds
# a WslMenu from raw items and a label; Select-Distro composes the one list
# this family shows most. Thin on purpose - the day another interface replaces
# the console, the doors go and the classes stay.

function Select-FromList {
    param(
        [string]$Title = "",
        [object[]]$Items = @(),
        [scriptblock]$Label = { param($Item) [string]$Item },
        [int]$DefaultIndex = 0,
        [switch]$Multi,
        [int[]]$CheckedIndexes = @(),
        [string]$Note = ""
    )

    $Items = @($Items)
    if ($Items.Count -eq 0) { return $null }

    $Menu = [WslMenu]::new($Title)
    foreach ($Item in $Items) {
        $null = $Menu.Add([WslMenuItem]::new([string](& $Label $Item), $Item))
    }
    if ($Multi) {
        foreach ($Index in $CheckedIndexes) {
            if ($Index -ge 0 -and $Index -lt $Menu.Items.Count) { $Menu.Items[$Index].Checked = $true }
        }
    }
    $Menu.Multi = [bool]$Multi
    $Menu.Note = $Note
    # An index that is not in the list is the first one: the list's own rule.
    if ($DefaultIndex -ge 0 -and $DefaultIndex -lt $Menu.Items.Count) { $Menu.Current = $DefaultIndex }
    $Picked = $Menu.Prompt()

    if ($null -eq $Picked) { return $null }
    if ($Multi) {
        # The comma: a function's output is unrolled, and "I checked none"
        # must arrive as an empty list, not as nothing at all.
        return ,@($Picked | ForEach-Object { $_.Value })
    }
    return $Picked.Value
}

# The list this family shows most: the instances that are OURS, with the state
# and the room each takes. Escape is the end of the command that asked, unless
# -AllowCancel: then it is $null, for a command that has somewhere to go back
# to.
function Select-Distro {
    param([switch]$AllowCancel)

    $All = @([WslInstanceManager]::Ours())
    if ($All.Count -eq 0) {
        Write-Host ""
        Write-Host "[ABORT] No instance of this template is registered on this machine." -ForegroundColor (Get-MessageColour error)
        Write-Host "        Build one with  .\wsl.ps1 build" -ForegroundColor (Get-MessageColour hint)
        exit 1
    }

    $Menu = [WslMenu]::new("Our Instances")
    foreach ($Instance in $All) {
        $State = if ($Instance.State -eq [WslState]::Running) { "running" } else { "stopped" }
        $null = $Menu.Add([WslMenuItem]::new(
            ("{0,-30} {1,-8} {2,10}" -f $Instance.Name, $State, (Format-Size (Get-VhdxSize $Instance.Path))), $Instance))
    }
    $Picked = $Menu.Prompt()

    if ($null -eq $Picked) {
        if ($AllowCancel) { return $null }
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
    return $Picked.Value
}
