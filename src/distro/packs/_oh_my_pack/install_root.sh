#!/usr/bin/env bash
# ==============================================================================
# THE TEMPLATE PACK - WHAT NEEDS ROOT
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/template,
# then runs this script before install.sh, as WSL's root. What apt must
# install goes through PACK_PACKAGES instead; this file is for the rest.
#
# The template does nothing: it says it ran.

echo "run install root template"
