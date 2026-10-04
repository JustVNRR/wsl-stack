# ==============================================================================
# THE WAY IN AS OBJECTS: THE COMMANDS, THE TERMINAL, AND THE DISPATCH
# ==============================================================================
# The trio wsl.ps1 asks its command list with:
#
#   WslCommand    - one command: the word that names it, the line that says
#                   what it does, and the gesture that runs it.
#   WslTerminal   - the terminal: keyboard, cursor, window, and the one
#                   line-writer everything goes through.
#   WslDispatcher - the list itself: the commands, the ask (the arrows, or the
#                   numbered prompt when the machine has no keyboard), and the
#                   route by name for the command line.
#
# The names are temporary, like the copy they live beside: menu.ps1 defines
# WslMenuItem, WslConsole and WslMenu for the questions, and two classes of one
# name cannot coexist - the last one read wins, in silence, measured. The
# painting below is that menu's of today, recopied word for word and colour
# for colour; as the questions come over here, step by step, the old classes
# leave, one copy remains, and the names are decided again.
#
# Both ways in hand the WslCommand back instead of running it: the engine is
# made by the caller only once a command really is about to run, exactly as
# before, and the gesture - WslCommand.Execute() - is what runs it, with the
# command and the caller's context travelling in its parameters.
# ==============================================================================

# Loaded here too: suites drive this file on its own, and lines are drawn by
# asking the message palette for the colour.
. (Join-Path $PSScriptRoot "message.ps1")

# One command of the list: the word that names it, the line shown beside it,
# and the gesture - a scriptblock, so the command scripts stay outside this
# file.
class WslCommand {
    [string]$Key
    [string]$Description
    [scriptblock]$Action

    WslCommand([string]$Key, [string]$Description, [scriptblock]$Action) {
        $this.Key         = $Key
        $this.Description = $Description
        $this.Action      = $Action
    }

    # The gesture, run wherever the command was picked - the menu or the
    # command line. The command hands ITSELF and the caller's context to the
    # gesture, both as parameters: a gesture reads nothing from a scope at
    # call time - measured: a closure that read its variables by name came up
    # empty on a machine where the same code ran on another. A class method
    # hands back only its return value and lets Write-Host through; the
    # commands print through Write-Host, so none of their lines is lost here.
    [void] Execute([object]$Context) {
        & $this.Action $this $Context
    }
}

# The terminal, as the dispatcher's only collaborator. The real one touches
# the real console; a test builds a subclass that answers canned keys and
# records the lines instead of drawing them.
class WslTerminal {
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

    # One line, and its colour comes from the message palette - "" is the
    # plain line. Every line of the list goes through here; nothing else
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

# One list of commands = one WslDispatcher: the title, the rows, and the two
# ways in. Prompt() asks - the arrows with a keyboard, the numbered prompt
# without; Dispatch() routes a word from the command line. Both hand the
# WslCommand back, or $null, which every caller reads as "there is nothing to
# run"; running it is WslCommand.Execute(), left to the caller.
class WslDispatcher {
    [string]$Title
    [WslTerminal]$Terminal
    [System.Collections.Generic.List[WslCommand]]$Items
    hidden [int]$Current = 0

    # The terminal is built here, not handed in: a class constructor takes no
    # default value - [WslDispatcher]::new("T") would find no overload with
    # one argument, measured - and the tests replace the object right after,
    # as they always did.
    WslDispatcher([string]$Title) {
        $this.Title    = $Title
        $this.Terminal = [WslTerminal]::new()
        $this.Items    = [System.Collections.Generic.List[WslCommand]]::new()
    }

    # The list is built by the file that owns the commands - wsl.ps1 - one row
    # per command. The fluent return keeps the construction one statement.
    [WslDispatcher] Add([string]$Key, [string]$Description, [scriptblock]$Action) {
        $this.Items.Add([WslCommand]::new($Key, $Description, $Action))
        return $this
    }

