#!/usr/bin/env bash
# ==============================================================================
# WHAT WSL'S [boot] HOOK RUNS - THE RESOLVER, AND THE TUNNEL WHEN ASKED
# ==============================================================================
# Runs as root at each start of the distro, and does two separate things:
#   1. put the base resolver back - /etc/resolv.conf is openresolv's symlink
#      into /run, and /run is empty at every start;
#   2. raise the tunnel, only when the marker file (vpn_auto_on) is there.
# Which server, and whether there is a kill switch, are not decided here: it
# calls bin/vpn.sh as the instance's user, so this path and `gmake vpn_up` are
# the same code.
# It always exits 0 - holding the boot back would serve nothing. What it did
# goes to /var/log/web-vpn.log (vpn_status shows its last line).

set -u

LOG=/var/log/web-vpn.log
TRIES=6
WAIT=5
WSLCONF=/etc/wsl.conf

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"
}

# The instance's user. $HOME here is /root, so the home comes from
# /etc/wsl.conf ([user] default=) - or from the pack's own folder, when that
# names nobody.
home_of_user() {
    local user home
    user=$(sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*//p' "$WSLCONF" 2>/dev/null | head -n 1)
    if [ -n "$user" ]; then
        home=$(awk -F: -v u="$user" '$1 == u { print $6; exit }' /etc/passwd)
        if [ -n "$home" ] && [ -x "$home/.config/packs/oh_my_web/bin/vpn.sh" ]; then
            printf '%s\n' "$home"
            return 0
        fi
    fi
    for home in /home/*; do
        if [ -x "$home/.config/packs/oh_my_web/bin/vpn.sh" ]; then
            printf '%s\n' "$home"
            return 0
        fi
    done
    return 1
}

home=$(home_of_user) || {
    log "no home carries the oh_my_web pack - nothing was started."
    exit 0
}

# 1. The base resolver, tunnel or no tunnel.
if HOME="$home" "$home/.config/packs/oh_my_web/bin/vpn.sh" base >> "$LOG" 2>&1; then
    log "base resolver put back."
else
    log "the base resolver could not be put back - 'gmake vpn_down' will say more."
fi

# 2. The tunnel, only with the marker.
if [ ! -e "$home/.config/vpn/auto" ]; then
    exit 0
fi

# An interface that survived the last stop is raised again - its DNS
# registration and its rules died with that start; another instance's is left
# alone. The network may not be up yet either: hence the retries below.
if /usr/bin/wg show interfaces 2>/dev/null | grep -qx vpn; then
    if ! HOME="$home" "$home/.config/packs/oh_my_web/bin/vpn.sh" owns; then
        log "the vpn interface is up with another configuration - left alone."
        exit 0
    fi
    log "the tunnel survived the last stop - raising it again for this start."
fi

try=1
while [ "$try" -le "$TRIES" ]; do
    if HOME="$home" "$home/.config/packs/oh_my_web/bin/vpn.sh" up >> "$LOG" 2>&1; then
        log "the tunnel is up (attempt $try)."
        exit 0
    fi
    try=$((try + 1))
    [ "$try" -le "$TRIES" ] && sleep "$WAIT"
done

log "gave up after $TRIES attempts - 'gmake vpn_up' will say more."
exit 0
