#!/usr/bin/env bash
# ==============================================================================
# THE TUNNEL - WHAT THE gmake TARGETS AND THE BOOT HOOK CALL
# ==============================================================================
# State lives in three files:
#   ~/.config/vpn/servers.json        the servers: keys, DNS, MTU (the user's)
#   ~/.config/zsh/gmake/.env.global   VPN_PROFILE, VPN_KILL_SWITCH, VPN_MTU, BASE_DNS
#   /etc/wireguard/vpn.conf           generated from the two above before every
#                                     mount; never edited by hand
# bin/vpn-boot.sh reads through this same file, so the profile is never stale.

set -euo pipefail

WG_DIR=/etc/wireguard
IFACE=vpn
CONF=$WG_DIR/$IFACE.conf
BOOT_SCRIPT=/usr/local/sbin/web-vpn-boot
BOOT_LOG=/var/log/web-vpn.log
HOOK="command=$BOOT_SCRIPT"
WSLCONF=/etc/wsl.conf

here=$(cd "$(dirname "$0")" && pwd)
SAMPLE=$here/../vpn.servers.sample

# $HOME is the instance's user: a shell sets it, the boot hook hands it over.
SERVERS=$HOME/.config/vpn/servers.json
GLOBAL_ENV=$HOME/.config/zsh/gmake/.env.global

# The automatic start: a marker file - the boot hook also runs for the
# resolver alone, so its presence is what means "raise the tunnel".
AUTO_FLAG=$HOME/.config/vpn/auto

# The rules carry this label, so any instance can find and sweep them - scoped
# to this distro's cgroup path: the firewall is shared by every distro.
KS_COMMENT='wsl-stack kill switch'

# This distro's root in WSL's cgroup tree: the id is renumbered at every start,
# and matching the root covers the sessions (iptables' --path covers
# sub-folders). Empty when WSL says nothing usable - no rule is laid then.
# CGROUP_ROOT is what a test points at a stand-in tree.
CGROUP_ROOT=${CGROUP_ROOT:-/proc}
cgroup_distro_path() {
    local p=
    p=$(sed -n 's|^[0-9]*::\(/wsl-user/distro-[0-9]*\).*$|\1|p' "$CGROUP_ROOT/self/cgroup" 2>/dev/null | head -n 1 || true)
    if [ -z "$p" ]; then
        p=$(sed -n 's|^[0-9]*::\(/wsl-user/distro-[0-9]*\).*$|\1|p' "$CGROUP_ROOT"/[0-9]*/cgroup 2>/dev/null | head -n 1 || true)
    fi
    printf '%s\n' "$p"
}

