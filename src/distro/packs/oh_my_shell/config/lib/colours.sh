#!/usr/bin/env bash
# ==============================================================================
# THE SHELL COLOURS
# ==============================================================================
# The only shell file that writes an escape sequence. The display uses read the
# variables (.zshrc sources it; the pickers take them directly), and the scripts
# read them through lib/message.sh, which maps a message's kind to one of them.
#
# The make side has its twin, gmake/make/colours.mk: a colour changed in one
# file is changed in the other.
#
# Nothing else belongs here: .zshrc reads it into a running session, where a
# `set` would land in that session's options.
export C_RESET=$'\033[0m'
export C_RED=$'\033[31m'
export C_GREEN=$'\033[32m'
export C_YELLOW=$'\033[33m'
export C_CYAN=$'\033[36m'
export C_GREY=$'\033[90m'
