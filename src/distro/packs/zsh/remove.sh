#!/usr/bin/env bash
# ==============================================================================
# THE ZSH PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# The apt packages go one at a time, and one another installed pack still
# claims stays where it is - a pack is one claimant among others, not an
# owner. This pack claims a lot (sudo, git, make...), so it only ever leaves
# when nothing installed requires it any more - the engine's guard, above
# this script.
#
# The files the install wrote in the home go with it; what is YOURS - the
# .env files the gmake keeps your variables in, the history, the cache - is
# not the pack's to take and stays.
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

echo "Removing the socle's tools..."
apt_failed=0
for package in $packages; do
    if claimed_elsewhere "$package"; then
        echo "$package: another installed pack claims it - left in place."
        continue
    fi
    # A failure here is not the end: what apt cannot take back, it says so
    # about, and the script goes on to what it can. With no package lists,
    # `apt-get remove` answers "Unable to locate package" even for an
    # installed one.
    if ! sudo -p "$sudo_prompt" apt-get remove -y "$package"; then
        apt_failed=1
        echo "$package: apt could not remove it - left where it is."
        echo "   (If the run was just interrupted, run the removal again. If apt's"
        echo "   lists are missing: 'sudo apt-get update' inside, then again.)"
    fi
done

# The socle's files, out of ~/.config/zsh. The gmake folder keeps your .env
# files - only its Makefile and modules, which are the pack's, leave; the
# shell's history and cache live under ~/.local and are never touched.
echo "Removing the shell configuration..."
for item in "$here"/config/* "$here"/config/.zshrc; do
    [ -e "$item" ] || continue
    name=$(basename "$item")
    if [ "$name" = "gmake" ]; then
        rm -rf "$HOME/.config/zsh/gmake/Makefile" "$HOME/.config/zsh/gmake/make"
    else
        rm -rf "$HOME/.config/zsh/$name"
    fi
done

# Oh-My-Zsh and the two plugins, where the install put them.
echo "Removing oh-my-zsh..."
rm -rf "$HOME/.local/share/oh-my-zsh"

# Starship and tealdeer, when they are the install's: the image's copies live
# in /usr/local/bin and are not this pack's to take, so only ~/.local/bin is
# looked at - and a neighbour claiming the name holds it, the same rule as
# the packages.
for tool in starship tldr; do
    if [ -e "$HOME/.local/bin/$tool" ] && ! claimed_elsewhere "$tool"; then
        rm -f "$HOME/.local/bin/$tool"
    fi
done

# The .zshenv, only when it is exactly the one the install wrote: a file of
# your own was never touched on the way in, and is not touched on the way out.
# The single quotes are the point: the comparison is against the literal line
# the install writes - the variable expands in the login shell, not here.
# shellcheck disable=SC2016
if [ -e "$HOME/.zshenv" ] && [ "$(cat "$HOME/.zshenv")" = "$(printf '%s\n%s' 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' 'skip_global_compinit=1')" ]; then
    rm -f "$HOME/.zshenv"
fi

if [ "$apt_failed" = 1 ]; then
    # The pack stays: the tool must not be told "removed" while some
    # packages are still installed - the folder is what says so.
    echo "Some packages above are still installed - the pack stays."
    exit 1
fi

echo "The shell socle is gone."
echo "   Your history, your cache and your .env files are where they were; the"
echo "   shell comes back on bash at the next login."