# The same words for -I and -D (a -D that differs by one match deletes
# nothing); the $( ) is wg-quick's - expanded when the tunnel comes up, not
# here.
ks_rule() { # $1: -I or -D, $2: this instance's cgroup path, $3: the verb's tail
    # shellcheck disable=SC2016
    printf 'iptables %s OUTPUT ! -o %%i -m cgroup --path "%s" -m mark ! --mark $(wg show %%i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment "%s" -j REJECT%s; ip6tables %s OUTPUT ! -o %%i -m cgroup --path "%s" -m mark ! --mark $(wg show %%i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment "%s" -j REJECT%s' \
        "$1" "$2" "$KS_COMMENT" "$3" "$1" "$2" "$KS_COMMENT" "$3"
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# The messages: the shared library, when the image carries it, replaces this
# fallback - an instance built before it keeps a plain sentence.
hint() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# Just root? sudo would be an indirection too many (the boot hook runs as root).
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Remove every labelled rule still in the kernel; answers how many went. By
# label only: never by rebuilding a spec - the fwmark dies with the interface -
# and never by flushing the chain: Docker's rules live there.
ks_sweep() {
    local fam='' num='' removed=0
    for fam in iptables ip6tables; do
        while :; do
            num=$(as_root "$fam" -L OUTPUT --line-numbers -n 2>/dev/null | grep -m 1 -F -- "$KS_COMMENT" | awk '{print $1}')
            [ -n "$num" ] || break
            as_root "$fam" -D OUTPUT "$num" 2>/dev/null || break
            removed=$((removed + 1))
        done
    done
    printf '%s' "$removed"
}

ks_swept_message() {
    local word=rules
    if [ "$1" -eq 1 ]; then
        word=rule
    fi
    printf 'Removed %s kill-switch %s still in the kernel.\n' "$1" "$word"
}

# The files below are the user's: refuse root's own home (the boot hook sets HOME).
if [ "$(id -u)" -eq 0 ] && [ "${HOME:-}" = /root ]; then
    die "this reads your own files: run it as yourself (gmake vpn_up), not through sudo."
fi

# --- the JSON of servers ------------------------------------------------------

# jq reads it: a broken file gets a line number, not a wrong value.
json_ok() {
    [ -f "$SERVERS" ] && jq -e . "$SERVERS" > /dev/null 2>&1
}

# Every id, in the file's order.
ids() {
    [ -f "$SERVERS" ] || return 0
    jq -r '(.servers // [])[] | .id // empty' "$SERVERS" 2>/dev/null || true
}

# One field of one entry; the peer's fields are one level down.
field() {
    jq -r --arg id "$1" --arg k "$2" '(.servers // [])[] | select(.id == $id) | .[$k] // empty' "$SERVERS" 2>/dev/null || true
}

peer_field() {
    jq -r --arg id "$1" --arg k "$2" '(.servers // [])[] | select(.id == $id) | (.peer // {})[$k] // empty' "$SERVERS" 2>/dev/null || true
}

# How many entries carry that id - exactly one is the only usable answer.
entries() {
    jq -r --arg id "$1" '[ (.servers // [])[] | select(.id == $id) ] | length' "$SERVERS" 2>/dev/null || printf '0'
}

# Letters, digits, dot, dash, underscore - an id goes into .env.global.
VALID_ID='^[A-Za-z0-9._-]+$'
valid_id() {
    printf '%s' "$1" | grep -qE "$VALID_ID"
}

# After the editor closed: every id usable, each of them once.
check_ids() {
    local id seen=
    while read -r id; do
        [ -n "$id" ] || continue
        if ! valid_id "$id"; then
            printf 'id "%s" is not usable: letters, digits, dot, dash and underscore only (it goes into .env.global).\n' "$id" >&2
            return 1
        fi
        case " $seen " in
        *" $id "*)
            printf 'id "%s" appears twice - one entry per server.\n' "$id" >&2
            return 1
            ;;
        esac
        seen="$seen $id"
    done < <(ids)
    return 0
}

# --- the two variables --------------------------------------------------------

# From .env.global, never the exported copy: make exports the value from before
# the line this run is about to write.
env_var() {
    local name=$1 line
    [ -r "$GLOBAL_ENV" ] || return 0
    line=$(grep -E "^[[:space:]]*$name=" "$GLOBAL_ENV" | tail -n 1 || true)
    printf '%s\n' "${line#*=}"
}

server_var() {
    env_var VPN_PROFILE
}

ks_on() {
    case "$(env_var VPN_KILL_SWITCH)" in
    true | TRUE | True | yes | 1) return 0 ;;
    *) return 1 ;;
    esac
}

# What the variable asks vs what the kernel holds - the two can disagree. The
# rules are counted by label; "here" is this distro's path.
ks_line() {
    local state rules total here path word
    if [ ! -r "$GLOBAL_ENV" ]; then
        printf 'off (no %s yet - gmake env_global_enable builds it)\n' "$GLOBAL_ENV"
        return 0
    fi
    if ks_on; then
        state=on
    else
        state="off ($(env_var VPN_KILL_SWITCH))"
    fi

    rules=$(as_root sh -c 'iptables -S OUTPUT 2>/dev/null; ip6tables -S OUTPUT 2>/dev/null' | grep -F -- "$KS_COMMENT" || true)
    total=$(printf '%s\n' "$rules" | grep -c . || true)
    path=$(cgroup_distro_path)
    here=0
    if [ -n "$path" ]; then
        here=$(printf '%s\n' "$rules" | grep -c -F -- "--path \"$path\"" || true)
    fi

    if [ "$total" -eq 0 ]; then
        printf '%s - no rule in the kernel\n' "$state"
    elif [ "$here" -gt 0 ]; then
        word=rules
        if [ "$here" -eq 1 ]; then
            word=rule
        fi
        printf '%s - %s %s in the kernel, this instance\n' "$state" "$here" "$word"
    else
        word=rules
        if [ "$total" -eq 1 ]; then
            word=rule
        fi
        printf '%s - %s %s in the kernel, another instance\n' "$state" "$total" "$word"
    fi
}

