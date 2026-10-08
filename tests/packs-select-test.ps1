# Drives the ask/apply pair - the checklist in the module's questions, the
# applying in the module's pack moves - with no instance and no terminal.
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
#                  Get-InstanceHome is stubbed below, and inside the packs
#                  module: the pack moves ask it directly, and it would
#                  otherwise reach the machine.
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
#   1, v            a visible pack unticked under a standing claimant - refused
#   1, 2, v, (empty) both unticked -> the same answer goes through
#   1, v, (empty)   the debian family: only the debian-family pack is shown
#   1, v, (empty)   the fedora family: only the fedora-family pack is shown
#
#   powershell -File tests\packs-select-test.ps1 < tests\packs-select-test.answers
#
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\src\windows\WslStack\WslStack.psd1") -Force

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
Write-Output "--- The refusal: a pack a standing pack requires does not leave ---"

# A second catalog of its own: a shape the first one does not carry - a
# VISIBLE pack that another visible one requires, which is what the guard is
# about. The first catalog's scenarios answer by box number, so one more box
# there would shift every answer; this root has its runs to itself.
$PacksRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("packs-select-guard-" + [Guid]::NewGuid().ToString("N"))
$Declarations2 = @(
    @{ Name = "oh_my_shell";    Description = "The shell" },
    @{ Name = "python"; Description = "Python toolchain"; Requires = "oh_my_shell" },
    @{ Name = "web";    Description = "Web tooling";      Requires = "oh_my_shell" }
)
foreach ($Declaration in $Declarations2) {
    $Folder = Join-Path $PacksRoot2 $Declaration.Name
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $Conf = @("PACK_DESCRIPTION := $($Declaration.Description)")
    if ($Declaration.Requires) { $Conf += "PACK_REQUIRES := $($Declaration.Requires)" }
    Set-Content -Path (Join-Path $Folder "pack.conf") -Value $Conf
}
$Guarded = Get-PackCatalog -Root $PacksRoot2

# The resolver reports what cannot leave, with the packs that hold it - and
# the two directions at once: a standing claimant holds, one leaving with it
# does not.
$R = Resolve-PackSelection -Catalog $Guarded -Installed @("oh_my_shell", "python") -Kept @("python")
Check "a visible pack unticked under a standing claimant is a conflict" `
    ("$($R.Conflicts.Name)/$($R.Conflicts.Blockers -join ',')") "oh_my_shell/python"
Check "  ... and the rest of the selection still comes back" `
    ("$($R.ToRemove -join ',')/$($R.ToAdd.Count)") "oh_my_shell/0"

$R = Resolve-PackSelection -Catalog $Guarded -Installed @("oh_my_shell", "python") -Kept @()
Check "both unticked -> both leave, nothing holds" ("$($R.Conflicts.Count)") "0"

$R = Resolve-PackSelection -Catalog $Guarded -Installed @("oh_my_shell") -Kept @("web")
Check "a claimant just arriving holds it too" `
    ("$($R.Conflicts.Name)/$($R.Conflicts.Blockers -join ',')") "oh_my_shell/web"

# The rule under the guard: a visible pack is NEVER taken along by the
# cascade - only an invisible one leaves with the pack nothing requires any
# more. Both sides of that line, on the same departure.
Check "a visible pack is never cascaded out" `
    (($Guarded.ResolveRemoval(@("oh_my_shell", "python"), @("python"), @())) -join ",") "python"
