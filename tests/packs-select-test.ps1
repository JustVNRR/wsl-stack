# Drives the ask/apply pair - the checklist in scripts\prompts.ps1, the
# applying in scripts\packs.ps1 - with no instance and no terminal.
#
#   Select-Packs   is answered on standard input: with no console the numbered
#                  prompt is what runs, and it reads its answers from there.
#   Invoke-PackApply  has every move intercepted. The stand-in for
#                  Invoke-InInstance is the one place where a pack touches the
#                  instance - copy its folder in, run one of its scripts, take
#                  the folder out, travel the cleanup - so recording the calls
#                  there records the ORDER, which is the whole design: the
#                  newcomer's folder is placed BEFORE a remove.sh asks its
#                  question, so a shared package is left where it is.
#                  Get-InstanceHome is stubbed below: the root-side scripts
#                  ask it directly, and it would otherwise reach the machine.
#
# Run it with tests\packs-select-test.answers on standard input: the answers,
# one per line, in the order they are read - and in these exact counts, because
# each scenario consumes its own:
#   1, v, (empty)   one box ticked -> it and its requirement, requirement first
#   3, v, (empty)   the installed box unticked -> one removal
#   0               cancelled
#   v               nothing checked, nothing installed: ONE answer, because
#                   there is no list to confirm - which is the point of it
#   1, v, n         the confirmation answered no
#   v, (empty)      pre-checked, nothing installed
#   v               a pack installed here that this checkout does not carry:
#                   ONE answer, for the same reason as above
#   2, v, (empty)   a requirement already installed -> only the ticked one travels
#   2, v, (empty)   the claimant unticked -> it and the invisible one leave
#   2, v, (empty)   a second claimant installed -> only the ticked one leaves
#   v               an invisible pack among the pre-checked ones: ONE answer,
#                   because it has no box and nothing else was ticked
#
#   powershell -File tests\packs-select-test.ps1 < tests\packs-select-test.answers
#
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\scripts\instance.ps1")
. (Join-Path $PSScriptRoot "..\scripts\prompts.ps1")

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

# The catalog, built from a packs folder of this test's own: five folders and
# their declarations - gcp requires devops, python requires devops AND
# scaffold - the two invisible ones, in no list, travelling with what requires
# them. Their rows are absent from the checklist, which every numbered answer
# below counts on: were one offered, the numbering would shift and every
# scenario would answer about the wrong pack.
#
# Two of them, because a run can hold one and let the other go - and because
# the requirements of one pack arrive in the order that pack names them. The
# folder names sort the list, so the boxes are gcp, python, then vision.
$PacksRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("packs-select-test-" + [Guid]::NewGuid().ToString("N"))
$Declarations = @(
    @{ Name = "gcp";      Description = "Google Cloud CLI";    Requires = "devops" },
    @{ Name = "vision";   Description = "Image and OCR tools" },
    @{ Name = "python";   Description = "Python toolchain";    Requires = "devops scaffold" },
    @{ Name = "devops";   Description = "Project targets";     Visible = "no" },
    @{ Name = "scaffold"; Description = "Project scaffolding"; Visible = "no" }
)
foreach ($Declaration in $Declarations) {
    $Folder = Join-Path $PacksRoot $Declaration.Name
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $Conf = @("PACK_DESCRIPTION := $($Declaration.Description)")
    if ($Declaration.Requires) { $Conf += "PACK_REQUIRES := $($Declaration.Requires)" }
    if ($Declaration.Visible) { $Conf += "PACK_VISIBLE := $($Declaration.Visible)" }
    Set-Content -Path (Join-Path $Folder "pack.conf") -Value $Conf
}
$Catalog = Get-PackCatalog -Root $PacksRoot

Write-Output "--- Select-Packs: what the checklist means ---"

# 1. An installed pack arrives checked; ticking one more box adds it - with what
#    it requires, and before it: gcp requires devops, and a pack is installed on
#    top of what it needs.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("vision")
Check "one box ticked -> its requirement comes first, then it" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) "devops,gcp / "