# One line of .env.global: replaced where it is, appended when it is not there
# yet. The value is a checked id, or the literal true/false.
write_env() {
    local name=$1 value=$2
    [ -f "$GLOBAL_ENV" ] || die "no $GLOBAL_ENV yet - 'gmake env_global_enable' builds it from the samples."
    if grep -qE "^[[:space:]]*$name=" "$GLOBAL_ENV"; then
        sed -i -E "s|^[[:space:]]*$name=.*|$name=$value|" "$GLOBAL_ENV"
    else
        printf '\n%s=%s\n' "$name" "$value" >> "$GLOBAL_ENV"
    fi
    printf '\nWrote %s=%s (%s)\n' "$name" "$value" "$GLOBAL_ENV"
}

# --- the tunnel ---------------------------------------------------------------

# Root owns the profile (600 in 0700): ask through sudo, like its reads.
conf_present() {
    as_root test -f "$CONF"
}

is_up() {
    [ "$(as_root wg show interfaces 2>/dev/null | head -n 1)" = "$IFACE" ]
}

# wg-quick narrates every step; keep it for the day it fails.
run_quiet() {
    local out
    if ! out=$("$@" 2>&1); then
        printf '%s\n' "$out" >&2
        return 1
    fi
}

# The profile's "# Server:" line; empty when no tunnel is up.
server_in_use() {
    is_up || return 0
    as_root sed -n 's/^# Server: \([^ ]*\).*/\1/p' "$CONF" 2>/dev/null | head -n 1 || true
}

# A survivor of our own last start must be re-raised - its DNS registration and
# its rules died with that start. A neighbour's is left alone: the live public
# key against servers.json's tells them apart.
owns() {
    local live key ours
    live=$(as_root wg show "$IFACE" public-key 2>/dev/null || true)
    [ -n "$live" ] || return 1
    [ -f "$SERVERS" ] || return 1
    while read -r key; do
        [ -n "$key" ] || continue
        ours=$(printf '%s\n' "$key" | wg pubkey 2>/dev/null || true)
        if [ "$ours" = "$live" ]; then
            return 0
        fi
    done < <(jq -r '(.servers // [])[] | .private_key // empty' "$SERVERS" 2>/dev/null || true)
    return 1
}

# The handshake comes after the interface: wait for it before asking the exit IP.
wait_handshake() {
    local stamp
    for _ in $(seq 1 10); do
        stamp=$(as_root wg show "$IFACE" latest-handshakes 2>/dev/null | awk 'NR == 1 { print $2 }')
        [ -n "$stamp" ] && [ "$stamp" != 0 ] && return 0
        sleep 1
    done
    return 1
}

# fzf menu, like the other pickers; a server can also be named on the command line.
pick() {
    local list choice
    list=$(ids)
    [ -n "$list" ] || die "no server in $SERVERS yet - gmake vpn_edit_profiles opens it."
    if ! choice=$(printf '%s\n' "$list" | fzf --prompt="$1 > " --info=inline --layout=reverse); then
        die "no server chosen - a menu needs a terminal. Name one: gmake <target> VPN_PROFILE=<id>"
    fi
    [ -n "$choice" ] || die "no server chosen."
    printf '%s\n' "$choice"
}

