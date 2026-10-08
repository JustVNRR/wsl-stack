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
#     before the build), and refused names come back to the question - the
#     case ('Root'), and the leading underscore adduser would not take
#   - an empty answer takes the proposed Windows name, cleaned into one the
#     rule accepts
#   - the checklist opens with the shell pack ticked: applied as-is it chooses
#     it; cancelling means no pack, says so, and is asked no confirmation
#   - a pack chosen is installed later, so the failure report names it
#   - a recipe path that is not a file stops the run before anything is asked
#   - an option the build knows binds by name, one it does not is refused
#   - the onboarding is asked with the rest (Y on an empty answer) and the
#     shell list follows it - the repository's own first - and on 'n' nothing
#     of the onboarding is asked, the account question included
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
# The Windows account name the build proposes: dotted and cased, so the
# cleaning is exercised wherever the suite runs - the sandbox is not Windows.
export USERNAME="Jean.Dupont"

Failures=0
Out=$(mktemp)
# Where the checkout stands before the runs: they write nothing, and this is
# what says so - whether the tree is clean or carries work in progress. The
# seeds are the writes a run is meant to make (the first import fills
# assets\packs, assets\dockerfiles and assets\firstboots from src), so they
# are left out of the picture.
tree_state() {
    git -C "$RepoTemplate" status --short | grep -vE 'assets/(packs|dockerfiles|firstboots)' || true
}
Before=$(tree_state)

