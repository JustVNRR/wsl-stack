#!/usr/bin/env bash
# ==============================================================================
# THE OH_MY_DOC PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# The packages go one at a time, and one another installed pack still claims
# stays where it is - a pack is one claimant among others, not an owner.
#
# The four Arial files are the pack's own copy, in a directory of its own:
# nothing else under ~/.local/share/fonts is touched.
#
# Two things this never does: remove a library (apt would take its dependents
# along), and autoremove - remove_pack takes the dependencies back afterwards,
# with its question.
#
# Everything this script PRINTS is plain ASCII: it travels through wsl.exe.

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

# The claimed ones leave the list first, then ONE sudo for the lot: each sudo
# call asks again wherever the credential cache does not hold, and seven
# questions for seven packages is friction. apt lists what it takes back.
to_remove=()
echo "Removing Pandoc and the LaTeX engine..."
for package in $packages; do
    if claimed_elsewhere "$package"; then
        echo "$package: another installed pack claims it - left in place."
        continue
    fi
    to_remove+=("$package")
done

# A failure here is not the end: what apt cannot take back, it says so about,
# and the script goes on to the fonts below. With no package lists,
# `apt-get remove` answers "Unable to locate package" even for an installed
# one - a `set -e` script would stop there and leave the rest behind.
apt_failed=0
if [ ${#to_remove[@]} -gt 0 ] && ! sudo -p "$sudo_prompt" apt-get remove -y "${to_remove[@]}"; then
    apt_failed=1
    echo "apt could not remove: ${to_remove[*]} - left where they are."
    echo "(If the run was just interrupted, run the removal again. If apt's"
    echo "lists are missing: 'sudo apt-get update' inside, then again.)"
fi

echo "Removing the Arial files copied from Windows..."
fonts_dir=$HOME/.local/share/fonts/ms-arial
for face in arial.ttf arialbd.ttf ariali.ttf arialbi.ttf; do
    rm -f "$fonts_dir/$face"
done
# The directory only goes when it is empty: anything else in it is not the
# pack's, and a removal that deletes your files is worse than one that leaves an
# empty folder behind. fc-cache notices the files are gone at the next build.
rmdir "$fonts_dir" 2>/dev/null || true
fc-cache -f >/dev/null 2>&1 || true

if [ "$apt_failed" = 1 ]; then
    # The pack stays: the tool must not be told "removed" while the
    # packages are still installed - the folder is what says so.
    echo "The Arial copy is gone; the packages above are still installed - the pack stays."
    exit 1
fi

echo "Pandoc, XeLaTeX and the Arial copy are gone."
echo "   Your documents and their PDFs are where they were."