# Every path that raises the tunnel goes through here, the boot hook included;
# edits made in the generated file are lost at the next mount.
compose() {
    local id=$1 private address pub endpoint allowed dns mtu keepalive pair name value ks_path

    [ -n "$id" ] || die "no server named: gmake vpn_server picks the default, gmake vpn_up_from_list shows the menu."
    if ! valid_id "$id"; then
        die "'$id' cannot be a server id: letters, digits, dot, dash and underscore only."
    fi
    [ -f "$SERVERS" ] || die "no $SERVERS yet - gmake vpn_edit_profiles creates it from the sample."
    if ! json_ok; then
        die "$SERVERS is not valid JSON: $(jq . "$SERVERS" 2>&1 | head -n 1)"
    fi
    case "$(entries "$id")" in
    1) ;;
    0) die "no server '$id' in $SERVERS. It holds: $(ids | paste -sd' ' -). gmake vpn_edit_profiles opens it." ;;
    *) die "'$id' appears more than once in $SERVERS - one entry per server. gmake vpn_edit_profiles opens it." ;;
    esac

    private=$(field "$id" private_key)
    address=$(field "$id" address)
    pub=$(peer_field "$id" public_key)
    endpoint=$(peer_field "$id" endpoint)
    allowed=$(peer_field "$id" allowed_ips)
    dns=$(field "$id" DNS)
    mtu=$(field "$id" mtu)
    keepalive=$(peer_field "$id" persistent_keepalive)
    [ -n "$mtu" ] || mtu=$(env_var VPN_MTU)
    [ -n "$mtu" ] || die "VPN_MTU is not set in $GLOBAL_ENV - gmake env_global_enable writes it from the sample."
    # A half-filled entry is refused here, before wg-quick answers "Key is not
    # the correct length" - words that say nothing about this file. The
    # sample's PASTE- placeholders are not values either.
    for pair in "DNS=$dns" "private_key=$private" "address=$address" "peer.public_key=$pub" \
        "peer.endpoint=$endpoint" "peer.allowed_ips=$allowed"; do
        name=${pair%%=*}
        value=${pair#*=}
        if [ -z "$value" ] || [ "${value#PASTE-}" != "$value" ]; then
            die "server '$id': $name is missing in $SERVERS. gmake vpn_edit_profiles fills it in."
        fi
    done

    # Root, mode 600 (it carries the private key), content on stdin so no copy
    # of the key lands anywhere else. 0700 for the folder.
    as_root install -d -m 0700 "$WG_DIR"
    as_root install -m 600 /dev/null "$CONF"
    {
        printf '# Generated by the web pack from %s\n' "$SERVERS"
        printf '# Server: %s - do not edit this file: gmake vpn_up rewrites it.\n' "$id"
        printf '\n[Interface]\n'
        printf 'PrivateKey = %s\n' "$private"
        printf 'Address    = %s\n' "$address"
        printf 'DNS        = %s\n' "$dns"
        printf 'MTU        = %s\n' "$mtu"
        if ks_on; then
            ks_path=$(cgroup_distro_path)
            if [ -n "$ks_path" ]; then
                printf 'PostUp     = %s\n' "$(ks_rule -I "$ks_path" '')"
                printf 'PreDown    = %s\n' "$(ks_rule -D "$ks_path" ' || true')"
            else
                printf 'kill switch on, but this instance has no /wsl-user/distro-* place: no rule added.\n' >&2
            fi
        fi
        printf '\n[Peer]\n'
        printf 'PublicKey  = %s\n' "$pub"
        printf 'AllowedIPs = %s\n' "$allowed"
        printf 'Endpoint   = %s\n' "$endpoint"
        # Only when the entry asks for one.
        [ -z "$keepalive" ] || printf 'PersistentKeepalive = %s\n' "$keepalive"
    } | as_root tee "$CONF" > /dev/null
}

# openresolv's symlink and the BASE_DNS nameserver: what the instance resolves
# with when no tunnel is up.
write_base_resolver() {
    local base
    base=$(env_var BASE_DNS)
    [ -n "$base" ] || die "BASE_DNS is not set in $GLOBAL_ENV - gmake env_global_enable writes it from the sample."
    as_root ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf 2>/dev/null || true
    printf 'nameserver %s\n' "$base" | as_root resolvconf -a wsl.base
}

# Raise the tunnel: compose first (the profile is never stale), take down what
# is there, sweep leftovers, mount.
cmd_up() {
    local swept

    if ip link show dev "$IFACE" >/dev/null 2>&1 && ! conf_present; then
        as_root ip link delete dev "$IFACE" 2>/dev/null || true
    fi

    local wanted=${1:-}

    if [ -z "$wanted" ]; then
        if [ ! -f "$GLOBAL_ENV" ]; then
            die "no $GLOBAL_ENV yet - 'gmake env_global_enable' builds it from the samples."
        fi
        wanted=$(server_var)
        [ -n "$wanted" ] || die "VPN_PROFILE is not set in $GLOBAL_ENV - gmake vpn_server picks the server, gmake vpn_up_from_list shows the menu."
    fi

    if is_up; then
        # Ours to re-raise; a neighbour's is not ours to take down.
        owns ||
            die "the vpn interface is up with another instance's configuration - left alone. Take it down from there, or: sudo ip link delete $IFACE"
        run_quiet as_root wg-quick down "$IFACE" ||
            die "the tunnel was up and would not come down - the lines above are wg-quick's own."
    fi
    # A leftover rule carries an older fwmark and would reject this mount.
    swept=$(ks_sweep)
    if [ "$swept" -gt 0 ]; then
        ks_swept_message "$swept"
    fi
    write_base_resolver
    compose "$wanted"
    run_quiet as_root wg-quick up "$IFACE" ||
        die "the tunnel did not come up - the lines above are wg-quick's own."
    wait_handshake ||
        printf 'the server has not answered yet - the exit IP may take a moment.\n' >&2

    cmd_status
}

