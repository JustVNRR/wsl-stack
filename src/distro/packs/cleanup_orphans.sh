#!/bin/bash
# Run INSIDE an instance, after a pack's remove.sh has run and its folder is
# gone: take back the dependencies the pack brought and left behind.
#
# A dependency only goes when nothing can still need it, and the question is
# asked twice:
#
#   1. does any package apt knows about depend on it? `apt-get -s autoremove`
#      answers that - the packages it lists have no dependant left;
#
#   2. does anything OUTSIDE apt's graph link its libraries? apt cannot see
#      that, but `ldd` can: every executable and shared object living outside
#      apt (a venv, a tool under /usr/local, a hand-built binary) is asked what
#      it links, and `dpkg -S` says which package owns each answer.
#
# A hit on the second question changes everything: nothing is removed, and the
# file that would have broken is named.

set -uo pipefail

ORPHANS=/tmp/pack-orphans.txt
LINKS=/tmp/pack-links.txt

# --- 1. what apt itself would take ------------------------------------------
# apt prints the name WITH its architecture (`libtesseract5:amd64`) where
# `dpkg -S` gives it without: dropped here, once. Cut at the colon, not at the
# space - the suffix is glued to the name with a colon.
apt-get -s autoremove 2>/dev/null | sed -n 's/^Remv \([^ :]*\).*/\1/p' | sort -u > "$ORPHANS"
COUNT=$(wc -l < "$ORPHANS")

if [ "$COUNT" -eq 0 ]; then
    echo "    No dependency left behind - nothing to take back."
    exit 0
fi

# --- 2. what outside apt links the libraries of those packages --------------
# "elf-file library" pairs, one per line
: > "$LINKS"
find "$HOME/.local" "$HOME/projects" /usr/local /opt \
     -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null |
while read -r file; do
    head -c 4 "$file" 2>/dev/null | grep -q "$(printf '\177')ELF" || continue
    ldd "$file" 2>/dev/null | grep -oE '/[^[:space:]]+\.so[^[:space:]]*' |
        while read -r lib; do echo "$file $lib"; done
done | sort -u > "$LINKS"

# ldd answers with the loader's path (`/lib/...`), dpkg records what it
# installed (`/usr/lib/...`), and `dpkg -S` does not follow the /lib symlink
# between them. Hence three attempts: the path as given, its resolved path,
# then the file name alone - without them an empty owner and a nothing-to-find
# look identical.
owners_of() {
    local lib owners
    lib=$1
    owners=$(dpkg -S "$lib" 2>/dev/null | cut -d: -f1 | sort -u)
    if [ -z "$owners" ]; then
        owners=$(dpkg -S "$(readlink -f "$lib" 2>/dev/null)" 2>/dev/null | cut -d: -f1 | sort -u)
    fi
    if [ -z "$owners" ]; then
        owners=$(dpkg -S "*/$(basename "$lib")" 2>/dev/null | cut -d: -f1 | sort -u)
    fi
    printf '%s\n' "$owners"
}

# One line per file, not per library: the useful sentence is "this file stops
# the removal", not the twelve paths that prove it.
BROKEN=""
current=""
blockers=""
while read -r file lib; do
    if [ "$file" != "$current" ]; then
        # a new file: print what the previous one had accumulated
        if [ -n "$blockers" ]; then
            BROKEN="$BROKEN
    $current links $blockers"
        fi
        current=$file
        blockers=""
    fi
    for owner in $(owners_of "$lib"); do
        [ -z "$owner" ] && continue
        grep -qx "$owner" "$ORPHANS" || continue
        if ! grep -qx "$owner" <<< "$blockers"; then
            blockers="${blockers:+$blockers, }$owner"
        fi
    done
done < "$LINKS"
if [ -n "$blockers" ]; then
    BROKEN="$BROKEN
    $current links $blockers"
fi

if [ -n "$BROKEN" ]; then
    echo "    Kept in place: something outside apt still links what would go."
    printf '%s\n' "$BROKEN"
    echo "    Remove the package by hand if that program is gone."
    exit 0
fi

# --- 3. the weight, then the removal ----------------------------------------
TOTAL=0
while read -r package; do
    size=$(dpkg -s "$package" 2>/dev/null | sed -n 's/^Installed-Size: //p')
    TOTAL=$((TOTAL + ${size:-0}))
done < "$ORPHANS"

echo "    $COUNT dependencies nothing needs any more: $((TOTAL / 1024)) MB."
sudo apt-get autoremove -y

rm -f "$ORPHANS" "$LINKS"
