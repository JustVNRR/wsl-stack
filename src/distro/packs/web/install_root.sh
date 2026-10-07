#!/usr/bin/env bash
# ==============================================================================
# THE WEB PACK - WHAT IT INSTALLS AS ROOT
# ==============================================================================
# Run by install.sh as one sudo: everything here belongs to root. What it
# installs is read from pack.conf, beside this file - the same line remove.sh
# reads.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
declared=$(sed -n 's/^PACK_PACKAGES *:=[[:space:]]*//p' "$here/pack.conf")

if [ -z "$declared" ]; then
    echo "No PACK_PACKAGES found in $here/pack.conf" >&2
    exit 1
fi

# firefox is installed later (its repository comes first), and openresolv does
# not exist in Ubuntu 24.04 (Debian's package, pinned below): both would break
# the apt line.
packages=()
for package in $declared; do
    if [ "$package" != openresolv ] && [ "$package" != firefox ]; then
        packages+=("$package")
    fi
done
resolver_package=openresolv
resolver_url=http://ftp.debian.org/debian/pool/main/o/openresolv/openresolv_3.12.0-1_all.deb

# DEBIAN_FRONTEND: a package reconfigured on the way must not stop to ask.
export DEBIAN_FRONTEND=noninteractive

# The install, with a line at once and then one every 15 seconds while apt
# works in silence: a long wait must not look like a hang. One line per beat,
# because the run is streamed to the console line by line - an animated line
# would never show.
apt_install() {
    printf 'Installing... 0:00\n'
    apt-get -qq install -y --no-install-recommends "$@" > /dev/null &
    local apt_pid=$! i=0
    while kill -0 "$apt_pid" 2>/dev/null; do
        sleep 15
        i=$((i + 15))
        if kill -0 "$apt_pid" 2>/dev/null; then
            printf 'Installing... %d:%02d\n' "$((i / 60))" "$((i % 60))"
        fi
    done
    wait "$apt_pid" || return 1
}

# --- the tunnel -------------------------------------------------------------

# 1. systemd-resolved ships a resolvconf of its own; Debian's openresolv
#    refuses to install beside it.
if dpkg -s systemd-resolved >/dev/null 2>&1; then
    apt-get -qq remove -y systemd-resolved > /dev/null
fi

# 2. wireguard-tools, kmod (the module dies with 'wsl --shutdown' without
#    modprobe), iproute2 and iptables for wg-quick and the kill switch.
#    libavcodec60 and libpulse0 are libraries the browser loads at runtime:
#    never in PACK_PACKAGES, installed beside it on purpose.
apt-get -qq update
apt_install "${packages[@]}" libavcodec60 libpulse0

# 3. The resolver, from Debian's archive (no such package in Ubuntu 24.04).
resolver_deb=/tmp/$resolver_package.deb
wget -q "$resolver_url" -O "$resolver_deb"
dpkg -i "$resolver_deb" > /dev/null
rm -f "$resolver_deb"

# 4. WSL must stop rewriting /etc/resolv.conf at every start, or openresolv's
#    work is undone by the next boot. vpn.sh writes the file (the base, from
#    BASE_DNS) before every mount.
if grep -q '^[[:space:]]*generateResolvConf' /etc/wsl.conf 2>/dev/null; then
    sed -i 's/^[[:space:]]*generateResolvConf.*/generateResolvConf = false/' /etc/wsl.conf
else
    printf '\n[network]\ngenerateResolvConf = false\n' >> /etc/wsl.conf
fi

# --- the browser ------------------------------------------------------------

# 5. Mozilla's signing key, fingerprint checked. grep reads the whole stream:
#    with --quiet, gpg would take the SIGPIPE and pipefail would read it as a
#    bad key.
install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O /etc/apt/keyrings/packages.mozilla.org.asc
gpg --show-keys --with-colons /etc/apt/keyrings/packages.mozilla.org.asc |
    grep '^fpr:::::::::35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3:' > /dev/null || {
        echo "Mozilla's signing key is not the one this pack knows - nothing was installed."
        rm -f /etc/apt/keyrings/packages.mozilla.org.asc
        exit 1
    }

# 6. Their repository, and two pins: theirs above Ubuntu's, and Ubuntu's snap
#    stub below everything.
echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' > /etc/apt/sources.list.d/mozilla.list
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla
printf 'Package: firefox*\nPin: release o=Ubuntu*\nPin-Priority: -1\n' > /etc/apt/preferences.d/firefox-no-snap

apt-get -qq update
# --allow-downgrades: Ubuntu's stub carries an epoch (1:1snap1) and ranks
#    above Mozilla's package, so apt refuses the change without it.
apt_install --allow-downgrades firefox