cmd_up_from_list() {
    local wanted
    wanted=$(pick "VPN server")
    cmd_up "$wanted"
}

cmd_down() {
    local swept
    if ! is_up; then
        printf 'no tunnel is up.\n'
        swept=$(ks_sweep)
        if [ "$swept" -gt 0 ]; then
            ks_swept_message "$swept"
        fi
        if [ ! -e /etc/resolv.conf ]; then
            write_base_resolver
        fi
        cmd_status
        return 0
    fi

    if ! conf_present; then
        # No profile here: the interface belongs to another instance (or an
        # earlier start) - leave it up, put the rules and resolver back.
        printf '%s missing: interface left up (raised elsewhere); rules and resolver put back.\n' "$CONF"
        swept=$(ks_sweep)
        if [ "$swept" -gt 0 ]; then
            ks_swept_message "$swept"
        fi
        as_root resolvconf -d "$IFACE" 2>/dev/null || true
        write_base_resolver
        cmd_status
        return 0
    fi

    run_quiet as_root wg-quick down "$IFACE" ||
        die "the tunnel did not come down - the lines above are wg-quick's own."
    # The PreDown took this mount's rules; the sweep takes every other with the label.
    swept=$(ks_sweep)
    if [ "$swept" -gt 0 ]; then
        ks_swept_message "$swept"
    fi
    cmd_status
}

# Write VPN_PROFILE; switch to it right away when a tunnel is up.
cmd_server() {
    local wanted=${1:-}

    if [ -z "$wanted" ]; then
        wanted=$(pick "The server the distro starts with")
    fi
    if ! valid_id "$wanted"; then
        die "'$wanted' cannot be a server id: letters, digits, dot, dash and underscore only."
    fi
    if [ -f "$SERVERS" ] && [ "$(entries "$wanted")" != 1 ]; then
        die "no server '$wanted' in $SERVERS. It holds: $(ids | paste -sd' ' -). Run gmake vpn_edit_profiles to open it."
    fi

    write_env VPN_PROFILE "$wanted"

    # The value this process was started with is the one from before the line above.
    if is_up; then
        printf '\nSwitching to %s now.\n' "$wanted"
        cmd_up "$wanted"
    else
        printf 'Run gmake vpn_up or restart your distro to use this profile.\n'
    fi
    if ! auto_flag_present; then
        printf 'Run gmake vpn_auto_on to turn on automatic vpn activation.\n'
    fi
}

# One line of .env.global; remount when a tunnel this instance can remount is up.
cmd_kill_switch() {
    local what=${1:-} value wanted swept

    case "$what" in
    on) value=true ;;
    off) value=false ;;
    *) die "kill_switch takes 'on' or 'off'" ;;
    esac

    # Preflighted before the write: a failure after it would read as half-done.
    # Only a tunnel with a profile here is remounted - always this instance's.
    if is_up && conf_present; then
        wanted=$(server_var)
        [ "$(entries "$wanted")" = 1 ] ||
            die "the tunnel is up, and VPN_PROFILE names '$wanted', which $SERVERS does not hold any more. gmake vpn_server picks one, then try this again."
    fi

    write_env VPN_KILL_SWITCH "$value"

    if [ "$value" = false ]; then
        if is_up && conf_present; then
            printf 'Remounting the tunnel on %s, so this is true now.\n' "$wanted"
            cmd_up "$wanted"
        fi
        swept=$(ks_sweep)
        if [ "$swept" -gt 0 ]; then
            ks_swept_message "$swept"
        elif ! is_up || ! conf_present; then
            printf 'It applies to the next mount.\n'
        fi
    elif is_up && conf_present; then
        printf 'Remounting the tunnel on %s, so this is true now.\n' "$wanted"
        cmd_up "$wanted"
    else
        printf 'It applies to the next mount.\n'
    fi
}