Check "  ... where an invisible one follows its last claimant" `
    (($Catalog.ResolveRemoval(@("python", "devops"), @("python"), @())) -join ",") "python,devops"

# The console's own refusal: the unticked box under a standing claimant
# stops the question where it is instead of applying the rest of it.
$Selection = Select-Packs -Title "T" -Catalog $Guarded -Installed @("oh_my_shell", "python")
Check "the console refuses the answer" ($null -eq $Selection) "True"

# ... and the same answer with the claimant unticked as well goes through:
# the guard refuses a broken removal, never a removal.
$Selection = Select-Packs -Title "T" -Catalog $Guarded -Installed @("oh_my_shell", "python")
Check "both unticked -> the run goes through" `
    ((($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") + " / " + ($Selection.ToRemove -join ",")) " / oh_my_shell,python"

Write-Output ""
Write-Output "--- The family: a pack is only offered where its apt lives ---"

# A third catalog, of three packs of two families: the filter reads
# PACK_FAMILY (absent means debian), and the machine's own family - read from
# its /etc/os-release - decides which one a question shows. Its shell pack is
# Fedora's, so it is also what says the build's default stays unticked when
# the shell is not the build's own family.
$PacksRoot3 = Join-Path ([System.IO.Path]::GetTempPath()) ("packs-select-family-" + [Guid]::NewGuid().ToString("N"))
$Declarations3 = @(
    @{ Name = "alpha"; Description = "A Debian-family pack" },
    @{ Name = "beta";  Description = "A Fedora-family pack"; Family = "fedora" },
    @{ Name = "oh_my_shell";   Description = "A Fedora-family shell"; Family = "fedora" }
)
foreach ($Declaration in $Declarations3) {
    $Folder = Join-Path $PacksRoot3 $Declaration.Name
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $Conf = @("PACK_DESCRIPTION := $($Declaration.Description)")
    if ($Declaration.Family) { $Conf += "PACK_FAMILY := $($Declaration.Family)" }
    Set-Content -Path (Join-Path $Folder "pack.conf") -Value $Conf
}
$Familied = Get-PackCatalog -Root $PacksRoot3

Check "a pack without PACK_FAMILY reads as debian" ($Familied.GetPack("alpha").Family) "debian"
Check "a declared family is read" ($Familied.GetPack("beta").Family) "fedora"
Check "the debian surface shows only the debian pack" `
    (($Familied.OfferedFor("debian").Name) -join ",") "alpha"
Check "  ... and the fedora one the other" `
    (($Familied.OfferedFor("fedora").Name) -join ",") "beta,oh_my_shell"
Check "a machine that cannot say filters nothing" `
    (($Familied.OfferedFor("").Name) -join ",") "alpha,beta,oh_my_shell"

# The build's default box: the shell pack every visible pack requires, and
# only where its family is the build's own - a built image is Debian.
Check "the build ticks the shell pack" ((Get-BuildDefaultPacks -Catalog $Guarded) -join ",") "oh_my_shell"
Check "  ... and nothing when the shell is another family" ((Get-BuildDefaultPacks -Catalog $Familied) -join ",") ""
Check "  ... or when the catalog carries no shell" ((Get-BuildDefaultPacks -Catalog $Catalog) -join ",") ""

# What the checklist means on each family: the same boxes question, one pack
# fewer - and a foreign-family pack, installed here or not, is in neither
# list.
$R = Resolve-PackSelection -Catalog $Familied -Installed @("beta") -Kept @() -Family "debian"
Check "a foreign-family pack is not on the debian checklist" `
    ("$($R.ToRemove -join ',')/$($R.ToAdd.Count)") "/0"

$Selection = Select-Packs -Title "T" -Catalog $Familied -Installed @() -Family "debian"
Check "the debian checklist offers the debian pack" `
    (($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") "alpha"

$Selection = Select-Packs -Title "T" -Catalog $Familied -Installed @() -Family "fedora"
Check "the fedora checklist offers the fedora pack" `
    (($Selection.ToAdd | ForEach-Object { $_.Name }) -join ",") "beta"

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

# The pack moves ask the instance for the user's home through wsl.exe directly
# - outside the stand-in - and Enable-PackSudo reads the user name out of it.
# Answered twice: here for whatever calls it from the script's side, and inside
# the packs module, where the moves' own lookups start and this script's
# functions are out of reach.
function Get-InstanceHome { param([string]$DistroName) return "/home/u" }
& ((Get-Module WslStack).NestedModules | Where-Object { $_.Name -eq 'WslStack.Packs' }) {
    function Get-InstanceHome { param([string]$DistroName) return "/home/u" }
}

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
    ((Commands) -join " | ") "mkdir -p $Directory/fake-a | test -d /mnt/x/packs/fake-a | cp -r . $Directory/fake-a/ | sh -c find '$Directory/fake-a' -name '*.sh' -exec chmod +x {} + | test -f $Directory/fake-a/install_root.sh | env HOME=/home/u bash install_root.sh | $DoorOpen | bash install.sh | $DoorClose"

# The root half runs BEFORE the door, as WSL's own root: the door is a
# sudoers rule, and the shell pack carries sudo itself - on a bare Debian its
# root half must run where no door can open yet.
Check "  ... and it ran before the door opened" `
    ($script:Calls.IndexOf("$Directory/fake-a :: env HOME=/home/u bash install_root.sh") -lt
     $script:Calls.IndexOf("~ :: $DoorOpen")) "True"

# A pack without a root half - claude is one - installs all the same.
Reset
$script:FailCommand = "test -f $Directory/fake-a/install_root.sh"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add
Check "a pack without a root half skips it" `
    (@($script:Calls | Where-Object { $_ -like "*install_root.sh*" }).Count) "1"
Check "  ... and still runs its install behind the door" `
    ($script:Calls.IndexOf("$Directory/fake-a :: bash install.sh") -gt
     $script:Calls.IndexOf("~ :: $DoorOpen")) "True"
Check "  ... nothing failed" ($null -eq $Result) "True"

# A root half that fails stops everything before the door: no install.sh has
# run, so every folder goes back out - and the door never opens.
Reset
$script:FailCommand = "env HOME=/home/u bash install_root.sh"
$Result = Invoke-PackApply -DistroName "test" -PacksDirectory $Directory -ToAdd $Add
Check "a failed root half names the pack" "$($Result.Pack)/$($Result.ExitCode)" "fake-a/1"
Check "  ... no install.sh ran" `
    (@($script:Calls | Where-Object { $_ -like "*bash install.sh*" }).Count) "0"
Check "  ... the door never opened" `
    (@($script:Calls | Where-Object { $_ -like "*NOPASSWD*" }).Count) "0"
Check "  ... and every folder went back out" `
    (@($script:Calls | Where-Object { $_ -like "*rm -rf $Directory/fake-a*" }).Count) "1"

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

Remove-Item -Recurse -Force $PacksRoot, $PacksRoot2, $PacksRoot3 -ErrorAction SilentlyContinue

Write-Output ""
Write-Output ("failures: " + $Failures)
exit $Failures