# 2. Unticking what is installed, with nothing else ticked, is a removal - and
#    ONLY a removal. (The additions once came off the available packs instead of
#    the ticked ones, so a run installed the pack nobody had asked for.)
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("vision")
Check "unticking -> the pack leaves, the rest is NOT added" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) " / vision"

# 3. Cancel is cancel.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("vision")
Check "cancelled -> nothing at all" ($null -eq $Selection) "True"

# 4. Nothing checked and nothing installed is an ANSWER, not a cancellation: the
#    two lists come back empty and the caller decides what that means. (.Count
#    answers 0 for $null too, so the $null test is the sharp one; the second
#    check is what proves the list itself came back.)
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @()
Check "empty checklist is not a cancellation" ($null -eq $Selection) "False"
Check "  ... and both lists are empty" `
    ("$($Selection.ToAdd.Count)$($Selection.ToRemove.Count)") "00"

# 5. "n" at the one confirmation is a cancellation too.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("vision")
Check "answered n -> nothing at all" ($null -eq $Selection) "True"

# 6. Two different facts. What the instance HAS is not what arrives ticked: at
#    build time the new instance has no pack yet (nothing can be removed), while
#    the ticked boxes are the ones its predecessor carried.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @() -Checked @("vision")
Check "pre-checked is not installed" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) "vision / "

# 7. A pack installed in the instance that THIS checkout does not carry is not
#    in the checklist, so nobody can have unchecked it - it must be left alone.
#    (The first version read "installed and not ticked" and removed it without
#    ever showing it.)
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("vision", "foreign")
Check "a pack this checkout does not carry is left alone" ($Selection.ToRemove -join ",") ""
Check "  ... and the answer is still an answer, not a cancellation" ($null -eq $Selection) "False"

Write-Output ""
Write-Output "--- Select-Packs: the packs nobody picks ---"

# 8. What the instance already carries is not installed a second time. devops is
#    there, python is ticked, and the requirement already in place is not copied
#    over itself - its install.sh does not run again. What is missing still
#    arrives, and before the pack that requires it: scaffold, then python, in the
#    order python's own declaration names them.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("devops")
Check "a requirement already installed is not installed again" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) "scaffold,python / "

# 9. An invisible pack has no row, so nobody can untick it - it leaves when the
#    last pack that requires it does, and in the same answer. python is the only
#    claimant of the two it requires, so both follow it out.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("python", "devops", "scaffold")
Check "the last claimant leaves -> the invisible ones go too" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) " / python,devops,scaffold"

# 10. ... and one stays while an installed pack still requires it. That is the
#     whole reason they are not offered: another claimant is there to hold it.
#     gcp requires devops, and nothing requires scaffold: the same run holds one
#     and lets the other go, which is what a single invisible pack cannot show.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @("python", "gcp", "devops", "scaffold")
Check "another claimant holds it -> it stays, and the other one goes" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) " / python,scaffold"

# 11. What an instance carried is not what the checklist shows: a predecessor
#     that had an invisible pack must not bring it back through a tick nobody
#     can see. It arrives with the pack that requires it, or not at all.
$Selection = Select-Packs -Title "T" -Catalog $Catalog -Installed @() -Checked @("devops")
Check "a checked invisible pack installs nothing" ($null -eq $Selection) "False"
Check "  ... and both lists are empty" ("$($Selection.ToAdd.Count)$($Selection.ToRemove.Count)") "00"

Write-Output ""
Write-Output "--- Invoke-PackApply: the order, and where a failure stops ---"

# The stand-in speaks on purpose: a returned value must not carry the output of
# what was run to produce it - a pack's install once went silent into the
# variable holding the answer. Every check that reads a returned value is
# therefore also a check on where the output went.
$script:Calls = @()
$script:FailCommand = ""
$script:FailCode = 1
$script:FailAfter = 1
$script:FailSeen = 0
function Invoke-InInstance {
    param([string]$DistroName, [string[]]$Command, [string]$WorkingDirectory, [ref]$ExitCode, [switch]$Quiet)
    $Line = ($Command -join " ")
    $Where = if ($WorkingDirectory) { $WorkingDirectory } else { "~" }
    $script:Calls += "$Where :: $Line"
    if (-not $Quiet) { Write-Output "INSTANCE-SAYS: $Line" }
    if ($script:FailCommand -and $Line -like "$($script:FailCommand)*") {
        $script:FailSeen++
        if ($script:FailSeen -ge $script:FailAfter) { $ExitCode.Value = $script:FailCode } else { $ExitCode.Value = 0 }
    } else { $ExitCode.Value = 0 }
}
# What the forced failure answers: 1 for a broken install, 2 for a pack that
# asked and was told no - the first takes the pack back out as a failure, the
# second as an answer, and the stand-in has to be able to say both. FailAfter:
# the first (N-1) matching calls pass, so a pack before the failing one is
# placed cleanly first.
function Reset { $script:Calls = @(); $script:FailCommand = ""; $script:FailCode = 1; $script:FailAfter = 1; $script:FailSeen = 0 }
function Commands { return @($script:Calls | ForEach-Object { ($_ -split " :: ", 2)[1] }) }

# The root-side moves ask the instance for the user's home through wsl.exe
# directly - outside the stand-in - and Enable-PackSudo reads the user name out
# of it. Answered here: the machine running this suite has no such instance to
# ask, and an unanswered call arrived as wsl's own error text.
function Get-InstanceHome { param([string]$DistroName) return "/home/u" }

$Add = @([PSCustomObject]@{ Name = "fake-a"; Path = "X:\packs\fake-a"; Description = "d" })
$Directory = "/home/u/.config/packs"

Reset
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add -ToRemove @("fake-b")
Check "the newcomer is placed BEFORE the removal asks its question" `
    ($script:Calls.IndexOf("~ :: mkdir -p $Directory/fake-a") -lt
     $script:Calls.IndexOf("~ :: test -f $Directory/fake-b/remove.sh")) "True"
