#!/usr/bin/env bash
# ==============================================================================
# THE SCAFFOLD PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/scaffold,
# then runs this script from inside it, as the instance's own user.
#
# One tool: uv, under ~/.local - the same binary the python pack uses, and it
# may well be there already. The three tools the targets drive (copier, cruft,
# ccds) are NOT installed: `uvx --from ...` takes each from uv's cache the
# first time it runs, and a command that is never used costs nothing.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# The same clean_path the claude and python packs use: the shell this script
# runs from carries WSL's Windows directories, and `command -v uv` could be
# answered by a Windows one - this script would conclude "already installed"
# and put nothing here.
#
# ~/.local/bin in it: the check below and uv's installer need that directory.
clean_path=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH=$clean_path

if command -v uv >/dev/null 2>&1; then
    echo "uv is already installed ($(uv --version)) - nothing to do."
else
    echo "Installing uv..."
    # UV_NO_MODIFY_PATH: left alone, uv's installer adds a line to the shell's
    # startup files; each pack declares its own PATH in its own zsh file.
    # pipefail makes the curl pipe safe: a failed curl would feed an empty
    # script, which exits 0.
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
fi

success "The scaffolding is ready."