cmd_edit_profiles() {
    local editor

    if [ ! -f "$SERVERS" ]; then
        install -d -m 0700 "$(dirname "$SERVERS")"
        install -m 600 "$SAMPLE" "$SERVERS"
        printf '%s was created from the package sample - fill in your keys.\n' "$SERVERS"
    fi
    if ! json_ok; then
        die "$SERVERS does not parse, and this will not open a broken file: $(jq . "$SERVERS" 2>&1 | head -n 1)"
    fi

    # $EDITOR (one command, no arguments) or nano.
    editor=${EDITOR:-nano}
    eval "$editor \"\$SERVERS\""

    # Nothing is read from the file until it parses and the ids hold.
    if ! json_ok; then
        printf '%s does not parse any more: %s\n' "$SERVERS" "$(jq . "$SERVERS" 2>&1 | head -n 1)" >&2
        printf '   gmake vpn_edit_profiles opens it again - nothing is read from it until it does.\n' >&2
        return 1
    fi
    check_ids || return 1
    printf '%s: %s\n' "$SERVERS" "$(ids | paste -sd' ' -)"

    # Then the server to use, straight away - only with a terminal (a script
    # runs this with EDITOR=true, and there is nothing to ask).
    if [ -t 0 ] && [ -t 1 ]; then
        cmd_server
    fi
}

# The [boot] command does two things: the resolver at every start (the hook);
# the tunnel only when the marker file vpn_auto_on writes is there.
auto_flag_present() {
    [ -f "$AUTO_FLAG" ]
}

hook_present() {
    as_root grep -qxF "$HOOK" "$WSLCONF" 2>/dev/null
}

# Idempotent: one copy of the script, one line under [boot] - /etc/wsl.conf
# also holds generateResolvConf.
hook_on() {
    as_root install -m 0755 "$here/vpn-boot.sh" "$BOOT_SCRIPT"
    if hook_present; then
        return 0
    fi
    if as_root grep -q '^\[boot\]' "$WSLCONF" 2>/dev/null; then
        as_root sed -i "\|^\[boot\]|a $HOOK" "$WSLCONF"
    else
        printf '\n[boot]\n%s\n' "$HOOK" | as_root tee -a "$WSLCONF" > /dev/null
    fi
    hook_present || die "the [boot] line could not be written to $WSLCONF"
}

hook_off() {
    rm -f "$AUTO_FLAG"
    if as_root test -f "$WSLCONF"; then
        as_root sed -i "\|^${HOOK}$|d" "$WSLCONF"
    fi
    as_root rm -f "$BOOT_SCRIPT"
}

cmd_auto() {
    case "${1:-}" in
    on)
        if [ ! -f "$GLOBAL_ENV" ]; then
            die "no $GLOBAL_ENV yet - 'gmake env_global_enable' builds it from the samples."
        fi
        [ -n "$(server_var)" ] ||
            die "VPN_PROFILE is not set in $GLOBAL_ENV - gmake vpn_server picks the server first."
        hook_on
        install -d -m 0700 "$(dirname "$AUTO_FLAG")"
        : > "$AUTO_FLAG"
        printf '\n'
        hint "Restart your instance for the changes to take effect."
        ;;
    off)
        rm -f "$AUTO_FLAG"
        printf 'The distro will not bring the tunnel up.\n'
        printf 'A tunnel that is up stays up - gmake vpn_down stops it.\n'
        ;;
    *)
        die "auto takes 'on' or 'off'"
        ;;
    esac
}

cmd_hook() {
    case "${1:-}" in
    on)
        hook_on
        printf 'The boot hook is installed: the base resolver is put back at each start.\n'
        ;;
    off)
        hook_off
        printf 'The boot hook is removed.\n'
        ;;
    *)
        die "hook takes 'on' or 'off'"
        ;;
    esac
}

# The boot hook's first move: the base resolver (/run is empty at each start).
cmd_base() {
    write_base_resolver
}

# A line of $1 dashes, for the frame below.
dashes() {
    printf '%*s' "$1" '' | tr ' ' '-'
}

