# ============================================================
# COMPLETION
# ============================================================

# The targets `gmake` takes, each with the sentence it carries: read at every
# Tab from the files `gmake help` reads, and by its rule - a target documents
# itself after `##`. A pack that is not installed brings neither a module here
# nor a target.
_gmake() {
    local -a files pairs

    # The first word only: what follows a target is an assignment or nothing.
    (( CURRENT == 2 )) || return 1

    # The Makefile, its modules, the packs' - the same three places `help` reads.
    files=("$ZDOTDIR"/gmake/Makefile(N) "$ZDOTDIR"/gmake/make/*.mk(N) "$ZDOTDIR"/../packs/*/make/*.mk(N))
    (( $#files )) || return 1

    # `name:sentence`, the form _describe reads, built by the help rule's own
    # expression; sorted like the menu.
    pairs=(${(f)"$(
        awk -F':.*##' '
            /^[a-zA-Z_-]+:.*?##/ {
                sub(/[[:space:]]+$/, "", $2)
                printf "%s:%s\n", $1, $2
            }
        ' "${files[@]}" | sort -f
    )"})
    (( $#pairs )) || return 1

    _describe -t gmake-targets 'gmake target' pairs
}

# On the function, not on `make`, which is a command of its own.
compdef _gmake gmake
