# Draws icons the way the build draws them, and reads back what was drawn.
#
#   - the letters: what a name turns into (wagon -> WA, my-project -> MP), and
#     that a piece opening on a digit is not a word (Ubuntu-22.04 -> UB),
#   - the colours: a name always draws the same file. A hash seeded per process
#     answers the same twice inside one process and differently in the next -
#     the icon would change colour at every build - so every drawing here is a
#     PowerShell process of its own, and two of them have their bytes compared.
#
# It needs no instance, no console and no Docker.
#
# Usage:  pwsh -NoProfile -File tests\icon-test.ps1

$ErrorActionPreference = "Stop"

$IconScript = Join-Path $PSScriptRoot "..\src\windows\make-icon.ps1"
# Child processes follow the engine this suite runs under, so a pass under 7
# tests the scripts under 7.
$Engine = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
# The script writes terminal-icon.png into the current folder when -Out is not
# given: every drawing below names its file, and the check at the end says so.
# A suite that drops an image in the checkout is a suite that gets committed.
$StrayAtStart = Test-Path (Join-Path (Get-Location) "terminal-icon.png")
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("icon-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

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

# One drawing, in a process of its own. Returns what it printed, or $null when
# it failed: a drawing that cannot be made must say so, not write an empty file.
# Write-Host, or Write-Output would travel back with the return value - a
# captured result swallows what it captured.
function Invoke-Icon {
    param([string[]]$Arguments)

    # The child's error output is read, not thrown: a failed drawing owes us
    # its message and exit code, and at "Stop" the redirection below turns one
    # line of stderr into a terminating error that would end the suite instead
    # of failing one check.
    $Preference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Lines = & $Engine -NoProfile -File $IconScript @Arguments 2>&1
        $Code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $Preference
    }

    if ($Code -ne 0) {
        # Its first line only - the rest of a PowerShell error block repeats it
        # in the language of whoever's Windows answers.
        Write-Host ("      (the drawing failed: " + @($Lines)[0] + ")")
        return $null
    }
    return $Lines
}

# What the script said it drew: its line reads "monogram 'WA', #CF7040 -> #B95E30"
function Get-DrawnLine {
    param([string[]]$Arguments)

    $Lines = Invoke-Icon $Arguments
    return @($Lines | Where-Object { "$_" -match "monogram '" })[0]
}

function Get-DrawnLetters {
    param([string[]]$Arguments)

    $Line = Get-DrawnLine $Arguments
    if ($Line -match "monogram '([^']*)'") { return $Matches[1] }
    return "<nothing drawn>"
}

$Letters = @(
    @{ Name = "wagon";        Expect = "WA" },
    @{ Name = "distro";       Expect = "DI" },
    @{ Name = "ml";           Expect = "ML" },
    @{ Name = "my-project";   Expect = "MP" },
    @{ Name = "new_distro2";  Expect = "ND" },
    @{ Name = "Ubuntu-22.04"; Expect = "UB" },
    @{ Name = "2fast";        Expect = "2F" },
    @{ Name = "x";            Expect = "X" }
)

foreach ($Case in $Letters) {
    $Out = Join-Path $Tmp ("letters-" + $Case.Name + ".png")
    $Got = Get-DrawnLetters @("-Name", $Case.Name, "-Out", $Out)
    Check ("letters of '" + $Case.Name + "'") $Got $Case.Expect
}

# The colours: one name, two processes, the same file.
$First = Join-Path $Tmp "same-name-1.png"
$Second = Join-Path $Tmp "same-name-2.png"
$null = Invoke-Icon @("-Name", "wagon", "-Out", $First, "-Quiet")
$null = Invoke-Icon @("-Name", "wagon", "-Out", $Second, "-Quiet")
Check "the same name draws the same file, in two processes" `
    (Get-FileHash $First).Hash (Get-FileHash $Second).Hash

# And the colours come from the name, not from the letters: the same monogram
# typed by hand - same letters as 'wagon' - is drawn on the table's first row.
$ByHand = Join-Path $Tmp "by-hand.png"
$null = Invoke-Icon @("-Text", "WA", "-Out", $ByHand, "-Quiet")
Check "the same letters, another name, another colour" `
    ((Get-FileHash $First).Hash -ne (Get-FileHash $ByHand).Hash) $true

