# ==============================================================================
# ASKING: THE LIST, AS OBJECTS
# ==============================================================================
# Three classes, and the doors and helpers the commands call by name:
#
#   WslMenuItem - one row: the text shown, the value carried, the tick (in a
#                 checklist).
#   WslConsole  - the terminal: keyboard, cursor, window, screen, and the one
#                 line-writer everything goes through.
#   WslMenu     - one question: a title, rows, and the two ways to answer with
#                 the arrows (Ask) or at the numbered prompt when the machine
#                 has no keyboard.
#
# The menu holds its console (one object, built by default), so the tests hand
# it a subclass that answers canned keys and records the lines - nothing is
# replaced by name any more, and no state travels between free functions.
#
# "$Host" in a method: the parser refuses the name; it is reached through
# Get-Variable - measured. And a class is not data: a data class never draws;
# WslMenu is the question itself, its console is its trade.
#
# This file defines the classes, the small helpers the commands call by name
# (the keys and colour tests, the clean screen), and the thin doors
# (Select-FromList, Select-Distro, at the bottom); it is not a command.
# ==============================================================================

# Loaded here too: tests drive this file on its own, and lines are drawn by
# asking the message palette for the colour.
. (Join-Path $PSScriptRoot "message.ps1")

# One row of a list: what it shows, what it carries, and - in a checklist -
# whether it is ticked. The value is the thing the caller asked about; the
# text is how that thing is spelled on screen.
class WslMenuItem {
    [string]$Text
    [object]$Value
    [bool]$Checked = $false

    WslMenuItem([string]$Text, [object]$Value) {
        $this.Text = $Text
        $this.Value = $Value
    }
}

# The terminal, as the menu's only collaborator. The real one touches the real
# console; a test builds a subclass that answers canned keys and records the
# lines instead of drawing them.
class WslConsole {
    # Is there a keyboard we can read without hanging? Both checks are cheap
    # and neither one blocks: KeyAvailable throws without a console, and a
    # throw is an answer. $Host is reached through Get-Variable: a method
    # cannot name it directly - the parser refuses it, measured.
    [bool] HasKeyboard() {
        if ([Console]::IsInputRedirected) { return $false }
        try {
            $null = (Get-Variable -Name Host -ValueOnly).UI.RawUI.KeyAvailable
            return $true
        } catch {
            return $false
        }
    }

    # The one line in the project that touches the keyboard.
    [ConsoleKey] ReadKey() {
        return [Console]::ReadKey($true).Key
    }

    # $null means the host would not say - not the same as "row zero". A
    # terminal that refuses to be drawn on leaves the menu working, only
    # uglier: the choice is the keys, never the paint.
    [object] Top() {
        try { return [Console]::CursorTop } catch { return $null }
    }

    # Says whether it moved: a silent failure here is what turned a menu into
    # a stack of copies once - every repaint landed where the cursor already
    # was.
    [bool] SetTop([int]$Top) {
        try {
            [Console]::SetCursorPosition(0, $Top)
            return ([Console]::CursorTop -eq $Top)
        } catch {
            return $false
        }
    }

    # Width and height, or zeroes when the host will not say - zero meaning
    # "no constraint", so a host that keeps quiet is never a reason to give up
    # on the arrows.
    [int[]] Size() {
        try {
            $Size = (Get-Variable -Name Host -ValueOnly).UI.RawUI.WindowSize
            return @([int]$Size.Width, [int]$Size.Height)
        } catch {
            return @(0, 0)
        }
    }

    # A clean screen, for going down a level or coming back up one. The first
    # version blanked exactly the rows each menu had drawn - row numbers are
    # absolute and the console moves, so one scroll made every remembered row
    # a row off. Clearing is one call and cannot drift.
    [void] Clear() {
        try { Clear-Host } catch { }
    }

