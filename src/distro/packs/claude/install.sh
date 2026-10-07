#!/usr/bin/env bash
# ==============================================================================
# THE CLAUDE PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/claude, then
# runs this script from inside it, as the instance's own user.
#
# Everything this script PRINTS is plain ASCII: it travels through wsl.exe to
# the Windows console, which reads those bytes in its own code page - an emoji
# or an em dash arrives there as garbage. 

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
hint() { printf '%s\n' "$*"; }
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# The sample is read from beside this file: the two travel together wherever
# the folder lands.
here=$(cd "$(dirname "$0")" && pwd)

# From a shell that has not read the zsh configuration: ~/.local/bin is not on
# its PATH yet, and the check below needs it there.
export PATH="$HOME/.local/bin:$PATH"

launcher=$HOME/.local/bin/claude

if [ -x "$launcher" ]; then
    echo "Claude Code is already installed ($("$launcher" --version)) - nothing to do."
else
    foreign=$(command -v claude 2>/dev/null || true)
    if [ -n "$foreign" ]; then
        echo ""
        hint "Claude Code is already installed on Windows."
        hint "Install a local version too? [Y/n]"
        if read -r answer; then
            case "$answer" in
                [nN]*)
                    echo "Nothing was installed."
                    exit 2
                    ;;
            esac
        fi
    fi

    echo "Installing Claude Code from Anthropic's own script (a few minutes)..."
    clean_path=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    PATH=$clean_path curl -fsSL https://claude.ai/install.sh | PATH=$clean_path bash 2>&1 |
        LC_ALL=C tr -d '\200-\377'
fi

# The dictionary of providers: seeded once, never written again. Mode 600 - the
# tokens go in there, and what the pack writes in your settings comes out of it.
profiles=$HOME/.config/claude/profiles.json
if [ -f "$profiles" ]; then
    echo "$profiles is already there - left as it is."
else
    # Checked before it is copied: a broken sample would be discovered at the
    # first profile switch.
    jq -e . "$here/profiles.sample" > /dev/null ||
        { echo "$profiles: the pack's own sample of providers does not parse - nothing was written." >&2; exit 1; }
    install -d -m 0700 "$(dirname "$profiles")"
    install -m 600 "$here/profiles.sample" "$profiles"
    echo "A dictionary of providers is in place: $profiles."
    echo "Fill it with your tokens."
fi

# The socle builds .env.global from the samples; this runs that target once so
# the first `gmake claude_profile` finds it. Only when it is not there; a
# failure here is said, not fatal - the program is installed, which is what the
# pack came for.
global_env=$HOME/.config/zsh/gmake/.env.global
makefile=$HOME/.config/zsh/gmake/Makefile
if [ ! -f "$global_env" ] && [ -f "$makefile" ]; then
    echo "Building $global_env from the samples..."
    if ! make -f "$makefile" env_global_enable; then
        echo "$global_env could not be built - 'gmake env_global_enable' will do it from a shell."
    fi
fi

# The status line the instance's sessions draw: set once, and never over one
# that is already there. remove.sh takes back exactly the one this writes, and
# only while it is still the one.
settings=$HOME/.claude/settings.json
status_command="bash ~/.config/packs/claude/bin/statusline.sh"
if [ -f "$settings" ] && ! jq -e . "$settings" > /dev/null 2>&1; then
    echo "$settings does not parse - the status line was not set."
elif [ -f "$settings" ] && [ -n "$(jq -r '.statusLine.command // empty' "$settings" 2>/dev/null || true)" ]; then
    echo "$settings already has a status line - left as it is."
else
    install -d -m 0700 "$(dirname "$settings")"
    tmp=$(mktemp)
    if [ -f "$settings" ]; then
        ok=1
        jq --arg cmd "$status_command" '.statusLine = {"type": "command", "command": $cmd}' "$settings" > "$tmp" 2>/dev/null || ok=0
    else
        ok=1
        jq -n --arg cmd "$status_command" '{statusLine: {"type": "command", "command": $cmd}}' > "$tmp" || ok=0
    fi
    if [ "$ok" = "0" ]; then
        rm -f "$tmp"
        echo "$settings could not be written - the status line was not set."
    else
        chmod 600 "$tmp"
        mv "$tmp" "$settings"
    fi
fi

success "Claude Code is ready."