Check "the install comes after the removal" `
    ($script:Calls.IndexOf("$Directory/fake-a :: bash install.sh") -gt
     $script:Calls.IndexOf("~ :: rm -rf $Directory/fake-b")) "True"
Check "and the dependencies are taken back last" `
    ((@($script:Calls[-4..-1] | ForEach-Object { ($_ -split " :: ", 2)[1] }) -join " | ")) `
    "cp cleanup_orphans.sh /tmp/cleanup_orphans.sh | env HOME=/home/u bash cleanup_orphans.sh | rm -f /tmp/cleanup_orphans.sh | rm -f /etc/sudoers.d/90-wsl-stack-packs"
Check "nothing failed" ($null -eq $Result) "True"
Check "  ... and the instance's own words are not in the answer" ("$Result".Contains("INSTANCE-SAYS")) "False"

# The door the installs run behind: one rule, written through visudo's own
# check, opened before them and removed after - and the rule names the user
# the stub's home gives. The line carries a newline: printf writes whole lines.
$DoorOpen = "bash -c printf '%s`n' 'u ALL=(ALL) NOPASSWD: ALL' > /tmp/wsl-stack-pack-sudo" +
    " && chmod 0440 /tmp/wsl-stack-pack-sudo" +
    " && visudo -cf /tmp/wsl-stack-pack-sudo > /dev/null" +
    " && mv /tmp/wsl-stack-pack-sudo /etc/sudoers.d/90-wsl-stack-packs"
$DoorClose = "rm -f /etc/sudoers.d/90-wsl-stack-packs"

