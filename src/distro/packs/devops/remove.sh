#!/usr/bin/env bash
# ==============================================================================
# THE DEVOPS PACK - WHAT IT REMOVES
# ==============================================================================
# `wsl.ps1 remove_pack` runs this before deleting the pack's folder: what the
# install added leaves the machine, and only that.
#
# Nothing to take back - it installed nothing - and one thing never to touch:
# ~/projects, which comes from the image and outlives every pack.

set -euo pipefail

echo "Nothing to remove: this pack installed nothing."
echo "   ~/projects and the .env files inside it were left alone - they are yours."