# The block's lines. cmd_status captures them all to draw the frame at the
# widest line's width.
status_body() {
    local id count in_use ns exit_ip last

    if is_up && conf_present; then
        printf '   Tunnel      : up (%s)\n' "$IFACE"
    elif is_up; then
        printf '   Tunnel      : up (%s), no profile here - raised by another instance or an earlier start\n' "$IFACE"
    else
        printf '   Tunnel      : down\n'
    fi

    id=$(server_var)
    count=$(ids | wc -l)
    in_use=$(server_in_use)
    if [ ! -f "$SERVERS" ]; then
        printf '   Servers     : none (no %s - gmake vpn_edit_profiles creates it)\n' "$SERVERS"
    elif [ "$count" = 0 ]; then
        printf '   Servers     : none in %s - gmake vpn_edit_profiles opens it\n' "$SERVERS"
    else
        printf '   Servers     : %s in %s\n' "$count" "$SERVERS"
        if [ -n "$in_use" ] && [ "$in_use" != "$id" ] && [ -n "$id" ]; then
            # Up now and the next mount's server can differ (`vpn_up VPN_PROFILE=x`).
            printf '   Server      : %s - up now; VPN_PROFILE names %s\n' "$in_use" "$id"
        elif [ -n "$in_use" ]; then
            printf '   Server      : %s - up now, and what the next mount uses\n' "$in_use"
        elif [ -n "$id" ]; then
            printf '   Server      : %s (VPN_PROFILE)\n' "$id"
        else
            printf '   Server      : none named - gmake vpn_server picks one\n'
        fi
    fi

    printf '   Kill switch : %s\n' "$(ks_line)"

    # A missing /etc/resolv.conf is not a state this pack creates: say it, do
    # not fall over.
    if [ -r /etc/resolv.conf ]; then
        ns=$(sed -n 's/^nameserver[[:space:]]\+//p' /etc/resolv.conf 2>/dev/null | head -n 1 || true)
        printf '   DNS         : %s\n' "${ns:-none in /etc/resolv.conf}"
    else
        printf '   DNS         : no /etc/resolv.conf - nothing resolves a name\n'
    fi

    exit_ip=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || true)
    printf '   Exit IP     : %s\n' "${exit_ip:-unreachable}"

    if auto_flag_present; then
        printf '   Automatic launch : on\n'
    else
        printf '   Automatic launch : off (run gmake vpn_auto_on to turn it on)\n'
    fi

    last=$(as_root tail -n 1 "$BOOT_LOG" 2>/dev/null || true)
    [ -n "$last" ] && printf '   Last start  : %s\n' "$last"
    return 0
}

# Frame the block: borders and centred title at the body's width.
cmd_status() {
    local body width title='VPN status' left right

    body=$(status_body)
    width=$(printf '%s\n' "$body" | awk 'length > m { m = length } END { print m + 2 }')
    left=$(((width - ${#title} - 2) / 2))
    right=$((width - ${#title} - 2 - left))

    printf '\n'
    printf '%s\n' "$(dashes "$width")"
    printf '%s %s %s\n' "$(dashes "$left")" "$title" "$(dashes "$right")"
    printf '%s\n' "$(dashes "$width")"
    printf '%s\n' "$body"
    printf '%s\n\n' "$(dashes "$width")"
    return 0
}

case "${1:-}" in
status)
    shift
    cmd_status "$@"
    ;;
up)
    shift
    cmd_up "$@"
    ;;
up_from_list)
    shift
    cmd_up_from_list "$@"
    ;;
down)
    shift
    cmd_down "$@"
    ;;
server)
    shift
    cmd_server "$@"
    ;;
kill_switch)
    shift
    cmd_kill_switch "$@"
    ;;
edit_profiles)
    shift
    cmd_edit_profiles "$@"
    ;;
auto)
    shift
    cmd_auto "$@"
    ;;
hook)
    shift
    cmd_hook "$@"
    ;;
base)
    shift
    cmd_base "$@"
    ;;
owns)
    shift
    owns "$@"
    ;;
*)
    cat <<'USAGE'
usage: vpn.sh <command>

  status                tunnel, server, kill switch, DNS, exit IP, automatic launch
  up [id]               connect now (server VPN_PROFILE names, or the one given)
  up_from_list          connect now, picking the server in a menu
  down                  disconnect
  server [id]           the server the distro starts with (menu when no id)
  kill_switch on|off    the kill switch, with a remount; off also sweeps
  auto on|off           raise the tunnel when the distro starts
  hook on|off           the boot hook (the install and the removal drive it)
  base                  put the base resolver back (the hook's first move)
  owns                  is the up interface running one of our servers?
  edit_profiles         edit ~/.config/vpn/servers.json

gmake targets: vpn_status, vpn_up, vpn_up_from_list, vpn_down, vpn_server,
vpn_ks_on, vpn_ks_off, vpn_auto_on, vpn_auto_off, vpn_edit_profiles.
USAGE
    exit 2
    ;;
esac