Check "a monogram given by hand is drawn as asked" `
    (Get-DrawnLetters @("-Text", "ML", "-Out", (Join-Path $Tmp "by-hand-ml.png"))) "ML"

# The table the colours are chosen from, read the way `icon` reads it: one row
# per line, tab-separated, the name first.
$Pairs = @(Invoke-Icon @("-ListPairs"))
Check "the table has eight pairs" $Pairs.Count 8
Check "every row is a name and three colours" (@($Pairs | Where-Object { ($_ -split "`t").Count -ne 4 }).Count) 0
Check "the first pair is the orange of this repository" ($Pairs[0] -split "`t")[0] "orange"

# A colour given by hand wins over the name's own - what `icon` relies on when
# a pair is picked from that table - and the letters stay the name's.
$Line = Get-DrawnLine @("-Name", "wagon", "-Top", "#000000", "-Bottom", "#111111", "-TextColor", "#FFFFFF",
                        "-Out", (Join-Path $Tmp "colours-by-hand.png"))
Check "a colour given by hand is used as given" ("$Line".Contains("#000000 -> #111111")) $true
Check "and the letters still come from the name" `
    (Get-DrawnLetters @("-Name", "wagon", "-Out", (Join-Path $Tmp "name-only.png"))) "WA"

# The call `icon` makes: the drawing script in the same process, told what to
# draw through a table of parameters held in a variable. Both halves were
# learned the day the command was first run: a LIST is handed over in order, not
# by name - "-Text" lands where a colour belongs - and an inline @{...} is not a
# splat at all, just one value handed over as the first argument (it drew
# System.Collections.Hashtable, which reads 'SC' and comes out teal).
#
# So the shape of the call is checked, not only that it runs: the file has to
# be the same one a child process draws when asked the same thing.
$InProcess = Join-Path $Tmp "in-process.png"
$ViaChild = Join-Path $Tmp "via-child.png"
$Draw = @{ Name = "wagon"; Text = "ABC" }
$Drawn = $true
try {
    & $IconScript @Draw -Out $InProcess -Quiet
} catch {
    $Drawn = $false
    Write-Host ("      (in this process: " + $_.Exception.Message + ")")
}
$null = Invoke-Icon @("-Name", "wagon", "-Text", "ABC", "-Out", $ViaChild, "-Quiet")
Check "in this process, told by name" $Drawn $true
Check "and the same file as the same call made by a child" (Get-FileHash $InProcess).Hash (Get-FileHash $ViaChild).Hash

# -What says what was drawn on the output stream: one line of JSON, the letters
# and the three colours, for a caller that has to note them somewhere. The file
# they go in belongs to the caller, and nothing is dropped beside the picture.
$Noted = Join-Path $Tmp "noted.png"
$Told = @(Invoke-Icon @("-Name", "wagon", "-Text", "ABC", "-Top", "#3B82F6", "-Bottom", "#2563EB", "-Out", $Noted, "-What"))
$Said = $Told[-1] | ConvertFrom-Json
Check "what was drawn is said, in one line" $Told.Count 1
Check "with the letters that were drawn" $Said.Text "ABC"
Check "and the colours that were drawn" "$($Said.Top) $($Said.Bottom) $($Said.TextColor)" "#3B82F6 #2563EB #FFFFFF"
Check "and nothing is written beside the picture" (Test-Path ([System.IO.Path]::ChangeExtension($Noted, ".json"))) $false

# Nothing to draw is refused, and leaves no file behind.
$Nothing = Join-Path $Tmp "nothing.png"
Check "neither -Name nor -Text: refused" ($null -eq (Invoke-Icon @("-Out", $Nothing))) $true
Check "and no file was written" (Test-Path $Nothing) $false

# What comes out is a picture: the PNG signature, and bytes behind it.
$Bytes = [System.IO.File]::ReadAllBytes($First)
Check "the icon is a PNG" (($Bytes[0..7] | ForEach-Object { $_.ToString("X2") }) -join "") "89504E470D0A1A0A"
Check "and it has pixels in it" ($Bytes.Length -gt 1000) $true

# See the top of this file: no drawing may land in the folder the suite runs from.
Check "nothing was drawn into the working folder" (Test-Path (Join-Path (Get-Location) "terminal-icon.png")) $StrayAtStart

Remove-Item -Recurse -Force $Tmp

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
