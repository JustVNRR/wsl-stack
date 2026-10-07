#!/usr/bin/env bash
# ==============================================================================
# THE PANDOC PACK - WHAT IT INSTALLS AS ROOT
# ==============================================================================
# Run by the engine as WSL's own root, before install.sh - no password asked.
# The packages are root's business; what it installs is read from pack.conf,
# beside this file - the same line remove.sh reads.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
declared=$(sed -n 's/^PACK_PACKAGES *:=[[:space:]]*//p' "$here/pack.conf")

if [ -z "$declared" ]; then
    echo "No PACK_PACKAGES found in $here/pack.conf" >&2
    exit 1
fi

read -ra packages <<< "$declared"

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

# DEBIAN_FRONTEND, so that a package reconfigured on the way never stops the
# install to ask something.
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt_install "${packages[@]}"
