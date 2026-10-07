#!/usr/bin/env bash
# ==============================================================================
# THE GCP PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/gcp, then
# runs this script from inside it, as the instance's own user.
#
# The root half - the repository, the key, the package - is in install_root.sh,
# beside this file, and the engine runs it as root before this one starts.
#
# The image carries no trace of Google - no signing key, no APT address. This
# script registers both, then installs the package; remove.sh undoes exactly
# that.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# The root half ran before this script - the engine's call, as WSL's own
# root, ahead of the passwordless door. What is left here is the user's own
# part.

success "Google Cloud CLI installed."