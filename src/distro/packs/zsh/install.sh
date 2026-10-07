#!/usr/bin/env bash
# ==============================================================================
# THE ZSH PACK - WHAT IT INSTALLS
# ==============================================================================
# `wsl.ps1 add_pack` copies this pack's folder into ~/.config/packs/zsh, then
# runs this script from inside it, as the instance's own user.
#
# The socle in one pack: on the built image everything here is already in
# place and every step answers "already there" - the same run that dresses a
# foreign Debian. Nothing is ever re-downloaded: the clones are asked about
# before they start, and a binary on the PATH is left where it is.

set -euo pipefail

# The messages: the shared library replaces this fallback when the image
# carries it; an instance built before it prints a plain sentence.
success() { printf '%s\n' "$*"; }
if [ -r "$HOME/.config/zsh/lib/message.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/zsh/lib/message.sh" || true
fi

# The PATH is built here, not inherited: the shell this script runs from
# carries WSL's Windows directories, and a name resolved through them can be a
# Windows program. The same clean_path the other packs keep.
clean_path=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH=$clean_path

here=$(cd "$(dirname "$0")" && pwd)

# The root half ran before this script - the engine's call, as WSL's own
# root, ahead of the door. That order is what lets this pack install sudo
# itself: on a bare Debian there is no door to open yet.

# Oh-My-Zsh and its two plugins, each asked about on its own: a run that
# stopped between two clones picks up where it stopped.
ohmyzsh="$HOME/.local/share/oh-my-zsh"
if [ ! -d "$ohmyzsh" ]; then
    echo "Cloning oh-my-zsh..."
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ohmyzsh"
fi
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ ! -d "$ohmyzsh/custom/plugins/$plugin" ]; then
        echo "Cloning $plugin..."
        git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$ohmyzsh/custom/plugins/$plugin"
    fi
done

# Starship and tealdeer, the two binaries apt never sees: a name already on
# the PATH - the image's /usr/local/bin, or another pack's - is left where it
# is, and only a missing one is fetched, into ~/.local/bin (the socle's own
# PATH, from exports.zsh).
case "$(dpkg --print-architecture)" in
    amd64) release_arch="x86_64" ;;
    *)     release_arch="aarch64" ;;
esac
if ! command -v starship >/dev/null 2>&1; then
    echo "Installing Starship..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-${release_arch}-unknown-linux-gnu.tar.gz" |
        tar -xz -C "$HOME/.local/bin" starship
    chmod +x "$HOME/.local/bin/starship"
fi
if ! command -v tldr >/dev/null 2>&1; then
    echo "Installing tealdeer (tldr)..."
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-${release_arch}-musl" -o "$HOME/.local/bin/tldr"
    chmod +x "$HOME/.local/bin/tldr"
fi

# The shell's own files, into the home. -n: a file that is already there is
# never replaced - the settings are the ones you have, and re-running the
# install cannot overwrite an edit. The .env files the gmake keeps your
# variables in are not in this folder either way.
echo "Installing the shell configuration..."
mkdir -p "$HOME/.config/zsh" "$HOME/.local/state/zsh" "$HOME/.cache/zsh"
cp -rn "$here/config/." "$HOME/.config/zsh/"

# The one line that points zsh at the socle. A ~/.zshenv of your own is never
# touched: either it already does this, or it is told what to add.
if [ ! -e "$HOME/.zshenv" ]; then
    # The single quotes are the point: this line goes into the file as
    # written, and the variable must expand in the login shell, not here.
    # shellcheck disable=SC2016
    printf '%s\n%s\n' 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' 'skip_global_compinit=1' > "$HOME/.zshenv"
elif ! grep -q 'ZDOTDIR' "$HOME/.zshenv"; then
    echo "NOTE: ~/.zshenv exists and does not set ZDOTDIR - the socle will not"
    echo "      load until it does. Yours is yours, so nothing was added; put"
    echo "      this line in it:"
    echo "        export ZDOTDIR=\"\${XDG_CONFIG_HOME:-\$HOME/.config}/zsh\""
fi

# The home's leftovers from a shell used before the pack. A ~/.zshrc at the
# home's own root is never read again once ZDOTDIR points at the settings -
# the stub this repository's image leaves is taken back, and one zsh's
# first-run assistant wrote is moved aside, never deleted. A ~/.zsh_history
# is folded into the state file the settings name, so the commands you
# already typed keep their history.
if [ -e "$HOME/.zshrc" ]; then
    if head -1 "$HOME/.zshrc" | grep -q '^# The shell starts bare'; then
        rm -f "$HOME/.zshrc"
    else
        mv -f "$HOME/.zshrc" "$HOME/.zshrc.before-zsh-pack"
        echo "NOTE: your ~/.zshrc was moved to ~/.zshrc.before-zsh-pack - the"
        echo "      settings below take over from here; move back what you miss."
    fi
fi
if [ -s "$HOME/.zsh_history" ]; then
    cat "$HOME/.zsh_history" >> "$HOME/.local/state/zsh/history"
fi
rm -f "$HOME/.zsh_history"

success "The shell socle is installed. Open a new shell, or run:  exec zsh"
