#!/usr/bin/env bash
# ==============================================================================
# THE ZSH PACK - WHAT IT INSTALLS AS ROOT
# ==============================================================================
# Run by the engine as WSL's own root, before install.sh - no password asked.
# The packages, the two third-party repositories they install from, and the
# system-side touches the socle needs; what it installs is read from
# pack.conf, beside this file - the same line remove.sh reads. Every step
# asks before it acts: on the built image everything here is already in place
# and the whole script is a quiet no-op.

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

# DEBIAN_FRONTEND, so that a package reconfigured on the way (tzdata and its
# continent question) never stops the install to ask something.
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update

# The two third-party repositories the image registers are the socle's too:
# gh and eza install from there. Each is registered only when its keyring is
# missing - on the built image both are already in place.
if [ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ] || [ ! -f /etc/apt/keyrings/gierens.gpg ]; then
    # install -d, not `mkdir -p -m`: with -p the -m only reaches the deepest
    # directory, which is exactly the one that must be world-readable.
    install -d -m 0755 /etc/apt/keyrings
    apt_install ca-certificates curl gnupg
fi
if [ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ]; then
    echo "Registering the GitHub CLI repository..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get -qq update
fi
if [ ! -f /etc/apt/keyrings/gierens.gpg ]; then
    echo "Registering the eza repository..."
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list > /dev/null
    apt-get -qq update
fi

apt_install "${packages[@]}"

# The UTF-8 locales exports.zsh points LANG at: generated here when the
# machine has never seen them - the built image has them from its own
# Dockerfile run, and locale-gen rewrites the same files anyway.
if command -v locale-gen >/dev/null 2>&1 && ! locale -a 2>/dev/null | grep -qi 'en_US.utf8'; then
    echo "Generating the UTF-8 locales..."
    locale-gen en_US.UTF-8 fr_FR.UTF-8 > /dev/null
fi

# fd and bat wear their Debian names (fdfind, batcat), and the socle calls
# them by those; the short names are for the hand. The same links the image
# makes, with the same conditions.
if command -v fdfind >/dev/null 2>&1 && [ ! -e /usr/local/bin/fd ]; then
    ln -s "$(command -v fdfind)" /usr/local/bin/fd
fi
if command -v batcat >/dev/null 2>&1 && [ ! -e /usr/local/bin/bat ]; then
    ln -s "$(command -v batcat)" /usr/local/bin/bat
fi

# dpkg may have shipped the fzf examples compressed - the omz plugin sources
# them, and the bindings are gone while they are. The image guarantees the
# same thing the same way.
if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh.gz ]; then
    gunzip -f /usr/share/doc/fzf/examples/key-bindings.zsh.gz
fi

# The skeleton, for the accounts that come after this one: the image bakes
# the same files into /etc/skel. A file already there is someone's - created
# only when missing, never rewritten.
if [ -d /etc/skel ]; then
    if [ ! -e /etc/skel/.zshenv ]; then
        # The single quotes are the point: this line goes into the file as
        # written, and the variable must expand in the login shell, not here.
        # shellcheck disable=SC2016
        printf '%s\n%s\n' 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' 'skip_global_compinit=1' > /etc/skel/.zshenv
    fi
    if [ ! -e /etc/skel/.config/zsh ]; then
        mkdir -p /etc/skel/.config/zsh
        cp -r "$here/config/." /etc/skel/.config/zsh/
    fi
    mkdir -p /etc/skel/.local/state/zsh /etc/skel/.cache/zsh
fi
