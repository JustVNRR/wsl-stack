#!/usr/bin/env bash
# ==============================================================================
# THE TEMPLATE PACK - WHAT LEAVES WITH IT
# ==============================================================================
# `wsl.ps1 remove_pack` runs this script before the folder goes, as the
# instance's own user. What needs root goes to remove_root.sh, which this
# script calls as one sudo - the door is open exactly here.
#
# What an install leaves behind is removed HERE - everything it created:
# files and folders in the home, binaries dropped in ~/.local/bin, caches.
# The pack's own folder is NOT this script's business: the machinery takes
# it once this script returns. A real removal looks like:
#
# 	rm -rf "$HOME/.config/my-tool"
# 	rm -f "$HOME/.local/bin/my-tool"
#
# The template creates nothing, so it says it ran and nothing else.

echo "run remove template"