    # The command a typed word names, or $null. The word's case does not
    # matter; the caller says which word found nothing.
    [WslCommand] Dispatch([string]$Key) {
        $Wanted = "$Key".ToLower()
        foreach ($Command in $this.Items) {
            if ($Command.Key -eq $Wanted) { return $Command }
        }
        return $null
    }

    # The ask. An empty list asks nothing.
    [WslCommand] Prompt() {
        if ($this.Items.Count -eq 0) { return $null }
        if ($this.Terminal.HasKeyboard()) {
            return $this.PromptArrows()
        }
        return $this.PromptNumbers()
    }

    # One row, as it is drawn: the word, and the line beside it, in the columns
    # the documentation shows. The marker says where the choice is, so a
    # terminal that renders no colour still reads correctly.
    static [string] FormatRow([int]$Index, [int]$Current, [string[]]$Labels) {
        $Marker = if ($Index -eq $Current) { "  > " } else { "    " }
        return ($Marker + $Labels[$Index])
    }

    # One row is one line, always: a wrapped row is a row whose neighbours are
    # no longer where the arithmetic says. The tail is cut rather than the
    # list refused; a window that will not say how wide it is gets no cutting
    # at all. -Prefix says what goes in front of the label: 4 for the marker,
    # 0 for the title and the hint.
    static [string[]] Fit([string[]]$Labels, [int]$Width, [int]$Prefix) {
        if ($Width -le 0) { return $Labels }
        $Room = $Width - 1
        return @($Labels | ForEach-Object {
            $Max = $Room - $Prefix
            if ($_.Length -le $Max) { $_ }
            else { $_.Substring(0, [Math]::Max(1, $Max - 3)) + "..." }
        })
    }

    # The words of the rows, as the documentation spells them: the name in a
    # twelve-wide column, then the description.
    hidden [string[]] Labels() {
        return @($this.Items | ForEach-Object { "{0,-12} {1}" -f $_.Key, $_.Description })
    }

    # One row, now, in the right colour.
    hidden [void] DrawRow([int]$Index, [string[]]$Texts) {
        $Kind = if ($Index -eq $this.Current) { "info" } else { "" }
        $this.Terminal.Line([WslDispatcher]::FormatRow($Index, $this.Current, $Texts), $Kind)
    }

