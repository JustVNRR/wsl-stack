#!/usr/bin/env bash
# ==============================================================================
# THE VISION PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added to the system leaves it, and only that.
#
# One package at a time, and one another installed pack still claims stays: a
# pack is one claimant among others, not an owner. The claim is read from every
# pack's declaration, pack.conf and install.sh alike; the last one to want a
# package takes it away.
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

# Is this package claimed by another pack that is still installed?
claimed_elsewhere() {
    grep -rl --include=pack.conf --include=install.sh -- "$1" "$HOME/.config/packs" 2>/dev/null |
        grep -qv "^${here}/"
}

echo "Removing the vision and OCR tools..."
for package in $packages; do
    if claimed_elsewhere "$package"; then
        echo "$package: another installed pack claims it - left in place."
        continue
    fi
    sudo -p "$sudo_prompt" apt-get remove -y "$package"
done

echo "ffmpeg, ImageMagick and Tesseract are gone."
echo "   Your own files were left alone - the pack wrote none of them."
