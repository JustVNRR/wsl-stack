# ============================================================
# 1. OH MY ZSH DEFAULT ALIAS CLEANUP
# ============================================================

unalias rm 2>/dev/null
unalias lt 2>/dev/null

# ============================================================
# 2. CUSTOM SHORTCUTS & SYSTEM UTILITIES
# ============================================================

# The gmake Makefile inside $ZDOTDIR. A function, not an alias: zsh expands an
# alias before completing the line, so a completion bound to its name is never
# consulted - Tab would complete plain `make`.
gmake() {
    make -f "$ZDOTDIR/gmake/Makefile" "$@"
}

# Directory navigation & open network ports
alias b='cd -'
alias ports='sudo lsof -i -P -n | grep LISTEN'

# Quick configuration edits and reload (XDG compliant)
alias zsh_conf='code ~/.config/zsh'

# exec, not source: re-reading inside a live shell runs Oh My Zsh's lib against
# an alias table already expanded - its GLOBAL aliases (P, L, G...) break it. A
# fresh process reads the configuration in the normal order and cannot hit that.
alias reload='exec zsh'

# ============================================================
# 3. MODERN UTILITIES (RUST STACK)
# ============================================================

# eza (ls replacement with icons and Git status integration)
# --icons=always, never a bare --icons: the flag takes an optional value and a
# bare one swallows what follows it. `auto` renders no icon even on a terminal.
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=always'
    alias ll='eza -lh --icons=always --git'
    alias la='eza -lah --icons=always --git'
    alias tree='eza --tree --icons=always'
fi

# bat (cat replacement featuring syntax highlighting)
if command -v batcat >/dev/null 2>&1; then
    alias cat='batcat'
fi

alias grep='grep --color=auto'

# ============================================================
# 4. ALIAS FUZZY PICKER (FALIAS)
# ============================================================

# Interactively fuzzy-select an alias using fzf and return only its identifier
_falias_select() {
    alias |
        awk -F'=' -v m="$C_GREY" -v r="$C_RESET" '{
            printf "%-25s %s->%s %s\n", $1, m, r, $2
        }' |
        fzf \
            --ansi \
            --prompt="💡 Shortcuts > " \
            --info=inline \
            --layout=reverse |
        awk '{print $1}'
}

# CLI command: falias
falias() {
    local alias_name
    alias_name=$(_falias_select)
    [[ -z "$alias_name" ]] && return
    print -z -- "$alias_name "
}

# ZLE Widget: Alt + y
_falias_widget() {
    local alias_name
    # -I before the picker, reset-prompt after: zsh must be told its idea of
    # the display is stale before it redraws the prompt over what fzf painted.
    zle -I
    alias_name=$(_falias_select)
    [[ -z "$alias_name" ]] && {
        zle reset-prompt
        return
    }
    LBUFFER+="$alias_name "
    zle reset-prompt
}