    # The rows are drawn once and repainted in place - every label keeps its
    # length, so nothing has to be erased, and no Clear-Host.
    hidden [WslCommand] PromptArrows() {
        $Count = $this.Items.Count
        # An index that is not in the list is the first one: a default is a
        # favour, not a way to fail.
        if ($this.Current -lt 0 -or $this.Current -ge $Count) { $this.Current = 0 }

        $Texts = $this.Labels()
        $Hint = "  up/down to move, Enter to choose, Escape to cancel"
        $Size = $this.Terminal.Size()
        # Every line of the block is cut to the window, title and hint
        # included: one line that wraps moves the rows below by one, and the
        # arithmetic below is written for exactly Visible + 3 lines. A line
        # the arithmetic does not know about is the bug this file was written
        # against.
        $Shown = [WslDispatcher]::Fit($Texts, $Size[0], 4)
        $ShownTitle = @([WslDispatcher]::Fit(@($this.Title), $Size[0], 0))[0]
        $ShownHint = @([WslDispatcher]::Fit(@($Hint), $Size[0], 0))[0]

        # A list taller than the window scrolls rather than refuse: only the
        # rows that fit are drawn, and the window follows the choice. Three
        # lines kept for the blank and the hint.
        $Visible = if ($Size[1] -gt 0) { [Math]::Min($Count, [Math]::Max(1, $Size[1] - 3)) } else { $Count }
        # The choice starts in the middle when it can: it is where the eye
        # goes.
        $First = [Math]::Max(0, [Math]::Min($this.Current - [int](($Visible - 1) / 2), $Count - $Visible))

        # The top row is READ BACK from the cursor after drawing, never
        # computed before: writing the block can scroll the console, and a
        # row number from before is wrong by what scrolled - that was the
        # bug: every arrow added one more copy of the list.
        $this.Terminal.Line("", "")
        if ($ShownTitle) { $this.Terminal.Line($ShownTitle, "info") }
        for ($Row = 0; $Row -lt $Visible; $Row++) { $this.DrawRow($First + $Row, $Shown) }
        $this.Terminal.Line($ShownHint, "muted")

        $Cursor = $this.Terminal.Top()
        $Top = if ($null -ne $Cursor) { $Cursor - ($Visible + 1) } else { 0 }
        # No cursor reading (a test, a host that will not say): the loop still
        # answers the keys, it simply does not repaint - there is nothing to
        # paint on.
        $CanPaint = ($null -ne $Cursor) -and ($Top -ge 0)

        while ($true) {
            $Key = $this.Terminal.ReadKey()
            $Last = $Count - 1
            $Moved = $true

            if ($Key -eq [ConsoleKey]::UpArrow) {
                $this.Current = if ($this.Current -eq 0) { $Last } else { $this.Current - 1 }
            } elseif ($Key -eq [ConsoleKey]::DownArrow) {
                $this.Current = if ($this.Current -eq $Last) { 0 } else { $this.Current + 1 }
            } elseif ($Key -eq [ConsoleKey]::Enter) {
                if ($CanPaint) { $null = $this.Terminal.SetTop($Top + $Visible + 1) }
                return $this.Items[$this.Current]
            } elseif ($Key -eq [ConsoleKey]::Escape) {
                if ($CanPaint) { $null = $this.Terminal.SetTop($Top + $Visible + 1) }
                return $null
            } elseif (($Key -ge [ConsoleKey]::D1 -and $Key -le [ConsoleKey]::D9) -or
                      ($Key -ge [ConsoleKey]::NumPad1 -and $Key -le [ConsoleKey]::NumPad9)) {
                # A digit picks its row, no Enter needed - the numbers the
                # numbered prompt shows are the same rows.
                $Wanted = if ($Key -ge [ConsoleKey]::NumPad1) { [int]$Key - [int][ConsoleKey]::NumPad1 }
                          else { [int]$Key - [int][ConsoleKey]::D1 }
                if ($Wanted -lt $Count) {
                    if ($CanPaint) { $null = $this.Terminal.SetTop($Top + $Visible + 1) }
                    return $this.Items[$Wanted]
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
                if (-not $this.Terminal.SetTop($Top + $Row)) { $Placed = $false; break }
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

    # The prompt for a machine with no keyboard: numbered rows, a number
    # typed, an empty answer cancelling. Read-Host returns an empty string
    # when its input is closed, so a run with no console can never loop
    # forever.
    hidden [WslCommand] PromptNumbers() {
        $Count = $this.Items.Count
        $Texts = $this.Labels()

        $this.Terminal.Line("", "")
        if ($this.Title) { $this.Terminal.Line($this.Title, "info") }
        for ($Index = 0; $Index -lt $Count; $Index++) {
            $this.Terminal.Line(("  {0,2}.  {1}" -f ($Index + 1), $Texts[$Index]), "")
        }
        $this.Terminal.Line("   0.  Cancel", "")

        while ($true) {
            $Answer = $this.Terminal.Prompt("Which one? (0 to cancel)")
            if ([string]::IsNullOrWhiteSpace($Answer)) { return $null }
            $Number = 0
            if ([int]::TryParse($Answer.Trim(), [ref]$Number)) {
                if ($Number -eq 0) { return $null }
                if ($Number -ge 1 -and $Number -le $Count) { return $this.Items[$Number - 1] }
            }
            $this.Terminal.Line("  '$Answer' is not one of the numbers above.", "warning")
        }

        # Never reached, like the one in PromptArrows: for the parser, not for
        # the console.
        return $null
    }
}