    # One line, and its colour comes from the message palette - "" is the
    # plain line. Every line of every list goes through here; nothing else
    # writes.
    [void] Line([string]$Text, [string]$Kind) {
        if ($Kind) {
            Write-Host $Text -ForegroundColor (Get-MessageColour $Kind)
        } else {
            Write-Host $Text
        }
    }

    # One answer typed by the user, read from the console.
    [string] Prompt([string]$Prompt) {
        return [string](Read-Host $Prompt)
    }
}

# One list asked = one WslMenu: what is offered, where the choice starts and
# stands, what is ticked, the note under the block. Ask() walks the arrows;
# with no keyboard it falls back to the numbered prompt. The answer is a
# WslMenuItem (or the ticked ones), never a loose value - and $null, which
# every caller reads as "the user cancelled".
class WslMenu {
    [string]$Title
    [WslMenuItem[]]$Items
    [bool]$Multi
    [int]$Current = 0
    [string]$Note = ""
    [WslConsole]$Console
    [scriptblock]$KeyReader

    WslMenu([string]$Title, [WslMenuItem[]]$Items, [bool]$Multi) {
        $this.Title = $Title
        $this.Items = $Items
        $this.Multi = $Multi
        $this.Console = [WslConsole]::new()
    }

    # The answer, one way or the other. An empty list asks nothing.
    [object] Ask() {
        if ($this.Items.Count -eq 0) { return $null }
        if ($this.KeyReader -or $this.Console.HasKeyboard()) {
            return $this.AskWithArrows()
        }
        return $this.AskByNumber()
    }

    # One row, as it is drawn: the marker and the colours say where the choice
    # is, so a terminal that renders neither still reads correctly. The marker
    # keeps saying where the cursor is, the box what is checked - two
    # questions, two signs.
    static [string] FormatRow([int]$Index, [int]$Current, [string[]]$Labels, [bool[]]$Checked) {
        $Marker = if ($Index -eq $Current) { "  > " } else { "    " }
        if ($null -eq $Checked) { return ($Marker + $Labels[$Index]) }
        $Box = if ($Checked[$Index]) { "[x] " } else { "[ ] " }
        return ($Marker + $Box + $Labels[$Index])
    }

    # One row is one line, always: a wrapped row is a row whose neighbours are
    # no longer where the arithmetic says. The tail is cut rather than the
    # menu refused; a window that will not say how wide it is gets no cutting
    # at all. -Prefix says what goes in front of the label: 4 for the marker,
    # 8 for a checklist row, 0 for the title and the hint.
    static [string[]] Fit([string[]]$Labels, [int]$Width, [int]$Prefix) {
        if ($Width -le 0) { return $Labels }
        $Room = $Width - 1
        return @($Labels | ForEach-Object {
            $Max = $Room - $Prefix
            if ($_.Length -le $Max) { $_ }
            else { $_.Substring(0, [Math]::Max(1, $Max - 3)) + "..." }
        })
    }

    # The checked flags the row formatting reads - $null in a single-choice
    # list, where there is nothing to check.
    hidden [object] Flags() {
        if (-not $this.Multi) { return $null }
        return @($this.Items | ForEach-Object { $_.Checked })
    }

    # One row, now, in the right colour.
    hidden [void] DrawRow([int]$Index, [string[]]$Texts) {
        $Kind = if ($Index -eq $this.Current) { "info" } else { "" }
        $this.Console.Line([WslMenu]::FormatRow($Index, $this.Current, $Texts, $this.Flags()), $Kind)
    }

