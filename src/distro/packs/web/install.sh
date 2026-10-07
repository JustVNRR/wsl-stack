#!/usr/bin/env bash
# ==============================================================================
# THE WEB PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies the pack's folder into ~/.config/packs/web, then
# runs this script from inside it, as the instance's own user.
#
# Firefox comes from Mozilla's own repository (Ubuntu's `firefox` is a snap
# stub), the tunnel is WireGuard over openresolv, and the servers land in
# ~/.config/vpn/servers.json - seeded here, or migrated from old
# /etc/wireguard profiles.
#
# The commands that need root are in install_root.sh, beside this file, and
# the engine runs it as root before this one starts.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

here=$(cd "$(dirname "$0")" && pwd)

# The root half ran before this script - the engine's call, as WSL's own
# root, ahead of the door. The sudo lines below pass through that door: it
# asks nothing, and this prompt ends its line, which is what would show if it
# ever asked.
sudo_prompt=$(printf '[sudo] password:\n')

# The boot hook, installed with the pack: it puts the base resolver back at
# each start. vpn_auto_on/off only decide whether it also raises the tunnel.
if ! bash "$here/bin/vpn.sh" hook on; then
    echo "The boot hook was not installed - run it by hand:"
    echo "   bash ~/.config/packs/web/bin/vpn.sh hook on"
fi

# The audio sandbox keeps the browser away from WSLg's sound socket; this
# default turns it off (about:config wins). remove.sh takes the file back.
pref_file=/usr/lib/firefox/defaults/pref/wslg-audio.js
if [ -d /usr/lib/firefox/defaults/pref ]; then
    sudo -p "$sudo_prompt" tee "$pref_file" > /dev/null <<'PREF'
// Set by the web pack: the sound of a WSLg window goes through PulseAudio, and
// the audio sandbox keeps the browser away from the socket WSLg serves. This is
// a default - a value set in about:config wins over it.
pref("media.cubeb.sandbox", false);
PREF
    sudo -p "$sudo_prompt" chmod 0644 "$pref_file"
    echo "The sound reaches WSLg (media.cubeb.sandbox off, as a default)."
else
    echo "No /usr/lib/firefox/defaults/pref: the sound was left alone."
fi

# The privacy link, and the light profile in place: one link in the browser's
# directory pointing at a file of the user's own - the launchers switch with no
# password. Best-effort, like the hook.
if ! bash "$here/bin/fox.sh" light; then
    echo "The privacy link was not set up - run it by hand:"
    echo "   bash ~/.config/packs/web/bin/fox.sh light"
fi

# The servers. The JSON is the user's: left alone when it exists; migrated from
# leftover /etc/wireguard profiles; the sample otherwise.
servers=$HOME/.config/vpn/servers.json
if [ -f "$servers" ]; then
    echo "$servers is already there - left untouched."
else
    # The sample is checked first: it would be the user's file from the first minute.
    jq -e . "$here/vpn.servers.sample" > /dev/null ||
        {
            echo "The pack's own sample of servers does not parse - nothing was written to $servers." >&2
            exit 1
        }
    if ! bash "$here/bin/vpn-migrate.sh" "$servers"; then
        echo "Nothing was migrated - the pack's sample is used instead."
    fi
    if [ ! -f "$servers" ]; then
        install -d -m 0700 "$(dirname "$servers")"
        install -m 600 "$here/vpn.servers.sample" "$servers"
        echo "$servers is waiting for your keys - the sample shows where each"
        echo "   value goes (the WireGuard configuration from your provider)."
        echo "   Then: gmake vpn_edit_profiles, gmake vpn_up."
    fi
fi

# The pack's variables, merged into the file the shell loads. Best-effort: the
# merge loads every installed pack's module, and a broken neighbour must not
# fail an install that worked.
if ! make -f "$HOME/.config/zsh/gmake/Makefile" env_global_enable; then
    echo "The variables were not merged - run 'gmake env_global_enable' yourself."
fi

success "Firefox is installed: 'fox' opens it on the light privacy settings, 'pfox' on the strict ones."
success "WireGuard is installed: gmake vpn_status   (servers first: gmake vpn_edit_profiles)"
if [ -L /etc/resolv.conf ] || grep -q 'generateResolvConf' /etc/wsl.conf 2>/dev/null; then
    echo "The DNS setting is read when the distro starts: restart it once"
    echo "   (.\wsl.ps1 restart, from Windows) before the tunnel manages /etc/resolv.conf."
fi
