#!/bin/bash
set -e

# The socle's colours, read from the skeleton the image carries them in - the
# instance has no account yet. A missing library leaves the questions plain
# rather than stopping the onboarding.
C_RESET=''
C_RED=''
C_GREEN=''
C_YELLOW=''
C_CYAN=''
C_GREY=''
if [ -r /etc/skel/.config/zsh/lib/colours.sh ]; then
    # shellcheck source=/dev/null
    . /etc/skel/.config/zsh/lib/colours.sh || true
fi

clear
echo "============================================================"
echo "            Welcome to your WSL Stack environment"
echo "============================================================"
echo ""

# The build asks the name with its other questions and hands it here; the root
# shell that triggers this script passes nothing, and is asked below.
NEW_USER="${1:-}"

# A name no account uses yet: adduser fails on a taken one (root, daemon,
# www-data...), and set -e would abort the whole onboarding on its raw error.
while true; do
    if [ -z "$NEW_USER" ]; then
        read -rp "${C_YELLOW}Enter your username: ${C_RESET}" NEW_USER
    fi
    if [[ ! "$NEW_USER" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        echo "${C_YELLOW}Invalid username (lowercase letters, numbers, underscores, and dashes only, starting with a letter).${C_RESET}"
        NEW_USER=''
    elif id "$NEW_USER" >/dev/null 2>&1; then
        echo "${C_YELLOW}The account '$NEW_USER' already exists - pick another name.${C_RESET}"
        NEW_USER=''
    else
        break
    fi
done

echo ""
echo "${C_CYAN}Creating user account $NEW_USER...${C_RESET}"
# Create user silently (skips Full Name, Room Number, etc.)
adduser --disabled-password --gecos "" --shell /usr/bin/zsh "$NEW_USER"

# The trigger in /root/.bashrc runs this again on every root shell, and the
# account exists from here: a re-run could only fail on adduser. Disarmed now,
# not at the end - a failure above would leave that loop running.
sed -i '/first_boot\.sh/d' /root/.bashrc 2>/dev/null || true

echo ""
# The account was created with no password of its own (--disabled-password):
# inside WSL nobody logs in with one, so the password's only job is sudo. Hence
# the question, defaulting to no - NOPASSWD lets anything running as this user
# become root with no prompt at all.
read -rp "${C_YELLOW}Run sudo without a password (passwordless)? [y/N] ${C_RESET}" PASSWORDLESS
echo ""

# The group is what makes sudo possible at all - both paths below need it.
usermod -aG sudo "$NEW_USER"

PASSWORDLESS_OK=no
if [[ "$PASSWORDLESS" =~ ^[Yy]$ ]]; then
    # The drop-in that makes sudo stop asking. No dot in the name and 0440:
    # sudo ignores a file whose name contains one or ends in ~, and refuses any
    # other mode. The syntax is checked before the file stays - an invalid file
    # in sudoers.d takes sudo away entirely - and on a failed check the
    # password path below runs.
    SUDOERS_FILE="/etc/sudoers.d/010-$NEW_USER-nopasswd"
    echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
    if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
        PASSWORDLESS_OK=yes
        echo "${C_GREEN}sudo will not ask for a password.${C_RESET}"
    else
        rm -f "$SUDOERS_FILE"
        echo "${C_YELLOW}[WARNING] The sudo rule could not be written - falling back to a password.${C_RESET}"
    fi
fi

if [[ "$PASSWORDLESS_OK" == no ]]; then
    echo "${C_YELLOW}Please set a password for $NEW_USER:${C_RESET}"
    while ! passwd "$NEW_USER"; do
        echo ""
        echo "${C_RED}[ERROR] Password setup failed (mismatch or empty). Let's try again.${C_RESET}"
    done
fi

# The docker socket Docker Desktop creates is writable by root and by this
# group only, so the group is created with the account: the very first session
# can use docker. Left to Docker Desktop, it only arrives at its next restart.
# --force, not a plain groupadd: the group may already exist, and set -e would
# abort the whole onboarding on that.
groupadd --force docker
usermod -aG docker "$NEW_USER"

echo ""
echo "${C_CYAN}Configuring timezone...${C_RESET}"
# The dialog frontend (whiptail): the list one entry per line, walked with the
# arrows. The readline frontend packs the same list into columns across the
# whole window, which the eye cannot follow.
dpkg-reconfigure -f dialog tzdata
clear

# The WSL configuration the onboarding knows. No [boot] block: the image ships
# no /sbin/init, so systemd=true would do nothing - `gmake systemd_up` writes
# it on the instance that asks. mountFsTab=false likewise: no /etc/fstab lines
# yet, and `gmake fstab_up` is what applies them.
cat << WSLCONF > /etc/wsl.conf
[user]
default=$NEW_USER

[automount]
enabled=true
mountFsTab=false

[interop]
enabled=true
appendWindowsPath=true
WSLCONF

# No Python here: uv and the interpreter come with the `python` pack, the
# scaffolding tools with `scaffold` - they arrive on the instance that asks,
# with `.\wsl.ps1 add_pack` or by being chosen while the instance is built.

# The pages cache is a convenience: a machine without network must not lose the
# run - and the script deletes itself last, once nothing below can fail.
su - "$NEW_USER" -c "tldr --update" || echo "${C_GREY}  (tldr cache left as it was)${C_RESET}"
rm -f /root/first_boot.sh
exit 0