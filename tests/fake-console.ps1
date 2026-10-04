# The console the tests give the menu: canned keys, a canned window, a cursor
# that mimics a scrolling console, and every line recorded instead of drawn.
# It is a subclass of the real one - the tests replace the OBJECT now, not
# functions by name.
class FakeConsole : WslConsole {
    [System.Collections.Queue]$Keys
    [System.Collections.Queue]$Answers
    [int[]]$SizeAnswer = @(40, 20)
    [bool]$Drawing = $false
    [string[]]$Lines = @()
    [int[]]$Moves = @()

    [bool] HasKeyboard() { return $true }
    [ConsoleKey] ReadKey() { return $this.Keys.Dequeue() }

    # 20 before anything is drawn, 40 after - a console that scrolled under
    # the block, which is what the read-back after drawing is there for.
    [object] Top() { if ($this.Drawing) { return 40 } return 20 }

    [bool] SetTop([int]$Top) { $this.Moves += $Top; return $true }
    [int[]] Size() { return $this.SizeAnswer }

    [void] Line([string]$Text, [string]$Kind) {
        $this.Lines += $Text
        $this.Drawing = $true
    }

    [string] Prompt([string]$Prompt) { return $this.Answers.Dequeue() }
}
