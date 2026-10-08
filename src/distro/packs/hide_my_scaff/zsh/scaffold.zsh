# ============================================================
# PROJECT SCAFFOLDING (FNEW)
# ============================================================
# The shell reads it where it lives; nothing is copied. `%x` is this file - the
# catalogs are resolved from here, and it is also the right answer from inside
# a function (there, `$0` is the function's name).

# uv and its tools live in ~/.local/bin; the pack declares its own PATH rather
# than editing the startup files - the oh_my_py pack declares the same line.
export PATH="$HOME/.local/bin:$PATH"

# Pick a template from every installed pack's catalog and print
# "url<TAB>tool<TAB>version<TAB>pack" - the pack whose after-copy step runs.
_ftemplate_select() {
    # :A resolves the path; :h three times climbs from zsh/scaffold.zsh to the
    # packs' folder.
    local packs="${${(%):-%x}:A:h:h:h}"
    local -a catalogs readable
    local skipped c

    catalogs=("$packs"/*/cheatsheets/templates.tsv(N))
    # A pack with no catalog, or an empty one, is not a failure; nothing
    # readable anywhere is the silent exit fnew relies on.
    for c in "${catalogs[@]}"; do
        [[ -s "$c" ]] || continue
        readable+=("$c")
    done
    (( ${#readable} )) || return 1

    # Rows the picker skips are collected BEFORE it runs: fzf owns the screen,
    # and a message emitted before would only flash. Each row is named with its
    # catalog.
    skipped=$(awk -F'\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF < 4 { print FILENAME ": " $0 }
    ' "${readable[@]}")

    awk -F'\t' -v c="$C_CYAN" -v y="$C_YELLOW" -v m="$C_GREY" -v r="$C_RESET" '
        # Which pack a row comes from is the folder its catalog sits in:
        # <packs>/<pack>/cheatsheets/templates.tsv. FILENAME changes with every
        # file awk opens, so this is read once per file, on its first line.
        FNR == 1 {
            n = split(FILENAME, dirs, "/")
            pack = dirs[n-2]
        }

        # Skip comments, blank lines and malformed rows (the caller warns)
        /^[[:space:]]*(#|$)/ { next }
        NF < 4 { next }

        {
            url = $1
            tool = $2
            ver = $3
            sub(/[[:space:]]+$/, "", url)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", tool)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", ver)
            sub(/^[[:space:]]+/, "", $4)

            # Derive owner/repo from the url so the picker is searchable by repo name
            n = split(url, seg, "/")
            repo = url
            if (n >= 2) {
                repo = seg[n-1] "/" seg[n]
                sub(/^gh:/, "", repo)
                sub(/\.git$/, "", repo)
            }

            # Held until END: the columns are padded to the widest row, which is
            # only known once the whole catalog has been read. fzf is handed the
            # list in one go, so buffering the rows costs nothing.
            i = ++count
            urls[i] = url; tools[i] = tool; vers[i] = ver
            descs[i] = $4; repos[i] = repo; packs[i] = pack
            labels[i] = (ver == "") ? tool : tool " @" ver
            if (length(labels[i]) > wlabel) wlabel = length(labels[i])
            if (length(repo) > wrepo) wrepo = length(repo)
            if (length(pack) > wpack) wpack = length(pack)
        }

        END {
            for (i = 1; i <= count; i++) {
                if (vers[i] == "") {
                    tag = sprintf("%s%s%s%s", c, tools[i], r, spaces(wlabel - length(tools[i])))
                } else {
                    tag = sprintf("%s%s%s %s@%s%s%s", c, tools[i], r, y, vers[i], r, spaces(wlabel - length(labels[i])))
                }
                # Field 4 is the pack, kept out of the display on purpose: fzf
                # shows field 5 and hands the whole line back, so the pack
                # survives the pipe without being read by the eye twice.
                printf "%s\t%s\t%s\t%s\t%s%s%s%s %s·%s %s  %s|%s  %s%s  %s|%s  %s\n", urls[i], tools[i], vers[i], packs[i], m, packs[i], r, spaces(wpack - length(packs[i])), m, r, tag, m, r, repos[i], spaces(wrepo - length(repos[i])), m, r, descs[i]
            }
        }

        # n spaces; a printf of a negative width right-aligns, so it is clamped
        function spaces(k) { return sprintf("%*s", k > 0 ? k : 0, "") }
    ' "${readable[@]}" |
        fzf \
            --ansi \
            --delimiter=$'\t' \
            --with-nth=5 \
            --prompt='🏗️  Templates > ' \
            --info=inline \
            --layout=reverse |
        awk -F'\t' '{ print $1 "\t" $2 "\t" $3 "\t" $4 }'

    # A malformed row silently vanishes from the picker, which then looks exactly
    # like an empty catalog: name it, now that the screen is ours again. The row
    # printed carries the catalog it was read from.
    if [[ -n "$skipped" ]]; then
        local -a lines
        lines=("${(f)skipped}")
        printf "⚠️  %d malformed row(s) ignored\n" "${#lines}" >&2
        printf "    %s\n" "${lines[1]}" >&2
        printf "    A row needs 4 TAB-separated columns: url, tool, version, description.\n" >&2
    fi
}

# Scaffold a new project, from the packs' catalogs or from an explicit URL.
# It runs from ~/projects itself only (before any input), then delegates to the
# gmake target of the chosen tool (copier_project / cruft_project /
# ccds_project), which runs the pack's after-copy step.
#
#   fnew                        # pick from the catalogs
#   fnew gh:owner/repo [tool] [ref]
#
# The URL form reads and writes nothing: a template that does not suit costs
# only the project directory.
fnew() {
    local selection url tool version project_name pack remainder
    local -a make_args

    # ~/projects itself, before any interaction (deeper would nest projects)
    if [[ "$PWD" != "$HOME"/projects ]]; then
        echo "❌ fnew runs from ~/projects itself (current: $PWD)" >&2
        return 1
    fi

    if [[ -n "$1" ]]; then
        url="$1"
        tool="${2:-copier}"
        version="${3:-}"
    else
        selection=$(_ftemplate_select)
        [[ -z "$selection" ]] && return

        url=${selection%%$'\t'*}
        remainder=${selection#*$'\t'}
        tool=${remainder%%$'\t'*}
        remainder=${remainder#*$'\t'}
        version=${remainder%%$'\t'*}
        pack=${remainder#*$'\t'}
    fi

    if [[ "$tool" != copier && "$tool" != cruft && "$tool" != ccds ]]; then
        echo "❌ Unknown scaffold tool '$tool' (expected: copier, cruft or ccds)" >&2
        return 1
    fi

    # Only copier needs the destination path upfront; cruft and ccds ask the
    # name themselves, and asking twice would. The name uses the line editor so
    # arrows and backspace work - plain `read` has none, and escape bytes would
    # land in the variable. `vared -c`: unset variables, text kept across
    # attempts; a pipe or CI falls back to `read`.

    if [[ "$tool" == "copier" ]]; then
        while true; do
            if [[ -o interactive && -t 0 ]]; then
                vared -p "Project folder: " -c project_name || return
            else
                read "project_name?Project folder: " || return
            fi
            if [[ "$project_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
                break
            fi
            echo "Invalid name (use letters, digits, '.', '_' or '-'; no spaces)."
        done

        echo "📁 Creating project in: $PWD/$project_name"
    fi

    make_args=("${tool}_project" "PROJECT_NAME=$project_name" "PROJECT_TEMPLATE_REPO=$url")
    if [[ -n "$version" ]]; then
        make_args+=("PROJECT_TEMPLATE_VERSION=$version")
    fi
    # The row's pack decides what runs after the copy, and naming it on the
    # command line beats the .env.global default a direct call reads. The URL
    # form picks no row and keeps the default.
    if [[ -n "$pack" ]]; then
        make_args+=("TEMPLATE_PACK=$pack")
    fi

    # The Makefile cannot move this shell - recipes run in their own process;
    # fnew is a function, so it can, and only when the scaffolding succeeded.
    # Copier uses the destination it was given; cruft and ccds derive one, so
    # the newest folder is found.
    if [[ "$tool" == "copier" ]]; then
        make -f "$ZDOTDIR/gmake/Makefile" "${make_args[@]}" && cd "$project_name"
    else
        make -f "$ZDOTDIR/gmake/Makefile" "${make_args[@]}" && cd *(/om[1])
    fi
}
