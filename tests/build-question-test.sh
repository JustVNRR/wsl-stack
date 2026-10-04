#!/usr/bin/env bash
# Exercises the FIRST HALF of .\wsl.ps1 build - the questions - with no Docker
# Desktop and no instance.
#
# fake-docker-run.ps1 puts a stand-in docker on the PATH: it answers the
# preflight and the first steps, then hands the import a file that is not a tar
# - so every run stops on the deployment-error path with the packs already
# chosen, the only path where the packs show without a real build.
#
# What it proves:
#   - the pack checklist is asked after the name and the folder, and before
#     anything is created
#   - the user name is asked with the other questions (after the checklist,
#     before the build), and a refused name comes back to the question
#   - an empty checklist, applied or cancelled, means no pack, says so, and is
#     asked no confirmation
#   - a pack chosen is installed later, so the failure report names it
#   - nothing is left behind: no instance, no tar, no folder, exit code 1
#
# Usage: bash tests/build-question-test.sh
#        PS_ENGINE=powershell bash tests/build-question-test.sh   (the old PowerShell)
set -u

TestsDir=$(cd "$(dirname "$0")" && pwd)
RepoTemplate=$(cd "$TestsDir/.." && pwd)
# powershell -File wants the Windows form of the path: the checkout may live
# anywhere, under a Git Bash that spells it /d/...
Run=$(cygpath -w "$TestsDir/fake-docker-run.ps1")
# The engine under test: PowerShell 7, or what PS_ENGINE names.
PS=${PS_ENGINE:-pwsh}

Failures=0
Out=$(mktemp)
# Where the checkout stands before the runs: they write nothing, and this is
# what says so - whether the tree is clean or carries work in progress.
Before=$(git -C "$RepoTemplate" status --short)

run_build() {
    printf '%b' "$1" | $PS -NoProfile -ExecutionPolicy Bypass -File "$Run" build > "$Out" 2>&1
    Code=$?
}

check() {
    if [ "$2" = "$3" ]; then
        echo "OK   $1"
    else
        echo "FAIL $1 : expected '$3', got '$2'"
        Failures=$((Failures + 1))
    fi
}

contains() { if grep -aqF "$1" "$Out"; then echo yes; else echo no; fi; }
line_of()  { grep -anF "$1" "$Out" | head -1 | cut -d: -f1; }
# Both lines must be there before their order means anything: a check comparing
# two empty strings answers yes and proves nothing - the shape of the mistake
# that once made a check unable to fail.
before() {
    local a b
    a=$(line_of "$1"); b=$(line_of "$2")
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then echo yes; else echo no; fi
}

echo "--- cancelled at the checklist (answer 0)"
run_build 'pack-qtest-1\n\n0\nqtestuser\n'
check "says no pack was selected"     "$(contains "[OK] No pack selected: 'pack-qtest-1' will be built without one.")" "yes"
check "does not mention any chosen pack" "$(contains 'The packs chosen earlier')" "no"
check "the run stops on the deployment"  "$(contains '[ERROR] DURING DEPLOYMENT')" "yes"
check "and says the deployment failed"   "$(contains 'WSL import failed.')" "yes"
check "exit code 1"                      "$Code" "1"

echo ""
echo "--- empty checklist, applied (answer v)"
run_build 'pack-qtest-2\n\nv\nqtestuser\n'
check "says no pack was selected"     "$(contains "[OK] No pack selected: 'pack-qtest-2' will be built without one.")" "yes"
check "does not mention any chosen pack" "$(contains 'The packs chosen earlier')" "no"
check "exit code 1"                      "$Code" "1"

