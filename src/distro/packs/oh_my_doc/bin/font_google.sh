#!/usr/bin/env bash
# ==============================================================================
# THE OH_MY_DOC PACK - `font_from_google`: A FAMILY, FROM GOOGLE FONTS
# ==============================================================================
# The second source of fonts beside the Windows side: Google Fonts - around
# 1 800 families, all free, no account, one repository.
#
# FONT names a family and a part of one is enough; unnamed, a menu asks - fzf
# over the catalogue with --exact: fuzzy mode matches letters scattered through
# a name ("asi" finds "acm-siggraph"), which reads as noise on a list of
# thousands.
#
# The files land in ~/.local/share/fonts/google/<family>/, where fc-cache
# registers them at once. They are the user's: removing the pack leaves them.
set -euo pipefail

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

api=https://api.github.com/repos/google/fonts/contents
list=$(mktemp)
trap 'rm -f "$list"' EXIT

# The catalogue is the three licence folders of the repository - ofl, apache,
# ufl - one folder per family inside them. One API call per licence, and the
# names come back shaped for the picker: <licence> TAB <family>, the licence
# hidden from the display and kept by the choice, which fzf prints whole.
for licence in ofl apache ufl; do
    curl -fsSL "$api/$licence" 2>/dev/null |
        jq -r --arg lic "$licence" '.[] | select(.type == "dir") | "\($lic)\t\(.name)"' >> "$list" || true
done
[ -s "$list" ] ||
    die "the catalogue could not be read - is there a network? (GitHub also refuses for an hour once its unauthenticated limit is reached.)"

CHOSEN=""
choose() {
    local choice status
    if choice=$(printf '%s\n' "$1" | fzf --exact --with-nth=2 --prompt="family > " --info=inline --layout=reverse); then
        [ -n "$choice" ] || die "Nothing chosen."
        CHOSEN=$choice
    else
        status=$?
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "No family chosen - a menu needs a terminal. Name one instead: gmake font_from_google FONT=<name>"
    fi
}

FONT=${FONT:-}
if [ -n "$FONT" ]; then
    matches=$(awk -F'\t' -v f="$FONT" 'index(tolower($2), tolower(f))' "$list")
    [ -n "$matches" ] || die "no family matches '$FONT' - the menu (no FONT) lists the catalogue."
    if [ "$(printf '%s\n' "$matches" | grep -c .)" -eq 1 ]; then
        CHOSEN=$matches
    else
        choose "$matches"
    fi
else
    choose "$(cat "$list")"
fi

licence=${CHOSEN%%$'\t'*}
family=${CHOSEN#*$'\t'}

# The files: the static/ folder when the family has one (the classic faces),
# the family's own .ttf files otherwise (a variable font). What lands is read
# back from the files themselves: the folder name is not the family name a
# template writes (open-sans holds "Open Sans").
entries=$(curl -fsSL "$api/$licence/$family") || die "$family: not in the catalogue any more."
if [ "$(printf '%s\n' "$entries" | jq -r '[.[] | select(.type == "dir" and .name == "static")] | length')" != "0" ]; then
    entries=$(curl -fsSL "$api/$licence/$family/static") || die "$family: its static folder could not be read."
fi
files=$(printf '%s\n' "$entries" | jq -r '.[] | select(.type == "file" and (.name | endswith(".ttf"))) | "\(.name)\t\(.download_url)"')
[ -n "$files" ] || die "$family: no .ttf file in $licence/$family."

dest=$HOME/.local/share/fonts/google/$family
install -d "$dest"
count=0
while IFS=$'\t' read -r name url; do
    curl -fsSL -o "$dest/$name" "$url"
    count=$((count + 1))
done <<< "$files"

fc-cache -f >/dev/null 2>&1 || true

landed=$(fc-scan --format '%{family[0]}\n' "$dest"/*.ttf 2>/dev/null | sort -u | paste -sd', ' || true)
echo "✅ ${landed:-$family}: $count file(s) -> $dest"
echo "   A template asks for it by that name - e.g. \\setmainfont{$(printf '%s' "${landed:-$family}" | cut -d, -f1)}."
