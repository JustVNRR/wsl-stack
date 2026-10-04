# Drives the list classes with a scripted terminal: the arrow loop runs with
# no console in sight, which is the only way to test it. The terminal is a
# WslTerminal subclass (fake-terminal.ps1, next to this file) that answers
# canned keys and records the lines - the tests replace the object, not
# functions by name.
#
# Usage:  pwsh -File tests\menu-test.ps1 < tests\menu-test.answers
#
# The last checks use no fake at all - the no-console case: the list builds
# the real terminal, sees no keyboard, and reads the numbered prompt's answers
# from standard input. The .answers file is the ONLY copy of them; a second
# copy is a copy that drifts, and that is exactly what happened once.
#
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\scripts\menu.ps1")
. (Join-Path $PSScriptRoot "..\scripts\WslUI.ps1")
. (Join-Path $PSScriptRoot "fake-terminal.ps1")

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

# Rows for a plain list: the text is the value, spelled plainly.
function ItemsOf {
    param([object[]]$Values, [int[]]$Checked = @())
    $Out = @()
    for ($Index = 0; $Index -lt $Values.Count; $Index++) {
        $Row = [WslCommand]::new([string]$Values[$Index], $Values[$Index])
        if ($Checked -contains $Index) { $Row.Checked = $true }
        $Out += $Row
    }
    return ,$Out
}

# One list, the rows in, the wonderings set.
function New-List {
    param([string]$Title, [object[]]$Rows, [bool]$Multi = $false)
    $List = [WslDispatcher]::new($Title)
    foreach ($Row in $Rows) { $null = $List.Add($Row) }
    $List.Multi = $Multi
    return $List
}

# One menu, one scripted terminal, the answer.
function Run-Menu {
    param([ConsoleKey[]]$Keys, [object[]]$Items, [int]$Default = 0)
    $Terminal = [FakeTerminal]::new()
    $Terminal.Keys = [System.Collections.Queue]::new()
    foreach ($Key in $Keys) { $Terminal.Keys.Enqueue($Key) }
    $Menu = New-List "T" (ItemsOf $Items) $false
    $Menu.Terminal = $Terminal
    $Menu.Current = $Default
    return $Menu.Ask()
}

function Run-Multi {
    param([ConsoleKey[]]$Keys, [object[]]$Values, [int[]]$Checked = @())
    $Terminal = [FakeTerminal]::new()
    $Terminal.Keys = [System.Collections.Queue]::new()
    foreach ($Key in $Keys) { $Terminal.Keys.Enqueue($Key) }
    $Menu = New-List "T" (ItemsOf $Values $Checked) $true
    $Menu.Terminal = $Terminal
    $Picked = $Menu.Ask()
    if ($null -eq $Picked) { return $null }
    # The comma: this is a function, and "nothing checked" has to arrive as an
    # empty list, not as no output at all - the same trap the menu itself
    # avoids on the other side of the door.
    return ,@($Picked | ForEach-Object { $_.Value })
}

$Items = @("a", "b", "c")

Check "Down, Down, Enter        -> the third" `
    ((Run-Menu @([ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::Enter) $Items).Value) "c"
Check "Up from the first        -> the last (wrapping)" `
    ((Run-Menu @([ConsoleKey]::UpArrow, [ConsoleKey]::Enter) $Items).Value) "c"
Check "Down from the last       -> the first (wrapping)" `
    ((Run-Menu @([ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::Enter) $Items).Value) "a"
Check "Escape                   -> nothing" `
    ((Run-Menu @([ConsoleKey]::Escape) $Items).Value) ""
Check "the key 2                -> the second, no Enter needed" `
    ((Run-Menu @([ConsoleKey]::D2) $Items).Value) "b"
Check "the key 9 (off the list) -> ignored" `
    ((Run-Menu @([ConsoleKey]::D9, [ConsoleKey]::Enter) $Items).Value) "a"
Check "any other key            -> ignored" `
    ((Run-Menu @([ConsoleKey]::A, [ConsoleKey]::Enter) $Items).Value) "a"
Check "empty list               -> nothing, and nothing is asked" `
    ((New-List "T" @() $false).Ask()) ""
Check "a custom label           -> hands back the object, not the label" `
    (& {
        $Terminal = [FakeTerminal]::new()
        $Terminal.Keys = [System.Collections.Queue]::new()
        $Terminal.Keys.Enqueue([ConsoleKey]::DownArrow)
        $Terminal.Keys.Enqueue([ConsoleKey]::Enter)
        $Menu = New-List "T" @([WslCommand]::new("L-1", 1), [WslCommand]::new("L-2", 2)) $false
        $Menu.Terminal = $Terminal
        ($Menu.Ask()).Value
    }) "2"
Check "default: Enter takes it without moving" `
    ((Run-Menu @([ConsoleKey]::Enter) @("a", "b", "c") 2).Value) "c"
