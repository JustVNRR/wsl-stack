#!/usr/bin/env bash
# ==============================================================================
# FIREFOX - THE PRIVACY SETS - WHAT THE LAUNCHERS AND THE TARGETS CALL
# ==============================================================================
# Two profiles live beside this script, fox-privacy-light.js and
# fox-privacy-strict.js (contents: docs/fox.md). One is ever in place.
#
# Firefox reads defaults from /usr/lib/firefox/defaults/pref: that path is a
# LINK to ~/.config/fox-privacy.js, a file of the user's own - so choosing a
# profile writes nothing privileged. Only the link (once) and `off` go
# through sudo. Every profile is a file of DEFAULTS: about:config wins.

set -euo pipefail

# FOX_PREF_FILE is what a test points at a stand-in copy.
PREF_FILE=${FOX_PREF_FILE:-/usr/lib/firefox/defaults/pref/fox-privacy.js}
PREF_DIR=$(dirname "$PREF_FILE")
SLOT=$HOME/.config/fox-privacy.js

# The profiles themselves, beside this script in the pack.
here=$(cd "$(dirname "$0")" && pwd)

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Root already? sudo would be an indirection too many.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# The link, pointing at the slot. Answered without any sudo first: a launch
# where it is already right must not cost a password. `ln -sfn` also replaces
# the plain file of the pack's first shape - the migration.
ensure_link() {
    [ -d "$PREF_DIR" ] ||
        die "no $PREF_DIR: Firefox is not installed here - it arrives from Windows (.\wsl.ps1 add_pack)."
    if [ -L "$PREF_FILE" ] && [ "$(readlink -- "$PREF_FILE")" = "$SLOT" ]; then
        return 0
    fi
    as_root ln -sfn "$SLOT" "$PREF_FILE" ||
        die "the link could not be written to $PREF_FILE"
    if [ "$(readlink -- "$PREF_FILE" 2>/dev/null)" != "$SLOT" ]; then
        die "the link at $PREF_FILE does not point at $SLOT"
    fi
}

# One of the two profiles, in the slot. Copies only when the slot holds
# something else; answers 0 when it changed something, 1 when it held it.
#
# Every write is checked (put_set runs inside `if`, where bash suspends
# `set -e` - an unchecked cp that failed would be reported as done).
put_set() {
    local src=$here/../fox-privacy-$1.js
    [ -f "$src" ] ||
        die "no $src: the pack's copy of the $1 profile is missing - put the pack's folder back (.\wsl.ps1 add_pack)."
    ensure_link
    if [ -f "$SLOT" ] && cmp -s "$src" "$SLOT"; then
        return 1
    fi
    install -d "$(dirname "$SLOT")"
    cp "$src" "$SLOT" ||
        die "the $1 profile could not be written to $SLOT"
    cmp -s "$src" "$SLOT" ||
        die "the $1 profile did not survive the write to $SLOT"
    return 0
}

# What the launchers call: silent when nothing changes, one line when it does.
use() {
    if put_set "$1"; then
        printf 'The %s privacy profile is in place - Firefox reads it as it starts.\n' "$1"
    fi
}

cmd_on() {
    if put_set strict; then
        printf 'The privacy profile is in place: %s\n' "$SLOT"
    else
        printf 'The privacy profile is in place.\n'
    fi
}

cmd_off() {
    if [ ! -e "$PREF_FILE" ] && [ ! -e "$SLOT" ]; then
        printf 'Nothing to remove: the privacy profile is not in place.\n'
        return 0
    fi

    as_root rm -f "$PREF_FILE"
    rm -f "$SLOT"

    printf 'The privacy profile is removed - Firefox is back to its own.\n'
    printf '   Close and reopen Firefox for that to take effect.\n'
}

case "${1:-}" in
on) cmd_on ;;
off) cmd_off ;;
light) use light ;;
strict) use strict ;;
*)
    cat <<'USAGE'
usage: fox.sh <command>

  light                 put the light privacy profile in place - what `fox`
                        runs at every launch; silent when nothing changes
  strict                put the strict profile in place - what `pfox` runs
  on                    the strict profile, and it says so (gmake fox_tweak_on)
  off                   take everything out - the browser's own defaults again
                        (gmake fox_tweak_off)

The first switch sets the link up (one sudo, once); after that a switch costs
no password. docs/fox.md tells what each profile holds.
USAGE
    exit 2
    ;;
esac
