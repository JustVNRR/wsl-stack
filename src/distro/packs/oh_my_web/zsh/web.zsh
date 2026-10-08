# ============================================================
# THE BROWSER
# ============================================================
# The pack's shell file, read where it lives (~/.config/packs/oh_my_web/zsh/web.zsh).
# `fox` opens the light privacy profile, `pfox` the strict one in a private
# window, with the check page first (docs/fox.md).

# X11, not Wayland: WSLg announces Wayland, and that path misbehaves under WSL.
# Ask for it back for one call: `MOZ_ENABLE_WAYLAND=1 fox`.
export MOZ_ENABLE_WAYLAND=0

# The pack's root, from this file's own path - %x is where a function here was
# defined (inside one, $0 is the function's name).
PACK=${${(%):-%x}:A:h:h}
FOX_SH=$PACK/bin/fox.sh

# What both launchers end on. No session bus in the image, and Firefox's first
# window never opens without one: the first launch of a shell starts it.
_fox_launch() {
    if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]] && command -v dbus-launch >/dev/null 2>&1; then
        # dbus refuses WSLg's runtime directory (world-writable); give this
        # call one of its own. The shell keeps WSLg's - Wayland and the sound
        # go through it.
        install -d -m 0700 "$HOME/.run"
        eval "$(XDG_RUNTIME_DIR="$HOME/.run" dbus-launch --sh-syntax)"
    fi
    firefox "$@"
}

# fox opens on the light profile - and puts it back after a strict visit.
fox() {
    "$FOX_SH" light || return
    _fox_launch "$@"
}

# pfox opens the private window on the strict profile, check page first (the
# profile and the resolver travel in its fragment). The switch counts at the
# next start: with Firefox already running it would be silently wrong - refused.
pfox() {
    if pgrep -x firefox >/dev/null 2>&1; then
        print -u2 "Firefox is already running - close it, then run pfox again (the profile is read when Firefox starts)."
        return 1
    fi
    "$FOX_SH" strict || return
    local dns
    dns=$(awk '/^[[:space:]]*nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null)
    _fox_launch --private-window "file://$PACK/privacy-check.html#strict;dns=$dns" "$@"
}
