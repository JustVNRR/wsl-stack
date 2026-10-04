# Drives the way in's trio with a scripted terminal: the arrow loop and the
# numbered prompt run with no console in sight, which is the only way to test
# them. The terminal is a WslTerminal subclass (fake-terminal.ps1, next to
# this file) that answers canned keys, records the lines instead of drawing
# them, and can say there is no keyboard. The gestures are counted, not run.
#
# The last checks spawn wsl.ps1 itself, where its words live: the invalid
# command and its table, and the cancelled menu - both leave before the
# engine is ever made, so nothing here needs wsl.exe.
#
# Usage:  pwsh -File tests\wslui-test.ps1
#
$ErrorActionPreference = "Stop"
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

# The three rows the checks walk: the real words of the real table, so the
# twelve-wide column and the marker are read the way the docs show them.
function New-TestDispatcher {
    $D = [WslDispatcher]::new("WSL Stack")
    $null = $D.Add([WslCommand]::new("list",  "list our instances and the archives", { $script:Ran += "list" }))
    $null = $D.Add([WslCommand]::new("build", "build an instance from the image",    { $script:Ran += "build" }))
    $null = $D.Add([WslCommand]::new("start", "start a stopped instance",            { $script:Ran += "start" }))
    return $D
}

# One run, one scripted keyboard, the answer - and the gesture, the way wsl.ps1
# runs it: the ask hands the command back, the caller executes.
function Run-Choice {
    param([ConsoleKey[]]$Keys)
    $script:Ran = @()
    $D = New-TestDispatcher
    $T = [FakeTerminal]::new()
    $T.Keys = [System.Collections.Queue]::new()
    foreach ($Key in $Keys) { $T.Keys.Enqueue($Key) }
    $D.Terminal = $T
    $Picked = $D.Ask()
    if ($Picked) { $Picked.Execute($null) }
    return $Picked
}

Check "Down, Down, Enter        -> the third" `
    ((Run-Choice @([ConsoleKey]::DownArrow, [ConsoleKey]::DownArrow, [ConsoleKey]::Enter)).Key) "start"
Check "  ... and its gesture ran" ($script:Ran -join ",") "start"
Check "Up from the first        -> the last (wrapping)" `
    ((Run-Choice @([ConsoleKey]::UpArrow, [ConsoleKey]::Enter)).Key) "start"
Check "Escape                   -> nothing" `
    (Run-Choice @([ConsoleKey]::Escape)) ""
Check "  ... and nothing ran" ($script:Ran -join ",") ""
Check "the key 2                -> the second, no Enter needed" `
    ((Run-Choice @([ConsoleKey]::D2)).Key) "build"
Check "the key 9 (off the list) -> ignored" `
    ((Run-Choice @([ConsoleKey]::D9, [ConsoleKey]::Enter)).Key) "list"
Check "any other key            -> ignored" `
    ((Run-Choice @([ConsoleKey]::A, [ConsoleKey]::Enter)).Key) "list"
Check "empty list               -> nothing, and nothing is asked" `
    (([WslDispatcher]::new("WSL Stack")).Ask()) ""

Write-Output ""
Write-Output "--- the block: the marker, the column, the words ---"
# The first six lines of one draw, whole: the blank, the title, the three rows
# (the current one behind the marker) and the hint. The rows are the ones the
# commands page shows, column included, word for word.
$D = New-TestDispatcher
$T = [FakeTerminal]::new()
$T.SizeAnswer = @(80, 20)          # the window the docs' samples assume
$T.Keys = [System.Collections.Queue]::new()
$T.Keys.Enqueue([ConsoleKey]::Enter)
$D.Terminal = $T
$null = $D.Ask()
Check "the block, six lines, whole" ($T.Lines[0..5] -join "|") `
    "|WSL Stack|  > list         list our instances and the archives|    build        build an instance from the image|    start        start a stopped instance|  up/down to move, Enter to choose, Escape to cancel"

Write-Output ""
Write-Output "--- a row is one line: cut to the window ---"
# The repaint only works while every row is exactly one line: marker and label
# together never exceed the width the terminal gave.
$Wide = "x" * 400
Check "a row with its marker fits the width" `
    (4 + @([WslDispatcher]::Fit(@($Wide), 40, 4))[0].Length) "39"
Check "  ... and the cut shows as one" `
    (@([WslDispatcher]::Fit(@($Wide), 40, 4))[0] -like "x*...") "True"
Check "a short label is left alone" `
    (@([WslDispatcher]::Fit(@("court"), 40, 4))[0]) "court"
Check "a host that says no width cuts none" `
    (@([WslDispatcher]::Fit(@($Wide), 0, 4))[0]).Length "400"

Write-Output ""
Write-Output "--- the repaint: the top of the block is read back AFTER it is drawn ---"
# A terminal that scrolls while the block is written: it answers 20 before the
# rows are drawn and 40 after. Read before drawing, 20 puts every row 20 lines
# too high - the fake tells the two moments apart.
$D = New-TestDispatcher
$T = [FakeTerminal]::new()
$T.Keys = [System.Collections.Queue]::new()
$T.Keys.Enqueue([ConsoleKey]::DownArrow)
$T.Keys.Enqueue([ConsoleKey]::Enter)
$D.Terminal = $T
$Picked = $D.Ask()
Check "top read after (36..38, then 40) -> no drift" ($T.Moves -join ",") "36,37,38,40"
Check "  ... and the choice is right" $Picked.Key "build"