Check "default off the list     -> the first" `
    ((Run-Menu @([ConsoleKey]::Enter) @("a", "b", "c") 9).Value) "a"
Check "negative default         -> the first" `
    ((Run-Menu @([ConsoleKey]::Enter) @("a", "b", "c") -1).Value) "a"
Check "default = last, Down     -> wraps to the first" `
    ((Run-Menu @([ConsoleKey]::DownArrow, [ConsoleKey]::Enter) @("a", "b", "c") 2).Value) "a"

Write-Output ""
Write-Output "--- a row is one line, box or no box ---"

# The repaint only works while every row is exactly one line: a wrapped row
# makes the block taller than the arithmetic assumes, and the next keypress
# paints one line off. These checks are the invariant itself: marker, box and
# label together never exceed the width the terminal gave.
$Wide = @(("x" * 400 -join ""), ("y" * 400 -join ""))
$Cut = [WslDispatcher]::Fit($Wide, 40, 4)
Check "a plain row fits the width          " `
    ((@($Cut | ForEach-Object { 4 + $_.Length }) | Measure-Object -Maximum).Maximum) "39"
$Cut = [WslDispatcher]::Fit($Wide, 40, 8)
Check "a row with its box fits it too     " `
    ((@($Cut | ForEach-Object { 8 + $_.Length }) | Measure-Object -Maximum).Maximum) "39"
$Cut = [WslDispatcher]::Fit($Wide, 40, 0)
Check "a title or a hint fits it too       " `
    ((@($Cut | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum) "39"
Check "  ... and the cut shows as one      " ($Cut[0] -like "x*...") "True"
Check "a short label is left alone         " (@([WslDispatcher]::Fit(@("court"), 40, 4))[0]) "court"
Check "a host that says no width cuts none " (@([WslDispatcher]::Fit(@("x" * 400 -join ""), 0, 4))[0]).Length "400"

Write-Output ""
Write-Output "--- no console (numbered fallback, answers read from standard input) ---"
Check "fallback: answer 2       -> the second" `
    ((New-List "T" (ItemsOf $Items) $false).Ask().Value) "b"
Check "fallback: empty answer   -> nothing" `
    ((New-List "T" (ItemsOf $Items) $false).Ask().Value) ""
Check "fallback multi: 1, 2 then v -> both" `
    (((New-List "T" (ItemsOf $Items) $true).Ask() | ForEach-Object { $_.Value }) -join ",") "a,b"
Check "fallback multi: v alone     -> an empty list, not a cancellation" `
    ($null -eq (New-List "T" (ItemsOf $Items) $true).Ask()) "False"
Check "  ... and that list is really empty" `
    (@((New-List "T" (ItemsOf $Items) $true).Ask()).Count) "0"
Check "fallback multi: empty line  -> cancelled" `
    ((New-List "T" (ItemsOf $Items) $true).Ask()) ""

Write-Output ""
Write-Output "--- the drawing: the top of the block is read back AFTER it is drawn ---"
# A terminal that scrolls while the block is written: it answers 20 before the
# rows are drawn and 40 after. Read before drawing, 20 puts every row 20 lines
# too high - the fake terminal tells the two moments apart.
$Terminal = [FakeTerminal]::new()
$Terminal.Keys = [System.Collections.Queue]::new()
$Terminal.Keys.Enqueue([ConsoleKey]::DownArrow)
$Terminal.Keys.Enqueue([ConsoleKey]::Enter)
$Menu = New-List "T" (ItemsOf @("a", "b", "c", "d", "e")) $false
$Menu.Terminal = $Terminal
$Picked = $Menu.Ask()

Check "top read after (34..38, then 40) -> no drift" ($Terminal.Moves -join ",") "34,35,36,37,38,40"
Check "and the choice is still right" $Picked.Value "b"

Write-Output ""
Write-Output "--- -Note: one more line of the same block ---"
# The note is one more line of the block, counted everywhere: where the rows
# start, how many fit, and the line the cursor leaves on. Widened on purpose
# (20 lines for five rows) so the two halves read apart: without the note, rows
# at 34 and the way out at 40.
$Terminal = [FakeTerminal]::new()
$Terminal.Keys = [System.Collections.Queue]::new()
$Terminal.Keys.Enqueue([ConsoleKey]::DownArrow)
$Terminal.Keys.Enqueue([ConsoleKey]::Enter)
$Menu = New-List "T" (ItemsOf @("a", "b", "c", "d", "e")) $false
$Menu.Note = "Get more at https://example.test"
$Menu.Terminal = $Terminal
$Noted = $Menu.Ask()
Check "the rows (33..37) and the way out (40) count it" ($Terminal.Moves -join ",") "33,34,35,36,37,40"
Check "  ... and the choice is still right" $Noted.Value "b"

# And it is really drawn: written under the list.
Check "and it shows under the list" `
    (@($Terminal.Lines | Where-Object { "$_" -like "*Get more at https://example.test*" }).Count) 1

Write-Output ""
Write-Output "--- multi-select: space checks, Enter hands the list back ---"
$PackItems = @("gcp", "vision", "python")
Check "space checks                 -> the list handed back" `
    ((Run-Multi @([ConsoleKey]::Spacebar, [ConsoleKey]::Enter) $PackItems) -join ",") "gcp"
Check "space twice unchecks" `
    ((Run-Multi @([ConsoleKey]::Spacebar, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter) $PackItems) -join ",") ""
Check "two packs checked, in the list's order" `
    ((Run-Multi @([ConsoleKey]::Spacebar, [ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter) $PackItems) -join ",") "gcp,python"
Check "already checked: move down and uncheck" `
    ((Run-Multi @([ConsoleKey]::DownArrow, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter) $PackItems @(1, 2)) -join ",") "python"
Check "a digit toggles instead of leaving" `
    ((Run-Multi @([ConsoleKey]::D2, [ConsoleKey]::Enter) $PackItems) -join ",") "vision"
# $null -eq is the sharp test: .Count on $null answers 0 as well, so a check
# written that way would pass whether the list came back or not.
Check "Enter with nothing checked  -> an empty list, not a cancellation" `
    ($null -eq (Run-Multi @([ConsoleKey]::Enter) $PackItems)) "False"
Check "  ... and that list is really empty" `
    ((Run-Multi @([ConsoleKey]::Enter) $PackItems).Count) "0"
Check "Escape                       -> nothing at all" `
    (Run-Multi @([ConsoleKey]::Escape) $PackItems) ""
Check "single-select: space does nothing" `
    ((Run-Menu @([ConsoleKey]::Spacebar, [ConsoleKey]::Enter) $PackItems).Value) "gcp"
Check "the box shows in the row" `
    (([WslDispatcher]::FormatRow(1, 0, $PackItems, @($true, $false, $true))).Trim()) "[ ] vision"

Write-Output ""
Write-Output "--- the window: rows are cut, a tall list scrolls ---"
# A tiny window, and the list must still work: the long label is cut rather
# than wrapping, and the list scrolls instead of refusing to draw.
$Long = "remove_pack  uninstall optional tooling from an instance, dependencies included"
# @() around each: a one-element list unrolls to its element, and [0] on a
# string is its first LETTER - the same trap, met again in the test.
$Cut = @([WslDispatcher]::Fit(@($Long), 40, 4))[0]
$Short = @([WslDispatcher]::Fit(@("short"), 40, 4))[0]
$NoWidth = @([WslDispatcher]::Fit(@($Long), 0, 4))[0]
Check "cut to the width (39 max)" ($Cut.Length -le 39) $true
Check "cut: the end becomes ..." ($Cut.EndsWith("...")) $true
Check "a short label stays whole" $Short "short"
Check "unknown width (0): nothing is cut" $NoWidth $Long

$Terminal = [FakeTerminal]::new()
$Terminal.SizeAnswer = @(40, 6)
$Terminal.Keys = [System.Collections.Queue]::new()
foreach ($n in 1..6) { $Terminal.Keys.Enqueue([ConsoleKey]::DownArrow) }
$Terminal.Keys.Enqueue([ConsoleKey]::Enter)
$Menu = New-List "T" (ItemsOf @("i0", "i1", "i2", "i3", "i4", "i5", "i6", "i7", "i8", "i9")) $false
$Menu.Terminal = $Terminal
$Picked = $Menu.Ask()

# The rows as recorded: the marker says where the choice is, so the current
# row is the one carrying "> ".
$Last = $Terminal.Lines[-3..-1] -join "|"
Check "the window followed the choice (i6 current)" $Last "    i4|    i5|  > i6"
Check "and the choice is still right" ($Picked.Value) "i6"

Write-Output ""
Write-Output "--- a clean screen between levels ---"
# One call, and that is the point: the version before remembered each menu's
# rows and blanked exactly those - a row number is absolute and the console
# moves, so one scroll drew the next menu over the prompt. Replaced by this.
Check "clearing the screen is safe without one" (& { [WslConsole]::new().Clear(); "survived" }) "survived"

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