    # The rows are drawn once and repainted in place - every label keeps its
    # length, so nothing has to be erased, and no Clear-Host.
    hidden [object] AskWithArrows() {
        $Count = $this.Items.Count
        # An index that is not in the list is the first one: a default is a
        # favour, not a way to fail.
        if ($this.Current -lt 0 -or $this.Current -ge $Count) { $this.Current = 0 }

        $Texts = @($this.Items | ForEach-Object { $_.Text })
        $Hint = if ($this.Multi) { "  up/down to move, space to check, Enter to apply, Escape to cancel" }
                else { "  up/down to move, Enter to choose, Escape to cancel" }
        $Size = $this.Console.Size()
        # Every line of the block is cut to the window, title and hint
        # included: one line that wraps moves the rows below by one, and the
        # arithmetic below is written for exactly Visible + 3 lines, plus the
        # note when there is one. A line the arithmetic does not know about is
        # the bug this file was written against.
        $Extra = if ($this.Note) { 1 } else { 0 }
        $Shown = [WslMenu]::Fit($Texts, $Size[0], $(if ($this.Multi) { 8 } else { 4 }))
        $ShownTitle = @([WslMenu]::Fit(@($this.Title), $Size[0], 0))[0]
        $ShownHint = @([WslMenu]::Fit(@($Hint), $Size[0], 0))[0]
        $ShownNote = @([WslMenu]::Fit(@($this.Note), $Size[0], 0))[0]

        # A list taller than the window scrolls rather than refuse: only the
        # rows that fit are drawn, and the window follows the choice. Three
        # lines kept for the blank and the hint, one more for the note.
        $Visible = if ($Size[1] -gt 0) { [Math]::Min($Count, [Math]::Max(1, $Size[1] - 3 - $Extra)) } else { $Count }
        # The choice starts in the middle when it can: it is where the eye
        # goes.
        $First = [Math]::Max(0, [Math]::Min($this.Current - [int](($Visible - 1) / 2), $Count - $Visible))

        # The top row is READ BACK from the cursor after drawing, never
        # computed before: writing the block can scroll the console, and a
        # row number from before is wrong by what scrolled - that was the
        # bug: every arrow added one more copy of the list.
        $this.Console.Line("", "")
        if ($ShownTitle) { $this.Console.Line($ShownTitle, "info") }
        for ($Row = 0; $Row -lt $Visible; $Row++) { $this.DrawRow($First + $Row, $Shown) }
        $this.Console.Line($ShownHint, "muted")
        if ($ShownNote) { $this.Console.Line($ShownNote, "muted") }

        $Cursor = $this.Console.Top()
        $Top = if ($null -ne $Cursor) { $Cursor - ($Visible + 1 + $Extra) } else { 0 }
        # No cursor reading (a test, a host that will not say): the loop still
        # answers the keys, it simply does not repaint - there is nothing to
        # paint on.
        $CanPaint = ($null -ne $Cursor) -and ($Top -ge 0)

        while ($true) {
            $Key = if ($this.KeyReader) { & $this.KeyReader } else { $this.Console.ReadKey() }
            $Last = $Count - 1
            $Moved = $true

            if ($Key -eq [ConsoleKey]::UpArrow) {
                $this.Current = if ($this.Current -eq 0) { $Last } else { $this.Current - 1 }
            } elseif ($Key -eq [ConsoleKey]::DownArrow) {
                $this.Current = if ($this.Current -eq $Last) { 0 } else { $this.Current + 1 }
            } elseif ($Key -eq [ConsoleKey]::Spacebar -and $this.Multi) {
                # Space checks and unchecks where the cursor is. In a
                # single-choice list it means nothing, and nothing is what it
                # does.
                $this.Items[$this.Current].Checked = -not $this.Items[$this.Current].Checked
            } elseif ($Key -eq [ConsoleKey]::Enter) {
                if ($CanPaint) { $null = $this.Console.SetTop($Top + $Visible + 1 + $Extra) }
                if ($this.Multi) {
                    # No comma, unlike the function this came from: a method
                    # hands its value back whole, where a function's output is
                    # unrolled into the pipeline. The empty list arrives as
                    # itself - "I checked none" stays different from "I
                    # cancelled".
                    return @($this.Items | Where-Object { $_.Checked })
                }
                return $this.Items[$this.Current]
            } elseif ($Key -eq [ConsoleKey]::Escape) {
                if ($CanPaint) { $null = $this.Console.SetTop($Top + $Visible + 1 + $Extra) }
                return $null
            } elseif (($Key -ge [ConsoleKey]::D1 -and $Key -le [ConsoleKey]::D9) -or
                      ($Key -ge [ConsoleKey]::NumPad1 -and $Key -le [ConsoleKey]::NumPad9)) {
                $Wanted = if ($Key -ge [ConsoleKey]::NumPad1) { [int]$Key - [int][ConsoleKey]::NumPad1 }
                          else { [int]$Key - [int][ConsoleKey]::D1 }
                if ($Wanted -lt $Count) {
                    if ($this.Multi) {
                        $this.Items[$Wanted].Checked = -not $this.Items[$Wanted].Checked    # a digit checks, it does not leave
                    } else {
                        if ($CanPaint) { $null = $this.Console.SetTop($Top + $Visible + 1 + $Extra) }
                        return $this.Items[$Wanted]
                    }
                }
            } else {
                $Moved = $false                   # a key the menu has no use for
            }

            if (-not $Moved -or -not $CanPaint) { continue }

            # Bring the choice back into the window, then repaint where the
            # rows already are; if the cursor will not go back, the block is
            # written again - one more copy is ugly, a screen showing the
            # wrong current row is worse.
            if ($this.Current -lt $First) { $First = $this.Current }
            if ($this.Current -ge ($First + $Visible)) { $First = $this.Current - $Visible + 1 }

            $Placed = $true
            for ($Row = 0; $Row -lt $Visible; $Row++) {
                if (-not $this.Console.SetTop($Top + $Row)) { $Placed = $false; break }
                $this.DrawRow($First + $Row, $Shown)
            }
            if (-not $Placed) {
                for ($Row = 0; $Row -lt $Visible; $Row++) { $this.DrawRow($First + $Row, $Shown) }
            }
        }

        # Never reached: the loop only leaves by return. A typed method must
        # return on every path, and the parser cannot see that the loop never
        # falls through - this line is for it.
        return $null
    }

