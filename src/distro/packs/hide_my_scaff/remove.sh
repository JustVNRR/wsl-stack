#!/usr/bin/env bash
# ==============================================================================
# THE HIDE_MY_SCAFF PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# One thing to take back - uv - and one thing never to touch: ~/projects. The
# projects in there are the user's; the pack wrote none, and the folder comes
# from the image and outlives every pack.
#
# uv is the oh_my_py pack's too: the question is asked before anything is erased
# (the same one PACK_PACKAGES answers for apt's packages) - the last pack that
# declares it takes it away, with the interpreter and the cache.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

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

if claimed_elsewhere uv; then
    echo "uv: another installed pack claims it - left in place, with what it manages."
else
    echo "Removing uv and what it manages..."
    # Everything uv wrote: the shims in ~/.local/bin, its builds and tools under
    # ~/.local/share/uv, its cache. Every path is spelled from $HOME.
    rm -rf "$HOME/.local/bin/uv" \
           "$HOME/.local/bin/uvx" \
           "$HOME"/.local/bin/python3.* \
           "$HOME/.local/share/uv" \
           "$HOME/.cache/uv"
fi

echo "The scaffolding is gone."
echo "   ~/projects was left alone - the projects in it are yours."
