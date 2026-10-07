#!/bin/sh
# ==============================================================================
# THE MESSAGES
# ==============================================================================
# A message says what kind of line it is; the colour is decided once, here,
# over the names in lib/colours.sh. The kinds are scripts/message.ps1's: error,
# warning, success, info, muted, hint - warning and hint share the yellow until
# they need to differ.
#
# Never read by the interactive shell: these six names would land in a session.
# A script reads it with:
#   . "${ZDOTDIR:-$HOME/.config/zsh}/lib/message.sh"
# shellcheck source=/dev/null
. "${ZDOTDIR:-$HOME/.config/zsh}/lib/colours.sh"
error()   { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET"; }
warning() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
success() { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
info()    { printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
muted()   { printf '%s%s%s\n' "$C_GREY" "$*" "$C_RESET"; }
hint()    { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
