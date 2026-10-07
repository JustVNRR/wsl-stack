#!/usr/bin/env bash
# ==============================================================================
# THE GCP PACK - WHAT IT REMOVES AS ROOT
# ==============================================================================
# Run by remove.sh as one sudo.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get remove -y google-cloud-cli
rm -f /etc/apt/keyrings/cloud.google.gpg /etc/apt/sources.list.d/google-cloud-sdk.list