echo ""
echo "--- one pack chosen (2 = the second in the list) and confirmed"
# 'Root' first: a name the rule refuses, so the question's own re-ask shows in
# the output. The Read-Host prompt itself cannot be asserted on - the runner's
# pwsh does not write it to a captured stream, a Write-Host always is.
run_build 'pack-qtest-3\n\n2\nv\n\nRoot\nqtestuser\n'
# Which pack answer 2 chose is read from the run rather than written here: this
# checkout's packs are not another checkout's packs.
Chosen=$(grep -aoE 'Will install : .*' "$Out" | head -1 | sed 's/Will install : //' | tr -d '\r')
check "the checklist arrives before the build" "$(before "Packs for 'pack-qtest-3'" '==> 1. Building Docker')" "yes"
check "and after the name" "$(before '==> Creating a new instance' "Packs for 'pack-qtest-3'")" "yes"
check "the user name is asked after the checklist" "$(before "Packs for 'pack-qtest-3'" 'Lowercase letters, digits')" "yes"
check "and a refused name is asked again" "$(contains 'Lowercase letters, digits')" "yes"
check "and the build starts only after it" "$(before 'Lowercase letters, digits' '==> 1. Building Docker')" "yes"
check "the one line of the summary names a pack" "$([ -n "$Chosen" ] && echo yes || echo no)" "yes"
check "no empty 'Will remove' line"              "$(contains 'Will remove')" "no"
check "the failure names the pack it could not install" \
    "$(contains "The packs chosen earlier ($Chosen) were not installed: the build stopped before them.")" "yes"
check "exit code 1" "$Code" "1"

echo ""
echo "--- the folder question's other answers: n, an unusable path, cancel"
run_build 'path-qtest-1\nn\nx<y\n\n'
check "says the path is unusable" "$(contains "'x<y' is not a usable path.")" "yes"
check "and cancels on the empty answer" "$(contains '[ABORT] Operation cancelled by user. Nothing was modified.')" "yes"
check "nothing is built"                "$(contains '==> 1. Building Docker')" "no"
check "exit code 0"                     "$Code" "0"

echo ""
echo "--- a build started while another holds the lock"
# Another build is a small PowerShell holding the same named lock; it says so
# by writing a file, so the test knows the lock is taken before running the
# second one. The second must refuse before asking anything.
Holder=$(mktemp --suffix=.ps1)
HeldFlag=$(mktemp)
rm -f "$HeldFlag"
cat > "$Holder" <<'EOF'
$m = [System.Threading.Mutex]::new($false, "Global\wsl-stack-build")
$null = $m.WaitOne(0)
[System.IO.File]::WriteAllText($args[0], "held")
Start-Sleep -Seconds 15
$m.ReleaseMutex()
EOF
$PS -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$Holder")" "$(cygpath -w "$HeldFlag")" &
HolderPid=$!
for _ in $(seq 1 60); do [ -f "$HeldFlag" ] && break; sleep 0.25; done
run_build 'lock-qtest\n'
check "refuses while another build holds the lock" "$(contains '[ABORT] Another build is already running.')" "yes"
check "and asks nothing first"                     "$(contains 'Name of the instance')" "no"
check "exit code 1"                                "$Code" "1"
kill $HolderPid 2>/dev/null
wait $HolderPid 2>/dev/null
rm -f "$Holder" "$HeldFlag"

echo ""
echo "--- nothing left on the machine"
check "no instance registered" "$(wsl.exe --list --quiet 2>/dev/null | tr -d '\0' | grep -ac 'pack-qtest' )" "0"
check "no folder left"         "$(find /d/WSL -maxdepth 1 -name 'pack-qtest-*' 2>/dev/null | wc -l)" "0"
check "no tar left"            "$(find /d/WSL -maxdepth 1 -name '*rootfs.tar' 2>/dev/null | wc -l)" "0"
echo "--- and the checkout is untouched by the runs"
check "the runs left the checkout exactly as it was" \
    "$([ "$Before" = "$(git -C "$RepoTemplate" status --short)" ] && echo yes || echo no)" "yes"

rm -f "$Out"
echo ""
echo "failures: $Failures"
exit $Failures
