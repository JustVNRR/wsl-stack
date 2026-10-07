#!/usr/bin/env bash
# ==============================================================================
# THE GCP PACK - WHAT IT INSTALLS AS ROOT
# ==============================================================================
# Run by install.sh as one sudo, asked while the keyboard is still free: a
# `curl ... | sudo gpg` in the middle of the install would have no terminal on
# its input for the password.

set -euo pipefail

# DEBIAN_FRONTEND, so that a package reconfigured on the way never stops the
# install to ask a question.
export DEBIAN_FRONTEND=noninteractive

# The install, with a line at once and then one every 15 seconds while apt
# works in silence: a long wait must not look like a hang. One line per beat,
# because the run is streamed to the console line by line - an animated line
# would never show.
apt_install() {
    printf 'Installing... 0:00\n'
    apt-get -qq install -y --no-install-recommends "$@" > /dev/null &
    local apt_pid=$! i=0
    while kill -0 "$apt_pid" 2>/dev/null; do
        sleep 15
        i=$((i + 15))
        if kill -0 "$apt_pid" 2>/dev/null; then
            printf 'Installing... %d:%02d\n' "$((i / 60))" "$((i % 60))"
        fi
    done
    wait "$apt_pid" || return 1
}

install -d -m 0755 /etc/apt/keyrings
# --batch --yes: gpg refuses to overwrite an existing output file without it,
# and the key file survives a removal that stopped halfway. The pipe needs
# pipefail (above): a curl that fails feeds gpg an empty input, and the failure
# must stop the install here rather than surface three steps later.
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/cloud.google.gpg
chmod go+r /etc/apt/keyrings/cloud.google.gpg
echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get -qq update
apt_install google-cloud-cli
