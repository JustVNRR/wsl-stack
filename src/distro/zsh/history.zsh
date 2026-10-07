# ============================================================
# HISTORY CONFIGURATION
# ============================================================

# 1. Storage path and limits
HISTFILE="$HOME/.local/state/zsh/history"
HISTSIZE=100000
SAVEHIST=100000

# 2. Multi-terminal session sharing
setopt APPEND_HISTORY
setopt SHARE_HISTORY

# 3. Deduplication management
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS

# 4. A leading space keeps a command out of the history
setopt HIST_IGNORE_SPACE

# 5. What is not worth remembering
# A command that does not exist never ran: `zshaddhistory` sees the line BEFORE
# it runs, and returning 1 keeps it out. Only the first word is looked at, so
# an alias, a function, a builtin and a keyword all count.
# Two lines are kept whatever they open on, because their first word is not the
# command: `FOO=bar cmd` and `$EDITOR file` - losing either would cost work.
zshaddhistory() {
    local -a words
    words=(${(z)1})

    [[ -n "$words[1]" ]] || return 0
    [[ "$words[1]" == *=* ]] && return 0
    [[ "$words[1]" == *'$'* ]] && return 0

    whence -w -- "$words[1]" >/dev/null 2>&1 && return 0
    return 1
}
