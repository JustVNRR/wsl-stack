#!/usr/bin/env bash
# ==============================================================================
# THE WEB PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added to the system leaves it, and only that. A package another
# installed pack still claims stays where it is. Never a library (apt would
# take its dependents), and no autoremove here - remove_pack runs the cleanup
# that follows.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

# sudo's own prompt has no trailing newline, and the line-based capture
# behind wsl.exe only showed whole lines: the question stayed invisible and
# the call waited forever. This prompt ends its line, so it shows.
sudo_prompt=$(printf '[sudo] password:\n')
declared=$(sed -n 's/^PACK_PACKAGES *:=[[:space:]]*//p' "$here/pack.conf")

if [ -z "$declared" ]; then
    echo "No PACK_PACKAGES found in $here/pack.conf" >&2
    exit 1
fi

# Is this package claimed by another pack that is still installed?
claimed_elsewhere() {
    grep -rl --include=pack.conf --include=install.sh -- "$1" "$HOME/.config/packs" 2>/dev/null |
        grep -qv "^${here}/"
}

echo "Taking the tunnel down, and removing its boot hook..."
"$here/bin/vpn.sh" hook off
"$here/bin/vpn.sh" down

echo "Removing the tunnel and the browser..."
for package in $declared; do
    if claimed_elsewhere "$package"; then
        echo "$package: another installed pack claims it - left in place."
        continue
    fi
    if [ "$package" = openresolv ]; then
        # No candidate in Ubuntu 24.04: it came from Debian's package.
        sudo -p "$sudo_prompt" dpkg -r openresolv
        continue
    fi
    sudo -p "$sudo_prompt" apt-get remove -y "$package"
done

# Libraries installed beside the browser: marked automatic, they become
# orphans for the cleanup remove_pack runs next.
echo "Leaving the browser's decoder and its sound client to the cleanup that follows..."
sudo -p "$sudo_prompt" apt-mark auto libavcodec60 libpulse0 2>/dev/null || true

# What the pack wrote in the browser's directory: the sound preference, and the
# privacy link with the file it points at.
echo "Removing the sound preference and the privacy link..."
sudo -p "$sudo_prompt" rm -f /usr/lib/firefox/defaults/pref/wslg-audio.js \
           /usr/lib/firefox/defaults/pref/fox-privacy.js
rm -f "$HOME/.config/fox-privacy.js"

echo "Removing Mozilla's repository..."
sudo -p "$sudo_prompt" rm -f /etc/apt/sources.list.d/mozilla.list \
           /etc/apt/preferences.d/mozilla \
           /etc/apt/preferences.d/firefox-no-snap \
           /etc/apt/keyrings/packages.mozilla.org.asc

# Regenerated at every mount - not a file of the user's.
echo "Removing the profile the pack generated..."
sudo -p "$sudo_prompt" rm -f /etc/wireguard/vpn.conf

echo "The tunnel and the browser are gone, and Mozilla's repository with them."
echo "Left alone: your servers (~/.config/vpn), the VPN_* lines in .env.global,"
echo "   the /etc/wireguard profiles an older install left, generateResolvConf in"
echo "   /etc/wsl.conf, and your Firefox profile (~/.mozilla)."
echo "systemd-resolved was removed to make room for openresolv:"
echo "   sudo apt install systemd-resolved    puts it back."
