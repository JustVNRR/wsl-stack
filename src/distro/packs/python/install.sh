#!/usr/bin/env bash
# ==============================================================================
# THE PYTHON PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/python, then
# runs this script from inside it, as the instance's own user.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# The PATH is built here, not inherited: the shell this script runs from
# carries WSL's Windows directories, and a name resolved through them can be a
# Windows program - the claude pack's installer uninstalled the Windows copy
# that way. The claude pack's clean_path, kept identical so the two read alike.
#
# ~/.local/bin is in it: uv warns on every tool when that directory is missing
# from the PATH, and the `uv` lines below must find what the line above
# installed.
clean_path=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH=$clean_path

here=$(cd "$(dirname "$0")" && pwd)

# The root half ran before this script - the engine's call, as WSL's own
# root, ahead of the passwordless door. What is left here is the user's own
# part.

# uv may already be there: this pack requires the scaffold pack, which installs
# it and comes first. Asking the machine rather than installing a second time
# keeps the download to one.
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

echo "Installing Python 3 and ruff..."
uv python install 3
# --force: a shim left by an install that stopped halfway makes uv refuse to
# write ruff's, and a pack whose install can only be re-run after cleaning up
# by hand never finishes.
uv tool install --force ruff

success "Python 3, uv and ruff are installed."
