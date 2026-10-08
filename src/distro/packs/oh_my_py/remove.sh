#!/usr/bin/env bash
# ==============================================================================
# THE OH_MY_PY PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# The apt packages go one at a time, and one another installed pack still
# claims stays where it is - a pack is one claimant among others, not an owner.
#
# uv is the same question about something apt never saw (PACK_OUTSIDE_APT): the
# hide_my_scaff pack names it too, so the first of the two to leave leaves uv where
# it is, and the last takes it away with everything it manages - the
# interpreter, the tools' environments, the cache. The whole tree goes
# together: its shims point into it, and half of it is worth nothing.
#
# Two things this never does: remove a library, and autoremove - remove_pack
# takes the dependencies back afterwards.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

# sudo's own prompt has no trailing newline, and the line-based capture
# behind wsl.exe only showed whole lines: the question stayed invisible and
# the call waited forever. This prompt ends its line, so it shows.
sudo_prompt=$(printf '[sudo] password:\n')
packages=$(sed -n 's/^PACK_PACKAGES *:=[[:space:]]*//p' "$here/pack.conf")

if [ -z "$packages" ]; then
    echo "No PACK_PACKAGES found in $here/pack.conf" >&2
    exit 1
fi

# A claim is a declaration, not a mention: the name is read off PACK_PACKAGES
# and PACK_OUTSIDE_APT, and off install.sh for a pack written before the first
# existed.
claimed_elsewhere() {
    local other value word
    for other in "$HOME"/.config/packs/*/; do
        if [ "${other%/}" = "$here" ]; then
            continue
        fi
        value=$(sed -nE 's/^PACK_(PACKAGES|OUTSIDE_APT) *:=[[:space:]]*//p' "$other/pack.conf" 2>/dev/null)
        for word in $value; do
            if [ "$word" = "$1" ]; then
                return 0
            fi
        done
        grep -q -- "$1" "$other/install.sh" 2>/dev/null && return 0
    done
    return 1
}

echo "Removing the compilation tools..."
apt_failed=0
for package in $packages; do
    if claimed_elsewhere "$package"; then
        echo "$package: another installed pack claims it - left in place."
        continue
    fi
    # A failure here is not the end: what apt cannot take back, it says so
    # about, and the script goes on to what it can (uv, below). With no package
    # lists, `apt-get remove` answers "Unable to locate package" even for an
    # installed one.
    if ! sudo -p "$sudo_prompt" apt-get remove -y "$package"; then
        apt_failed=1
        echo "$package: apt could not remove it - left where it is."
        echo "   (If the run was just interrupted, run the removal again. If apt's"
        echo "   lists are missing: 'sudo apt-get update' inside, then again.)"
    fi
done

# ruff goes back whether or not uv stays. Both halves matter: the shim in
# ~/.local/bin is where the next install trips - uv refuses to write an
# executable that is already there - and a shim whose target is gone answers
# "No such file or directory" to whoever types it.
echo "Removing ruff..."
rm -f "$HOME/.local/bin/ruff"
rm -rf "$HOME/.local/share/uv/tools/ruff"

if claimed_elsewhere uv; then
    echo "uv: another installed pack claims it - left in place, with what it manages."
else
    echo "Removing uv and what it installed..."
    # By name, not by asking uv: `uv tool uninstall` lives on the very binary
    # being removed, and a removal must work on a machine where the install
    # stopped halfway. Everything uv wrote is in ~/.local/bin (the shims),
    # ~/.local/share/uv and its cache; every path is spelled from $HOME.
    #
    # The Python shims are named after their version, and the pack never chose
    # it - it asks uv for `3`, whatever that is today - hence the glob, with
    # nullglob so an empty directory hands `rm` nothing.
    shopt -s nullglob
    rm -rf "$HOME/.local/bin/uv" \
           "$HOME/.local/bin/uvx" \
           "$HOME"/.local/bin/python3.* \
           "$HOME/.local/bin/copier" \
           "$HOME/.local/bin/cruft" \
           "$HOME/.local/bin/ruff" \
           "$HOME/.local/bin/cookiecutter" \
           "$HOME/.local/bin/ccds" \
           "$HOME/.local/share/uv" \
           "$HOME/.cache/uv"
fi

if [ "$apt_failed" = 1 ]; then
    # The pack stays: the tool must not be told "removed" while some
    # packages are still installed - the folder is what says so.
    echo "Some packages above are still installed - the pack stays."
    exit 1
fi

echo "Python 3 and its tools are gone."
echo "   What the pack wrote in ~/.local went with it; your projects are where they were."
