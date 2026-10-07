#!/usr/bin/env bash
# ==============================================================================
# THE PANDOC PACK - `font_from_windows`: A FONT FAMILY, FROM THE WINDOWS SIDE
# ==============================================================================
# The pack brings no font of its own. A document that asks for Arial, Times New
# Roman or another Windows font gets it here, one family at a time. Nothing
# comes from the network: these are the fonts this machine owns, copied into
# ~/.local/share/fonts/<family>/, where fc-cache registers them at once.
#
# A font cannot be aliased into place: XeTeX ignores fontconfig substitutions -
# fc-match answers where XeLaTeX stops on "The font ... cannot be found" - so
# the file itself has to arrive.
#
# FONT names a family and a part of one is enough (`FONT=times` takes Times New
# Roman). Unnamed, a menu asks: the families are read out of the Windows files
# themselves (fc-scan), so the menu offers the names a template writes -
# \setmainfont{Times New Roman} - and not file names.
#
# These files are the user's: remove.sh leaves what this fetched where it is -
# one rm away.
set -euo pipefail

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

win_fonts=/mnt/c/Windows/Fonts
[ -d "$win_fonts" ] || die "no $win_fonts in this instance - there is no Windows side to copy from."

# Both spellings: drvfs (the real /mnt/c) matches case-insensitively, a test
# container's bind mount does not, and a font file named .TTF is a font file.
shopt -s nullglob
files=("$win_fonts"/*.ttf "$win_fonts"/*.otf "$win_fonts"/*.ttc
       "$win_fonts"/*.TTF "$win_fonts"/*.OTF "$win_fonts"/*.TTC)
shopt -u nullglob
[ ${#files[@]} -gt 0 ] || die "no font file in $win_fonts."

# One pass of fc-scan for the whole directory, shaped for the shell:
# <file> TAB <first family>. One process for the 376 files, not one each.
table=$(fc-scan --format '%{file}\t%{family[0]}\n' "${files[@]}" 2>/dev/null || true)
[ -n "$table" ] || die "the Windows fonts could not be read."

FONT=${FONT:-}
match=""
if [ -n "$FONT" ]; then
    # Named: a part of the family name is enough, case-insensitively.
    match=$(printf '%s\n' "$table" | awk -F'\t' -v f="$FONT" 'index(tolower($2), tolower(f))')
else
    families=$(printf '%s\n' "$table" | cut -f2 | sort -u)
    if choice=$(printf '%s\n' "$families" | fzf --exact --prompt="family > " --info=inline --layout=reverse); then
        [ -n "$choice" ] || die "Nothing chosen."
        FONT=$choice
    else
        status=$?
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "No family chosen - a menu needs a terminal. Name one instead: gmake font_from_windows FONT=<name>"
    fi
    # Chosen from the list: the family exactly, not a part of it - "Cambria"
    # must not drag "Cambria Math" along.
    match=$(printf '%s\n' "$table" | awk -F'\t' -v f="$FONT" 'tolower($2) == tolower(f)')
fi

[ -n "$match" ] ||
    die "no font family on the Windows side matches '$FONT' - the menu (no FONT) lists the names."

# FONT may have been a part of one ("times"), and a part can catch more than
# one family: what travels is what the files themselves carry.
selected=$(printf '%s\n' "$match" | cut -f1)
landed=$(printf '%s\n' "$match" | cut -f2 | sort -u | paste -sd', ')

# The directory is named after the first family: lower case, non-alphanumerics
# to dashes ([:alnum:] in brackets, so an accented name keeps its letters).
slug=$(printf '%s\n' "$match" | cut -f2 | sort -u | head -n 1 |
    tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')
dest=$HOME/.local/share/fonts/$slug
install -d "$dest"
count=0
while IFS= read -r file; do
    install -m 644 "$file" "$dest/$(basename "$file")"
    count=$((count + 1))
done <<< "$selected"

# fc-cache, so the family is in fontconfig's cache at once - the document's
# build is usually the next command.
fc-cache -f >/dev/null 2>&1 || true

echo "✅ $landed: $count file(s) -> $dest"
echo "   A template asks for it by that name - e.g. \\setmainfont{$(printf '%s\n' "$match" | cut -f2 | sort -u | head -n 1)}."