    # The prompt every command used before the arrows: numbered rows, a number
    # typed, an empty answer cancelling. Read-Host returns an empty string
    # when its input is closed, so a run with no console can never loop
    # forever.
    hidden [object] AskByNumber() {
        $Count = $this.Items.Count
        $Texts = @($this.Items | ForEach-Object { $_.Text })

        if ($this.Multi) {
            while ($true) {
                # The list is written again at every turn: a box that changed
                # has to be seen, and with no console to paint on there is
                # nowhere else to put it.
                $this.Console.Line("", "")
                if ($this.Title) { $this.Console.Line($this.Title, "info") }
                for ($Index = 0; $Index -lt $Count; $Index++) {
                    $Box = if ($this.Items[$Index].Checked) { "[x]" } else { "[ ]" }
                    $this.Console.Line(("  {0,2}.  {1} {2}" -f ($Index + 1), $Box, $Texts[$Index]), "")
                }
                $this.Console.Line("   0.  Cancel", "")
                if ($this.Note) { $this.Console.Line("  $($this.Note)", "muted") }

                $Answer = $this.Console.Prompt("Number toggles, v applies, 0 cancels")
                if ([string]::IsNullOrWhiteSpace($Answer) -or $Answer.Trim() -eq "0") { return $null }
                if ($Answer.Trim() -match "^[vV]$") {
                    return @($this.Items | Where-Object { $_.Checked })
                }
                $Number = 0
                if ([int]::TryParse($Answer.Trim(), [ref]$Number) -and
                    $Number -ge 1 -and $Number -le $Count) {
                    $this.Items[$Number - 1].Checked = -not $this.Items[$Number - 1].Checked
                    continue
                }
                $this.Console.Line("  '$Answer' is not one of the numbers above.", "warning")
            }
        }

        $this.Console.Line("", "")
        if ($this.Title) { $this.Console.Line($this.Title, "info") }
        for ($Index = 0; $Index -lt $Count; $Index++) {
            $this.Console.Line(("  {0,2}.  {1}" -f ($Index + 1), $Texts[$Index]), "")
        }
        $this.Console.Line("   0.  Cancel", "")
        if ($this.Note) { $this.Console.Line("  $($this.Note)", "muted") }

        while ($true) {
            $Answer = $this.Console.Prompt("Which one? (0 to cancel)")
            if ([string]::IsNullOrWhiteSpace($Answer)) { return $null }
            $Number = 0
            if ([int]::TryParse($Answer.Trim(), [ref]$Number)) {
                if ($Number -eq 0) { return $null }
                if ($Number -ge 1 -and $Number -le $Count) { return $this.Items[$Number - 1] }
            }
            $this.Console.Line("  '$Answer' is not one of the numbers above.", "warning")
        }

        # Never reached, like the one in AskWithArrows: for the parser, not
        # for the console.
        return $null
    }
}