Reset
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add
Check "nothing to remove -> no removal, and no cleanup" `
    ((Commands) -join " | ") "mkdir -p $Directory/fake-a | test -d /mnt/x/packs/fake-a | cp -r . $Directory/fake-a/ | sh -c find '$Directory/fake-a' -name '*.sh' -exec chmod +x {} + | $DoorOpen | bash install.sh | $DoorClose"

Reset
$script:FailCommand = "test -f"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToRemove @("fake-b")
Check "no remove.sh -> the folder leaves, no script runs" `
    ((Commands) -join " | ") `
    "test -f $Directory/fake-b/remove.sh | rm -rf $Directory/fake-b | cp cleanup_orphans.sh /tmp/cleanup_orphans.sh | env HOME=/home/u bash cleanup_orphans.sh | rm -f /tmp/cleanup_orphans.sh"

Reset
$script:FailCommand = "cp -r ."
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add -ToRemove @("fake-b")
Check "a failed copy names the pack that stopped it" "$($Result.Pack)/$($Result.ExitCode)" "fake-a/1"
Check "  ... and nothing else was touched" (@($script:Calls).Count) "4"

Reset
$script:FailCommand = "bash install.sh"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add
Check "a failed install takes the folder back out" "$($Result.Pack)/$($Result.ExitCode)" "fake-a/1"
Check "  ... and the answer is one object, not that plus the output" (@($Result).Count) "1"
Check "  ... after the failure, not before" `
    ($script:Calls.IndexOf("~ :: rm -rf $Directory/fake-a") -gt
     $script:Calls.IndexOf("$Directory/fake-a :: bash install.sh")) "True"

# Exit code 2 is a pack that asked a question and was told no, not a failure:
# its folder goes back out (the menu reads the folder), but the run carries on -
# no object naming a pack, no failure to explain, the other moves untouched.
Reset
$script:FailCommand = "bash install.sh"
$script:FailCode = 2
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add
Check "a declined install is not a failure" ($null -eq $Result) "True"
Check "  ... its folder goes back out" `
    ($script:Calls.IndexOf("~ :: rm -rf $Directory/fake-a") -gt
     $script:Calls.IndexOf("$Directory/fake-a :: bash install.sh")) "True"

Reset
$script:FailCommand = "env HOME=/home/u bash remove.sh"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add -ToRemove @("fake-b")
Check "a failed remove.sh names that pack" "$($Result.Pack)" "fake-b"
Check "  ... and nothing is installed after it" `
    (@($script:Calls | Where-Object { $_ -like "*bash install.sh*" }).Count) "0"
Check "  ... and its folder stays, it is still installed" `
    (@($script:Calls | Where-Object { $_ -like "*rm -rf $Directory/fake-b*" }).Count) "0"
Check "  ... and the placed pack, never run, loses its folder" `
    (@($script:Calls | Where-Object { $_ -like "*rm -rf $Directory/fake-a*" }).Count) "1"

# The packs after a failure were placed but never ran: their folders go back
# out with the one that stopped the run, or the menu reads them as
# installations that never happened. The queue is ordered, so the position is
# what says which ones never ran.
Reset
$AddTwo = @(
    [PSCustomObject]@{ Name = "fake-a"; Path = "X:\packs\fake-a"; Description = "d" },
    [PSCustomObject]@{ Name = "fake-b"; Path = "X:\packs\fake-b"; Description = "d" }
)
$script:FailCommand = "bash install.sh"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $AddTwo
Check "a failed install takes the tail's folders back out too" `
    ((@($script:Calls | Where-Object { $_ -like "*rm -rf*" }) | ForEach-Object { ($_ -split " :: ", 2)[1] }) -join " | ") `
    "rm -rf $Directory/fake-a | rm -rf $Directory/fake-b"
Check "  ... and the pack after it never ran" `
    (@($script:Calls | Where-Object { $_ -like "*fake-b :: bash install.sh*" }).Count) "0"
Check "  ... and the run names the pack that stopped it" "$($Result.Pack)/$($Result.ExitCode)" "fake-a/1"

# A copy that fails takes the folders placed before it back out: nothing was
# installed, and a folder left behind would pass for an installation.
Reset
$script:FailCommand = "cp -r ."
$script:FailAfter = 2
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $AddTwo
Check "a failed copy takes the earlier placed folder back out" `
    ((@($script:Calls | Where-Object { $_ -like "*rm -rf*" }) | ForEach-Object { ($_ -split " :: ", 2)[1] }) -join " | ") `
    "rm -rf $Directory/fake-b | rm -rf $Directory/fake-a"
Check "  ... and the run names the pack that stopped it" "$($Result.Pack)/$($Result.ExitCode)" "fake-b/1"

Remove-Item -Recurse -Force $PacksRoot -ErrorAction SilentlyContinue

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
