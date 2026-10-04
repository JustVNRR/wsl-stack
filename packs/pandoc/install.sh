#!/usr/bin/env bash
# ==============================================================================
# THE PANDOC PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/pandoc, then
# runs this script from inside it, as the instance's own user.
#
# Everything this script PRINTS is plain ASCII: it travels through wsl.exe to
# the Windows console, which reads those bytes in its own code page.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

here=$(cd "$(dirname "$0")" && pwd)

# sudo's own prompt has no trailing newline, and the line-based capture
# behind wsl.exe only showed whole lines: the question stayed invisible and
# the call waited forever. This prompt ends its line, so it shows.
sudo_prompt=$(printf '[sudo] password:\n')

sudo -p "$sudo_prompt" bash "$here/install_root.sh"

success "Pandoc and XeLaTeX are ready."
