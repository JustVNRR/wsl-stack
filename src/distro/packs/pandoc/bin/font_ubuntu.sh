#!/usr/bin/env bash
# ==============================================================================
# THE PANDOC PACK - `font_from_ubuntu`: A FAMILY, FROM THE UBUNTU PACKAGES
# ==============================================================================
# The third source of fonts, and the only one that installs nothing by hand:
# the fonts- packages of the archive - Noto, EB Garamond, the URW PostScript
# classics (Nimbus Roman for Times, Nimbus Sans for Helvetica)...
#
# FONT names one and a part of the name is enough; unnamed, a menu asks - fzf
# over the packages and their one-line description, with --exact.
#
# The install is apt's, with one sudo. The package is the user's: it leaves
# with `sudo apt-get remove`, not with the pack.
set -euo pipefail

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

list=$(apt-cache search --names-only '^fonts-' | sort)
[ -n "$list" ] ||
    die "apt knows no fonts- package - are the package lists there? (sudo apt-get update)"

CHOSEN=""
choose() {
    local choice status
    if choice=$(printf '%s\n' "$1" | fzf --exact --prompt="package > " --info=inline --layout=reverse); then
        [ -n "$choice" ] || die "Nothing chosen."
        CHOSEN=$choice
    else
        status=$?
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "No package chosen - a menu needs a terminal. Name one instead: gmake font_from_ubuntu FONT=<name>"
    fi
}

FONT=${FONT:-}
if [ -n "$FONT" ]; then
    # On the PACKAGE NAME, never on the whole line: a description mentions
    # other packages ("fonts-ebgaramond-extra" is described next to its
    # parent), and a name that is a part of another's is what the menu is for
    # - it lists the few that answer.
    matches=$(printf '%s\n' "$list" | awk -v f="$FONT" 'index(tolower($1), tolower(f))')
    [ -n "$matches" ] || die "no fonts- package matches '$FONT' - the menu (no FONT) lists them."
    if [ "$(printf '%s\n' "$matches" | grep -c .)" -eq 1 ]; then
        CHOSEN=$matches
    else
        choose "$matches"
    fi
else
    choose "$list"
fi

# "fonts-noto-core - Noto fonts, except the CJK..." is what apt answers: the
# package is the first word.
package=${CHOSEN%% *}

echo "Installing $package (your password will be asked)..."
sudo apt-get install -y "$package"
echo "✅ $package installed."
echo "   A template asks for its families by name - fc-list : family | sort -u"
