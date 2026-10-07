#!/usr/bin/env bash
# ==============================================================================
# THE CLAUDE PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# Three things to take back: the launcher, the versions behind it, and the
# desktop entry the CLI drops for its URL scheme (it points at the launcher).
#
# The CLI's own data (~/.claude, its caches) and the dictionary the pack seeded
# are the user's, and they STAY - exactly as ~/.mozilla stays when the web pack
# leaves. The one question at the end is the only thing that says otherwise;
# with no answer to read, keeping is the answer.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints plain sentences.
hint() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

here=$(cd "$(dirname "$0")" && pwd)

# A claim is a declaration, not a mention: the name is read off PACK_PACKAGES
# and PACK_OUTSIDE_APT, and off install.sh for a pack written before the first
# existed.
claimed_elsewhere() {
    local other value word
    for other in "$HOME"/.config/packs/*/; do
        if [ "${other%/}" = "$here" ]; then
            continue
        fi
        value=$(sed -nE 's/^PACK_(PACKAGES|OUTSIDE_APT) *:=[[:space:]]*//p' "$other/pack.conf" 2>/dev/null)
        for word in $value; do
            if [ "$word" = "$1" ]; then
                return 0
            fi
        done
        grep -q -- "$1" "$other/install.sh" 2>/dev/null && return 0
    done
    return 1
}

claimed=0
if claimed_elsewhere claude; then
    claimed=1
    echo "claude: another installed pack claims it - left in place, with the versions it keeps."
else
    echo "Removing Claude Code and the versions it keeps..."
    # Every path is spelled from $HOME so none is empty, and `rm -f` takes a
    # symlink or a file - nothing else.
    rm -f "$HOME/.local/bin/claude"
    rm -rf "$HOME/.local/share/claude"
    # The dead desktop entry for the claude-cli:// scheme: the CLI drops it at a
    # run, and it points at the launcher just removed. Only that file - the
    # applications directory is shared.
    rm -f "$HOME/.local/share/applications/claude-code-url-handler.desktop"
fi

# And the provider keys in the settings - the four shorthand ones, plus every
# key the dictionary declared: meaningless without it, and a token left behind
# is a token nobody looks after. Everything else in that file is not looked at.
settings=$HOME/.claude/settings.json
if [ -f "$settings" ]; then
    profiles=$HOME/.config/claude/profiles.json
    owned=$(
        {
            printf 'ANTHROPIC_BASE_URL\nANTHROPIC_AUTH_TOKEN\nANTHROPIC_API_KEY\nANTHROPIC_MODEL\n'
            if [ -f "$profiles" ]; then
                jq -r '(.profiles // [])[] | del(.id, .note) | keys[]' "$profiles" 2>/dev/null || true
            fi
        } | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))'
    )
    tmp=$(mktemp)
    if jq --argjson owned "$owned" '
            (.env // {}) as $env
            | .env = ($env | with_entries(select(.key as $k | ($owned | index($k)) == null)))
            | if .env == {} then del(.env) else . end
        ' "$settings" > "$tmp" 2>/dev/null; then
        chmod 600 "$tmp"
        mv "$tmp" "$settings"
        echo "The provider keys this pack wrote were taken back out of $settings."
    else
        rm -f "$tmp"
        echo "$settings could not be read - the provider keys in it were left as they are."
    fi
fi

# And the status line, only while it is still the pack's: one of your own is
# yours, and this never takes it away.
if [ -f "$settings" ]; then
    if jq -r '.statusLine.command // empty' "$settings" 2>/dev/null | grep -q 'packs/claude/bin/statusline.sh'; then
        tmp=$(mktemp)
        if jq 'del(.statusLine)' "$settings" > "$tmp" 2>/dev/null; then
            chmod 600 "$tmp"
            mv "$tmp" "$settings"
            echo "The pack's status line was taken back out of $settings."
        else
            rm -f "$tmp"
        fi
    fi
fi

# What the CLI wrote and the dictionary: the removals above were the program,
# this is the data, and it is the user's - sessions, a login, tokens cannot be
# fetched again. `n` is the only answer that takes it all; no answer means
# keep. Asked only when the program really left and there is something to keep.
# Yellow, like the install question, for the same reason: this text lands in a
# Windows console.
wiped=0
has_data=0
if [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ] || [ -e "$HOME/.config/claude" ]; then
    has_data=1
fi

if [ "$claimed" -eq 0 ] && [ "$has_data" -eq 1 ]; then
    echo ""
    hint "Your data stays where it is:"
    hint "   ~/.claude and ~/.claude.json - settings, login, history, sessions"
    hint "   the caches under ~/.cache and ~/.local/state"
    hint "   ~/.config/claude/profiles.json - your providers, and their tokens"
    hint "Keep it all? [Y/n]"
    if read -r answer; then
        case "$answer" in
        [nN]*)
            wiped=1
            rm -rf "$HOME/.claude" "$HOME/.claude.json" "$HOME/.cache/claude" \
                "$HOME/.local/state/claude" "$HOME/.config/claude"
            # The pack's block in .env.global - the fence, the title, the
            # comments and the CLAUDE_PROFILE line - removed only when the block
            # is really there, so a file that never saw the merge is left byte
            # for byte. The awk buffers because the fence to drop is the line
            # BEFORE the title.
            global_env=$HOME/.config/zsh/gmake/.env.global
            if [ -f "$global_env" ] && grep -q "^# CLAUDE - SHARED DEFAULTS (the claude pack)$" "$global_env"; then
                tmp=$(mktemp)
                if awk '
                        { lines[NR] = $0 }
                        END {
                            start = 0
                            for (i = 1; i <= NR; i++) {
                                if (lines[i] == "# CLAUDE - SHARED DEFAULTS (the claude pack)") { start = i; break }
                            }
                            if (start > 1 && lines[start - 1] ~ /^# =+$/) start = start - 1
                            end = 0
                            for (i = start; i <= NR; i++) {
                                if (lines[i] ~ /^CLAUDE_PROFILE=/) { end = i; break }
                            }
                            for (i = 1; i <= NR; i++) {
                                if (start > 0 && end > 0 && i >= start && i <= end) continue
                                print lines[i]
                            }
                        }
                    ' "$global_env" > "$tmp"; then
                    mv "$tmp" "$global_env"
                else
                    rm -f "$tmp"
                fi
            fi
            echo "All of it was removed as well."
            ;;
        esac
    fi
fi

if [ "$claimed" -eq 0 ]; then
    echo "Claude Code is gone."
    if [ "$wiped" -eq 1 ]; then
        echo "   Its data went with it: nothing of this pack is on the machine any more."
    else
        echo "   Left where they are: your providers, ~/.config/claude/profiles.json - they"
        echo "   carry your tokens - and ~/.claude, with its settings, its history and its login."
    fi
else
    echo "Claude Code is still there: another installed pack claims it."
fi

# Plain ASCII, like install.sh and for the same reason: this text travels
# through wsl.exe to the Windows console.
