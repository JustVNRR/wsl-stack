# ==============================================================================
# MAIN ZSH CONFIGURATION (.zshrc)
# ==============================================================================

# --- 1. ENVIRONMENT & FOUNDATIONS ---
# Global variables and runtime engines must load before dependent modules
source "$ZDOTDIR/exports.zsh"
source "$ZDOTDIR/fzf.zsh"          # Defines preview templates and underlying fuzzy commands
source "$ZDOTDIR/history.zsh"      # History size, file path, and shell persistence options
source "$ZDOTDIR/lib/colours.sh"   # The shell colours, written once - read by the modules and the packs

# --- 2. OH-MY-ZSH CORE CONFIGURATION ---
export ZSH="$HOME/.local/share/oh-my-zsh"
ZSH_THEME=""                 # Disabled: prompt handled by Starship
ZSH_DISABLE_COMPFIX=true     # Skip security check on completion directories (faster startup)

# Active plugins
# Note: Syntax highlighting and autosuggestions MUST remain at the end.
plugins=(
    # --- Core Utilities ---
    git
    common-aliases
    last-working-dir

    # --- Navigation & History Search ---
    history-substring-search
    fzf

    # --- Environment & Tooling ---
    ssh-agent
    direnv
    docker
    docker-compose

    # --- Interactive UI & Completions ---
    zsh-autosuggestions
    zsh-syntax-highlighting
)

# SSH-agent plugin configuration (quiet startup)
zstyle :omz:plugins:ssh-agent quiet yes
zstyle :omz:plugins:ssh-agent lazy yes

# Initialize Oh My Zsh
export ZSH_COMPDUMP="$HOME/.cache/zsh/.zcompdump-${SHORT_HOST:-$(hostname)}-${ZSH_VERSION}"
source "${ZSH}/oh-my-zsh.sh"



# --- 3. COMMANDS, ALIASES & SHELL UTILITIES ---
source "$ZDOTDIR/aliases.zsh"      # Command shortcuts and interactive falias tool
source "$ZDOTDIR/navigation.zsh"   # Directory hopping and fuzzy file pickers (cdv, cda, fv, fa)
source "$ZDOTDIR/unzip.zsh"        # Interactive archive extraction handler
source "$ZDOTDIR/cheatsheet.zsh"   # Custom cheatsheet selector (fcheat)
source "$ZDOTDIR/completion.zsh"   # Tab on gmake: the targets, read from the Makefile

# --- 4. ZLE KEYBINDINGS ---
# Keybindings must load AFTER all custom functions and widgets are declared in memory
source "$ZDOTDIR/bindings.zsh"

# --- 5. PACKS ---
# Each installed pack's shell files, read where they live: a pack that leaves
# takes its zsh with it. When the list changes the shell restarts - nothing can
# undefine a function in a running shell, so a fresh process is the only way.
#
# [@] and not $var: in zsh, "$array" of an EMPTY array is one empty word, and
# this loop would then source "".
typeset -ga _pack_zsh_loaded
_pack_zsh_loaded=("$ZDOTDIR"/../packs/*/zsh/*.zsh(N))
for _pack_zsh in "${_pack_zsh_loaded[@]}"; do
    source "$_pack_zsh"
done
unset _pack_zsh

_pack_zsh_follow() {
    local -a now
    now=("$ZDOTDIR"/../packs/*/zsh/*.zsh(N))
    [[ "${(j: :)_pack_zsh_loaded}" == "${(j: :)now}" ]] && return 0
    print -r -- "📦 the packs changed — restarting the shell"
    exec zsh
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _pack_zsh_follow

# --- 6. PROMPT ENGINE ---
# Executed last to ensure runtime hooks and aliases are fully registered
source "$ZDOTDIR/prompts/starship.zsh"

# --- 7. WSL STARTUP DIRECTORY RESOLUTION ---
# If opened from a mounted Windows volume (/mnt/*), restore last working directory or fallback to Linux home
if [[ "$PWD" == /mnt/* ]]; then
    lwd 2>/dev/null || cd ~
fi