# ---------------------------------------------------------------------------
# THE DOORS - WHAT THE SCRIPTS CALL, OVER THE CLASSES
# ---------------------------------------------------------------------------
# The same list, for the commands as they are written: Select-FromList builds
# a WslMenu from raw items and a label; Select-Distro composes the one list
# this family shows most. Thin on purpose - the day another interface replaces
# the console, the doors go and the classes stay.

# ---------------------------------------------------------------------------
# THE SMALL HELPERS THE COMMANDS ALREADY CALLED
# ---------------------------------------------------------------------------
# The commands ask these by name (theme.ps1 and the three children, icon, font
# and color) - kept here, where they always lived, and spelled as functions
# because that is how their callers know them. What a terminal can show, and
# how it spells a colour: the console class above answers the same questions
# for the menus. Test-KeyInput is that class's HasKeyboard twin - a method
# cannot name $Host, measured, so the class reads it through Get-Variable and
# this reads it directly.

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

function Select-FromList {
    param(
        [string]$Title = "",
        [object[]]$Items = @(),
        [scriptblock]$Label = { param($Item) [string]$Item },
        [scriptblock]$KeyReader,
        [int]$DefaultIndex = 0,
        [switch]$Multi,
        [int[]]$CheckedIndexes = @(),
        [string]$Note = ""
    )

    $Items = @($Items)
    if ($Items.Count -eq 0) { return $null }

    $Rows = @()
    foreach ($Item in $Items) {
        $Rows += [WslMenuItem]::new([string](& $Label $Item), $Item)
    }
    if ($Multi) {
        foreach ($Index in $CheckedIndexes) {
            if ($Index -ge 0 -and $Index -lt $Rows.Count) { $Rows[$Index].Checked = $true }
        }
    }

    $Menu = [WslMenu]::new($Title, $Rows, [bool]$Multi)
    $Menu.Note = $Note
    $Menu.KeyReader = $KeyReader
    # An index that is not in the list is the first one: the menu's own rule.
    if ($DefaultIndex -ge 0 -and $DefaultIndex -lt $Rows.Count) { $Menu.Current = $DefaultIndex }
    $Picked = $Menu.Ask()

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

    $Rows = @()
    foreach ($Instance in $All) {
        $State = if ($Instance.State -eq [WslState]::Running) { "running" } else { "stopped" }
        $Rows += [WslMenuItem]::new(("{0,-30} {1,-8} {2,10}" -f $Instance.Name, $State, (Format-Size (Get-VhdxSize $Instance.Path))), $Instance)
    }
    $Picked = [WslMenu]::new("Our Instances", $Rows, $false).Ask()

    if ($null -eq $Picked) {
        if ($AllowCancel) { return $null }
        Write-Host ""
        Write-Host "[ABORT] Operation cancelled by user. Nothing was modified." -ForegroundColor (Get-MessageColour success)
        exit 0
    }
    return $Picked.Value
}