# Whatever follows the answers is handed to the build as it came: the recipe
# options ride through the entry the way -Format does for archive.
run_build() {
    printf '%b' "$1" | $PS -NoProfile -ExecutionPolicy Bypass -File "$Run" build "${@:2}" > "$Out" 2>&1
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
# The user name is left empty: the proposed Windows name must be taken. The
# name after it is the fallback for a build that fails to propose - the check
# on the hint is what tells the two apart.
run_build 'pack-qtest-1\n\n0\n\n1\n\nqtestuser\n'
check "says no pack was selected"     "$(contains '[OK] No pack selected.')" "yes"
check "an empty answer takes the proposed name" "$(contains 'Lowercase letters, digits')" "no"
check "does not mention any chosen pack" "$(contains 'The packs chosen earlier')" "no"
check "the run stops on the deployment"  "$(contains '[ERROR] DURING DEPLOYMENT')" "yes"
check "and says the deployment failed"   "$(contains 'WSL import failed.')" "yes"
check "exit code 1"                      "$Code" "1"

echo ""
echo "--- the pre-ticked shell, applied as-is (answer v, then the confirmation)"
run_build 'pack-qtest-2\n\nv\n\n\n1\n\nqtestuser\n'
check "does not say no pack was selected" "$(contains '[OK] No pack selected.')" "no"
check "and names the pack that was"       "$(contains 'The packs chosen earlier')" "yes"
check "exit code 1"                       "$Code" "1"

echo ""
echo "--- one pack chosen (2 = the second in the list) and confirmed"
# Two names the rule refuses first - 'Root' for the case, '_jean' for the
# leading underscore adduser would not take - so the question's own re-ask
# shows in the output. The Read-Host prompt itself cannot be asserted on -
# the runner's pwsh does not write it to a captured stream, a Write-Host does.
run_build 'pack-qtest-3\n\n2\nv\n\n\n1\nRoot\n_jean\nqtestuser\n'
# Which pack answer 2 chose is read from the run rather than written here: this
# checkout's packs are not another checkout's packs.
Chosen=$(grep -aoE 'Will install : .*' "$Out" | head -1 | sed 's/Will install : //' | tr -d '\r')
check "the checklist arrives before the build" "$(before "Packs for 'pack-qtest-3'" '==> 1. Building Docker')" "yes"
check "and after the name" "$(before '==> Creating a new instance' "Packs for 'pack-qtest-3'")" "yes"
check "the user name is asked after the checklist" "$(before "Packs for 'pack-qtest-3'" 'Lowercase letters, digits')" "yes"
check "and a refused name is asked again" "$(contains 'Lowercase letters, digits')" "yes"
check "both refused names come back to the question" "$(grep -ac 'Lowercase letters, digits' "$Out")" "2"
check "and the build starts only after it" "$(before 'Lowercase letters, digits' '==> 1. Building Docker')" "yes"
check "the one line of the summary names a pack" "$([ -n "$Chosen" ] && echo yes || echo no)" "yes"
check "no empty 'Will remove' line"              "$(contains 'Will remove')" "no"
check "the failure names the pack it could not install" \
    "$(contains "The packs chosen earlier ($Chosen) were not installed: the build stopped before them.")" "yes"
check "exit code 1" "$Code" "1"

echo ""
echo "--- the onboarding skipped (answer n): no account is asked for"
# 'Root' follows the 'n': if the account question were asked, the rule would
# refuse it and print the hint - with the onboarding off, nothing reads it.
run_build 'pack-qtest-5\n\n0\nn\nRoot\n'
check "says no pack was selected"         "$(contains '[OK] No pack selected.')" "yes"
check "the account question is not asked" "$(contains 'Lowercase letters')" "no"
check "and the run goes on to the build"  "$(contains '==> 1. Building Docker')" "yes"
check "exit code 1"                       "$Code" "1"

echo ""
echo "--- the folder question's other answers: n, an unusable path, cancel"
run_build 'path-qtest-1\nn\nx<y\n\n'
check "says the path is unusable" "$(contains "'x<y' is not a usable path.")" "yes"
check "and cancels on the empty answer" "$(contains '[ABORT] Operation cancelled by user.')" "yes"
check "nothing is built"                "$(contains '==> 1. Building Docker')" "no"
check "exit code 0"                     "$Code" "0"

echo ""
echo "--- the recipe: a path that is not a file, then one that is"
# The recipe is checked before anything is asked or destroyed: a missing file
# stops the run with nothing confirmed and nothing touched.
run_build 'recipe-qtest-1\n' -Dockerfile "$RepoTemplate/nowhere/Dockerfile"
check "refuses a Dockerfile that is not a file" "$(contains '[ABORT] The Dockerfile is not a file:')" "yes"
check "and says nothing was modified"           "$(contains 'Nothing was modified.')" "yes"
check "and asks nothing"                        "$(contains 'Name of the instance')" "no"
check "and builds nothing"                      "$(contains '==> 1. Building Docker')" "no"
check "exit code 1"                             "$Code" "1"

run_build 'recipe-qtest-2\n' -FirstBoot "$RepoTemplate/nowhere/first_boot.sh"
check "and a first_boot that is not a file too" "$(contains '[ABORT] The first_boot is not a file:')" "yes"
check "exit code 1"                             "$Code" "1"

# A path that is a file: the option is accepted and the questions start -
# the run goes all the way to the build, where the stand-in docker stops it
# like every other run here.
run_build 'pack-qtest-4\n\n0\n\n1\n\nqtestuser\n' -Dockerfile "$RepoTemplate/src/distro/build/Dockerfile"
check "a real Dockerfile is accepted" "$(contains '==> 1. Building Docker')" "yes"
check "no recipe abort"               "$(contains '[ABORT] The Dockerfile')" "no"
check "exit code 1"                   "$Code" "1"

# An option the build does not know still lands in its unknown-options
# refusal: the entry rebuilds the tokens, it does not swallow them.
run_build 'x\n' -Whatever
check "an unknown option is refused" "$(contains '[ABORT] Unknown options after the command.')" "yes"
check "exit code 1"                  "$Code" "1"

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
    "$([ "$Before" = "$(tree_state)" ] && echo yes || echo no)" "yes"

rm -f "$Out"
echo ""
echo "failures: $Failures"
exit $Failures