Write-Output ""
Write-Output "--- the window: a tall list scrolls ---"
# A tiny window, and the list must still work: only the rows that fit are
# drawn, and the window follows the choice - the current row carries the
# marker.
$D = [WslDispatcher]::new("WSL Stack")
foreach ($Index in 0..9) { $null = $D.Add([WslCommand]::new("c$Index", "d$Index", {})) }
$T = [FakeTerminal]::new()
$T.SizeAnswer = @(40, 6)
$T.Keys = [System.Collections.Queue]::new()
foreach ($n in 1..6) { $T.Keys.Enqueue([ConsoleKey]::DownArrow) }
$T.Keys.Enqueue([ConsoleKey]::Enter)
$D.Terminal = $T
$Picked = $D.Ask()
# A two-letter word in the twelve-wide column: eleven spaces between it and
# its description.
$Column = (" " * 11)
Check "the window followed the choice (c6 current)" ($T.Lines[-3..-1] -join "|") `
    "    c4${Column}d4|    c5${Column}d5|  > c6${Column}d6"
Check "  ... and the choice is right" $Picked.Key "c6"

Write-Output ""
Write-Output "--- the command line: Dispatch routes, and runs nothing by itself ---"
$script:Ran = @()
$D = New-TestDispatcher
Check "the word names its command" ($D.Dispatch("list").Key) "list"
Check "the case does not matter" ($D.Dispatch("LIST").Key) "list"
Check "a word nobody knows     -> nothing" ($D.Dispatch("nope")) ""
Check "  ... and routing alone ran no gesture" ($script:Ran -join ",") ""

Write-Output ""
Write-Output "--- the gesture's context: everything arrives in its parameters ---"
# wsl.ps1's own shape, pinned: one gesture block for every command, and the
# command and the run context arrive as parameters - nothing is read from a
# scope at call time (a closure that read its variables by name worked on one
# machine and came up empty on another - measured). The context is made after
# the block, like the manager.
$Gesture = { param($Command, $Run) $script:Seen = "$($Command.Key):$($Run.Note)" }
$Cmd = [WslCommand]::new("list", "list our instances and the archives", $Gesture)
$Run = @{ Note = "made-after" }
$Cmd.Execute($Run)
Check "the command and the late context arrive whole" $script:Seen "list:made-after"

Write-Output ""
Write-Output "--- no keyboard: the numbered prompt ---"
# The rows, the cancel line and the question, word for word - and the answers
# come from the scripted terminal, not a console.
function New-NumberRun {
    param([string[]]$Answers)
    $script:Ran = @()
    $D = New-TestDispatcher
    $T = [FakeTerminal]::new()
    $T.KeyboardAnswer = $false
    $T.Answers = [System.Collections.Queue]::new()
    foreach ($Answer in $Answers) { $T.Answers.Enqueue($Answer) }
    $D.Terminal = $T
    return @($D, $T)
}

$Run = New-NumberRun @("2")
$Picked = $Run[0].Ask()
if ($Picked) { $Picked.Execute($null) }
Check "answer 2                 -> the second" $Picked.Key "build"
Check "  ... and its gesture ran" ($script:Ran -join ",") "build"
Check "the rows are numbered, the column holds" `
    ($Run[1].Lines -contains "   2.  build        build an instance from the image") "True"
Check "  ... and the question says what to type" ($Run[1].Prompts -join "|") "Which one? (0 to cancel)"

$Run = New-NumberRun @("0")
Check "answer 0                 -> nothing" ($Run[0].Ask()) ""
$Run = New-NumberRun @("")
Check "empty answer             -> nothing" ($Run[0].Ask()) ""
$Run = New-NumberRun @("x", "1")
$Picked = $Run[0].Ask()
Check "a word, then 1           -> the first" $Picked.Key "list"
Check "  ... and the word was caught" `
    ($Run[1].Lines -contains "  'x' is not one of the numbers above.") "True"

Write-Output ""
Write-Output "--- wsl.ps1 itself: both refusals, before the engine is ever made ---"
# The words live in wsl.ps1, so a child process is where they are read. Both
# paths leave before the manager is made - nothing here needs wsl.exe.
$Entry = Join-Path $PSScriptRoot "..\wsl.ps1"
$Out = (& pwsh -NoProfile -File $Entry bogus 2>&1 | Out-String)
Check "a word nobody knows says so, and lists" `
    ($Out.Contains("[ABORT] Invalid command 'bogus'. Available commands:")) "True"
Check "  ... and the table is whole" `
    (@("list", "build", "start", "stop", "restart", "shell", "add_pack", "remove_pack", "manage_packs", "theme", "unregister", "archive", "restore", "duplicate", "shrink", "wslconfig") |
        Where-Object { $Out -notmatch "\b$_\b" }).Count "0"
Check "  ... and the code says failure" $LASTEXITCODE "1"

$Out = ("0" | & pwsh -NoProfile -File $Entry 2>&1 | Out-String)
Check "the menu, answered 0, cancels and says so" `
    ($Out.Contains("[ABORT] Operation cancelled by user. Nothing was run.")) "True"
Check "  ... and the code says success" $LASTEXITCODE "0"

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
