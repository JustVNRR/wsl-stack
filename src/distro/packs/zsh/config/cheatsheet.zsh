# ============================================================
# CHEATSHEETS (FCHEAT)
# ============================================================

# The sheets the picker offers, minus those whose `# requires:` header is not
# met (negated with `!`). Nothing is recorded: the question is asked again at
# every opening. Two folders, one rule: the shell's sheets, then the packs'.
_fcheat_files() {
    local file requires binary

    for file in "$ZDOTDIR"/cheatsheets/*.sh(N) "$ZDOTDIR"/../packs/*/cheatsheets/*.sh(N); do
        requires=$(awk '/^#[[:space:]]*requires:/ {
            sub(/^#[[:space:]]*requires:[[:space:]]*/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }' "$file")

        if [[ -z "$requires" ]]; then
            print -r -- "$file"
        elif [[ "$requires" == '!'* ]]; then
            binary=${requires#!}
            command -v "$binary" >/dev/null 2>&1 || print -r -- "$file"
        elif command -v "$requires" >/dev/null 2>&1; then
            print -r -- "$file"
        fi
    done
}

# Interactively fuzzy-select a command via fzf and return only the raw command
_fcheat_select() {
    local raw
    local -a sheets

    raw=$(_fcheat_files)
    [[ -z "$raw" ]] && return 1
    sheets=("${(@f)raw}")

    awk -F'#' -v c="$C_CYAN" -v m="$C_GREY" -v r="$C_RESET" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {
            next
        }

        {
            command = $1
            description = $2

            sub(/[[:space:]]+$/, "", command)
            sub(/^[[:space:]]+/, "", description)

            printf "%s\t%s%-40s%s | %s%s\n",
                command, c, command, m, r, description
        }
    ' "${sheets[@]}" 2>/dev/null |
        sort -f -t $'\t' -k1,1V |
        # Exact matching, not fzf's fuzzy default: fuzzy takes the query's
        # letters in order anywhere in the line, so `docker` ended its list on
        # `fnew` and `gcloud auth login`. The trade: a fragment like `dckr` no
        # longer matches. `'` and `!` behave as they always did.
        fzf \
            --exact \
            --ansi \
            --delimiter=$'\t' \
            --with-nth=2 \
            --prompt='📘 Cheatsheets > ' \
            --info=inline \
            --layout=reverse |
        awk -F'\t' '{print $1}'
}

# Standard CLI usage: fcheat
# Select a command and load it into the prompt buffer ready to execute
fcheat() {
    local command

    command=$(_fcheat_select)

    [[ -z "$command" ]] && return

    print -z -- "$command"
}

# ZLE Widget: Alt + z
# Replace prompt buffer with the selected cheatsheet command
_fcheat_widget() {
    local command

    # -I before the picker, reset-prompt after: see aliases.zsh.
    zle -I
    command=$(_fcheat_select)

    [[ -z "$command" ]] && {
        zle reset-prompt
        return
    }

    LBUFFER="$command"
    RBUFFER=""
    zle reset-prompt
}
