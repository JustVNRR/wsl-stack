#!/usr/bin/env bash
# ==============================================================================
# CLAUDE CODE - WHAT THE gmake TARGETS CALL
# ==============================================================================
# The subcommands, one per target in make/claude.mk: what needs a terminal (a
# menu) or a decision lives here rather than inside a recipe.
#
#   ~/.config/claude/profiles.json   your providers, one entry per endpoint with
#                                    its own token. Yours: seeded from the
#                                    sample, never written in again. Mode 600.
#   ~/.config/zsh/gmake/.env.global  CLAUDE_PROFILE, the entry in use.
#   ~/.claude/settings.json          the CLI's own file: the pack writes the env
#                                    keys its dictionary declares, and nothing
#                                    else, there - which is why a profile
#                                    applies to every session, however started.
#   ~/.claude/projects               only READ: the CLI's store of the folders a
#                                    session has run in (claude_project).

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
SAMPLE=$here/../profiles.sample

PROFILES=$HOME/.config/claude/profiles.json
SETTINGS=$HOME/.claude/settings.json
GLOBAL_ENV=$HOME/.config/zsh/gmake/.env.global
PROJECTS_STORE=$HOME/.claude/projects

# What a menu put back. A variable and not the return value of `$( )`: the
# Escape path has to exit the SCRIPT, and an exit inside a command substitution
# only leaves its subshell - the caller would read "Nothing chosen." as the
# choice.
PICKED=""

# Named before anything looks for it: called by make the PATH is zsh's (with
# ~/.local/bin), called by hand it is not - the answer would be "not installed"
# about a program that is right there.
export PATH="$HOME/.local/bin:$PATH"

# The pack's own path, never what `claude` on the PATH resolves to: WSL appends
# the Windows directories, so a Windows Claude Code is found from inside and
# would be reported as this instance's own. install.sh tests the same path.
launcher=$HOME/.local/bin/claude
claude_bin=""
[ -x "$launcher" ] && claude_bin=$launcher

# What the PATH finds instead, named only: the message has to say why.
foreign_bin=$(command -v claude 2>/dev/null || true)
[ "$foreign_bin" = "$launcher" ] && foreign_bin=""

# What an id may be: it lands in .env.global, where make trims a space, cuts at
# a `#` and ends the name at an `=`.
VALID_ID='^[A-Za-z0-9._-]+$'

die() {
    printf '❌ %s\n' "$*" >&2
    exit 1
}

# --- the dictionary -----------------------------------------------------------

# jq reads it, and nothing greps inside it: a file that does not parse is an
# error with a line number rather than a wrong value.
json_ok() {
    [ -f "$PROFILES" ] && jq -e . "$PROFILES" > /dev/null 2>&1
}

# Every id, one per line, in the file's order: what the menus show.
ids() {
    [ -f "$PROFILES" ] || return 0
    jq -r '(.profiles // [])[] | .id // empty' "$PROFILES" 2>/dev/null || true
}

# How many entries carry that id. It has to be exactly one: two entries with the
# same id are two answers to one question.
entries() {
    [ -f "$PROFILES" ] || { printf '0'; return 0; }
    jq -r --arg id "$1" '[ (.profiles // [])[] | select(.id == $id) ] | length' "$PROFILES" 2>/dev/null || printf '0'
}

valid_id() {
    printf '%s' "$1" | grep -qE "$VALID_ID"
}

# The entry, minus its two keys. Flat on purpose: the keys are the CLI's, so a
# block from a settings file goes in as it stands. An entry with nothing but an
# id gives {} - which takes another provider's keys back out.
profile_env() {
    jq -c --arg id "$1" '(.profiles // [])[] | select(.id == $id) | del(.id, .note)' "$PROFILES" 2>/dev/null
}

# Every key the pack may have written: everything the dictionary declares, plus
# the four known by name whatever the file says - an entry can be DELETED, and
# a base URL left behind with no credential is the one mistake this pack
# refuses to make. That list is what applying takes back before it writes, and
# what the removal uses.
owned_keys() {
    {
        printf 'ANTHROPIC_BASE_URL\nANTHROPIC_AUTH_TOKEN\nANTHROPIC_API_KEY\nANTHROPIC_MODEL\n'
        if [ -f "$PROFILES" ]; then
            jq -r '(.profiles // [])[] | del(.id, .note) | keys[]' "$PROFILES" 2>/dev/null || true
        fi
    } | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

# The env block's pack-owned keys, sorted so two runs compare byte for byte.
applied_env() {
    [ -f "$SETTINGS" ] || { printf '{}'; return 0; }
    jq -S -c '(.env // {}) | with_entries(select(.key | startswith("ANTHROPIC_")))' "$SETTINGS" 2>/dev/null || printf '{}'
}

# Replaces the keys the dictionary declares and keeps everything else - the
# statusLine, the permissions, the user's own CLAUDE_CODE_*. Mode 600: it holds
# a token now.
apply_env() {
    local want=$1 owned tmp dir
    owned=$(owned_keys)
    dir=$(dirname "$SETTINGS")
    install -d -m 0700 "$dir"
    tmp=$(mktemp)

    if [ ! -f "$SETTINGS" ]; then
        # A fresh instance that picks the login profile gets no settings file.
        [ "$want" = "{}" ] && { rm -f "$tmp"; return 0; }
        jq -n --argjson add "$want" '{ env: $add }' > "$tmp"
    else
        if ! jq --argjson add "$want" --argjson owned "$owned" '
                (.env // {}) as $env
                | .env = (($env | with_entries(select(.key as $k | ($owned | index($k)) == null))) + $add)
                | if .env == {} then del(.env) else . end
            ' "$SETTINGS" > "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            die "$SETTINGS does not parse: $(jq . "$SETTINGS" 2>&1 | head -n 1)"
        fi
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$SETTINGS"
}

# --- the variables ------------------------------------------------------------

env_var() {
    local line
    [ -r "$GLOBAL_ENV" ] || return 0
    line=$(grep -E "^[[:space:]]*$1=" "$GLOBAL_ENV" | tail -n 1 || true)
    printf '%s\n' "${line#*=}"
}

profile_var() {
    env_var CLAUDE_PROFILE
}

# One line of the socle's .env.global, and nothing else: replaced where it is,
# appended when the variable is not there yet. The value is an id (valid_id):
# no escaping needed.
write_env() {
    local name=$1 value=$2
    [ -f "$GLOBAL_ENV" ] || die "no $GLOBAL_ENV yet - 'gmake env_global_enable' builds it from the samples."
    if grep -qE "^[[:space:]]*$name=" "$GLOBAL_ENV"; then
        sed -i -E "s|^[[:space:]]*$name=.*|$name=$value|" "$GLOBAL_ENV"
    else
        printf '\n%s=%s\n' "$name" "$value" >> "$GLOBAL_ENV"
    fi
}

# --- the menu -----------------------------------------------------------------

# fzf, like the shell's other pickers, needs a terminal - a provider can be
# named instead.
pick() {
    local list choice status
    list=$(ids)
    [ -n "$list" ] || die "no provider in $PROFILES - gmake claude_edit_profiles opens it."
    if choice=$(printf '%s\n' "$list" | fzf --prompt="$1 > " --info=inline --layout=reverse); then
        [ -n "$choice" ] || die "no provider chosen."
        PICKED=$choice
    else
        status=$?
        # fzf exits 130 on Escape or Ctrl-C: a decision, not a failure - make
        # must not print "Error" over it. The exit lands in this shell, not in
        # a subshell - see PICKED.
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "no provider chosen - a menu needs a terminal. Name one instead: gmake claude_profile CLAUDE_PROFILE=<id>"
    fi
}

# --- the projects -------------------------------------------------------------

# $HOME spelled ~, and nothing else; the substitution reverses exactly.
short_path() {
    case "$1" in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
    esac
}

# One line per project, most recently used first, shaped for fzf:
#   <store dir> TAB <path> TAB <last session>  <short path>
# The first two fields are what a choice needs and fzf hides them both - the
# chosen line comes back whole, and `cut -f1`/`cut -f2` read them again.
#
# The store's directory names encode the path and cannot be decoded back, so
# the path is read INSIDE the session files (each carries its cwd). A folder
# gone from disk is not offered.
project_lines() {
    local dir newest cwd epoch when
    [ -d "$PROJECTS_STORE" ] || return 0

    for dir in "$PROJECTS_STORE"/*/; do
        [ -d "$dir" ] || continue
        # The newest session: when the project was last used, and any of its
        # files answers the same cwd. `find` and not `ls` (a name says nothing
        # about a filename), and the read is guarded: `head` closes a long pipe
        # early (SIGPIPE) under set -e.
        newest=$(find "${dir%/}" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null |
            sort -rn | head -n 1 | cut -d' ' -f2- || true)
        [ -n "$newest" ] || continue
        cwd=$(jq -r 'select(.cwd) | .cwd' "$newest" 2>/dev/null | head -n 1 || true)
        [ -n "$cwd" ] || continue
        [ -d "$cwd" ] || continue
        epoch=$(date -r "$newest" +%s 2>/dev/null || echo 0)
        when=$(date -r "$newest" '+%Y-%m-%d %H:%M' 2>/dev/null || true)
        printf '%s\t%s\t%s\t%s  %s\n' "$epoch" "${dir%/}" "$cwd" "$when" "$(short_path "$cwd")"
    done | sort -rn -k1,1 | cut -f2-
}

# The same picker and the same demand: a menu needs a terminal. $1 prompt,
# $2 first displayed field, $3 the list; the chosen line lands in PICKED, whole.
pick_line() {
    local choice status
    if choice=$(printf '%s\n' "$3" | fzf --prompt="$1 > " --info=inline --layout=reverse --with-nth="$2.."); then
        [ -n "$choice" ] || die "nothing chosen."
        PICKED=$choice
    else
        status=$?
        if [ "$status" -eq 130 ]; then
            printf 'Nothing chosen.\n'
            exit 0
        fi
        die "nothing chosen - a menu needs a terminal."
    fi
}

# The first words typed in a session, flattened and cut short - what the CLI's
# own picker shows. Tool results travel as user messages and are skipped, so
# the extraction can come out empty; jq's first() takes the first that has
# something.
session_preview() {
    jq -r '
        first(
            select(.type == "user")
            | .message.content
            | if type == "string" then .
              elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
              else empty end
            | gsub("\\s+"; " ")
            | select(. != "")
        ) // empty
    ' "$1" 2>/dev/null | cut -c1-70 || true
}

# One line per session, most recent first - so the line the menu starts on is
# what a plain --continue would have taken - then the door to a new one. The id
# is the session file's own name, what `claude --resume` takes.
session_lines() {
    local dir=$1 file id when preview body
    find "$dir" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null |
        sort -rn | cut -f2- |
        while read -r file; do
            [ -n "$file" ] || continue
            id=$(basename "$file" .jsonl)
            when=$(date -r "$file" '+%Y-%m-%d %H:%M' 2>/dev/null || true)
            preview=$(session_preview "$file")
            if [ -n "$preview" ]; then
                body="$when  $preview"
            else
                body="$when"
            fi
            printf '%s\t%s\n' "$id" "$body"
        done || true
    printf 'new\tstart a new session\n'
}

# --- the targets --------------------------------------------------------------

# The id into .env.global, then what it means into the settings - both, always.
cmd_profile() {
    local wanted=${1:-} want has_url has_key

    if [ -z "$wanted" ]; then
        pick "The provider to use"
        wanted=$PICKED
    fi
    valid_id "$wanted" || die "'$wanted' cannot be a provider id: letters, digits, dot, dash and underscore only."
    if ! json_ok; then
        die "no usable $PROFILES - gmake claude_edit_profiles creates it from the sample."
    fi
    case "$(entries "$wanted")" in
    1) ;;
    0) die "no provider '$wanted' in $PROFILES. It holds: $(ids | paste -sd' ' -). gmake claude_edit_profiles opens it." ;;
    *) die "'$wanted' appears more than once in $PROFILES - one entry per provider. gmake claude_edit_profiles opens it." ;;
    esac

    want=$(profile_env "$wanted")
    [ -n "$want" ] || die "could not read the profile '$wanted' out of $PROFILES."

    # The one mistake that costs: a base URL and no credential. The CLI sends
    # whatever credential it has there, and the one it always has is your
    # claude.ai login. Refused rather than written.
    has_url=$(printf '%s' "$want" | jq -r 'has("ANTHROPIC_BASE_URL")')
    has_key=$(printf '%s' "$want" | jq -r 'has("ANTHROPIC_AUTH_TOKEN") or has("ANTHROPIC_API_KEY")')
    if [ "$has_url" = "true" ] && [ "$has_key" != "true" ]; then
        die "the provider '$wanted' carries a base URL and no credential: it would send your claude.ai login to that address. Add an ANTHROPIC_AUTH_TOKEN to it (or an ANTHROPIC_API_KEY) - gmake claude_edit_profiles opens the file."
    fi

    write_env CLAUDE_PROFILE "$wanted"
    apply_env "$want"

    # One line, and the key list stays out of it: eleven variable names in a
    # row tell nobody anything.
    if [ "$want" = "{}" ]; then
        printf '✅ %s applied - no keys, your login is used.\n' "$wanted"
    else
        printf '✅ %s applied.\n' "$wanted"
    fi
}

cmd_edit_profiles() {
    local editor

    if [ ! -f "$PROFILES" ]; then
        install -d -m 0700 "$(dirname "$PROFILES")"
        install -m 600 "$SAMPLE" "$PROFILES"
        printf '📝 %s was created from the package sample - fill in your tokens.\n' "$PROFILES"
    fi
    if ! json_ok; then
        die "$PROFILES does not parse, and this will not open a broken file: $(jq . "$PROFILES" 2>&1 | head -n 1)"
    fi

    # Short on purpose: the file carries the rest in its "note" fields, where a
    # person reads while editing - JSON has no comments.
    printf 'ℹ️  Fill in profiles.json.\n'
    printf '\n'

    # $EDITOR when set (one command, no arguments), nano otherwise.
    editor=${EDITOR:-nano}
    eval "$editor \"\$PROFILES\""

    # What the editor left behind: jq says where and why when it does not
    # parse, and the ids are checked too. Nothing is read until both hold.
    if ! json_ok; then
        printf '⚠️  %s does not parse any more: %s\n' "$PROFILES" "$(jq . "$PROFILES" 2>&1 | head -n 1)" >&2
        printf '   gmake claude_edit_profiles opens it again - nothing is read from it until it does.\n' >&2
        return 1
    fi
    while read -r id; do
        [ -n "$id" ] || continue
        if ! valid_id "$id"; then
            printf "❌ %s: the id '%s' cannot be used - letters, digits, dot, dash and underscore only.\n" "$PROFILES" "$id" >&2
            return 1
        fi
        if [ "$(entries "$id")" != 1 ]; then
            printf "❌ %s: '%s' appears %s times - one entry per provider.\n" "$PROFILES" "$id" "$(entries "$id")" >&2
            return 1
        fi
    done < <(ids)
    printf '✅ %s: %s\n' "$PROFILES" "$(ids | paste -sd' ' -)"

    # And the provider to use, straight away: a token rotated in the file is
    # the one the next session uses, and a menu over the file cannot leave a
    # name that no longer exists in CLAUDE_PROFILE.
    #
    # Only with a terminal: tests run this with EDITOR=true.
    if [ -t 0 ] && [ -t 1 ]; then
        cmd_profile
    fi
}

# Two menus - the project, then its sessions, most recent preselected and a new
# one last. An existing session opens with `--resume`, both in the project's
# folder, and `exec` makes the session replace this script.
cmd_project() {
    local list line dir cwd sessions session

    [ -n "$claude_bin" ] || die "Claude Code is not installed in this instance - bash ~/.config/packs/claude/install.sh puts it back."

    list=$(project_lines)
    if [ -z "$list" ]; then
        printf 'This instance has no project yet: one appears here once a session has run in its folder.\n'
        return 0
    fi

    pick_line "The project to open" 3 "$list"
    line=$PICKED
    dir=$(printf '%s\n' "$line" | cut -f1)
    cwd=$(printf '%s\n' "$line" | cut -f2)
    [ -d "$cwd" ] || die "$cwd is gone - it was removed after the list was read."

    sessions=$(session_lines "$dir")
    pick_line "The session to open" 2 "$sessions"
    line=$PICKED
    session=$(printf '%s\n' "$line" | cut -f1)

    cd "$cwd" || die "cannot enter $cwd."
    if [ "$session" = "new" ]; then
        exec "$claude_bin"
    fi
    exec "$claude_bin" --resume "$session"
}

# --- the status ---------------------------------------------------------------

# Read in the order the CLI reads it: the settings' env block beats the shell,
# then the environment. Only the variable's NAME, never its value - a status
# showing a key is a leak with a friendly face.
access() {
    local name="" where=""

    if [ -f "$SETTINGS" ]; then
        name=$(jq -r '(.env // {}) | if has("ANTHROPIC_AUTH_TOKEN") then "ANTHROPIC_AUTH_TOKEN" elif has("ANTHROPIC_API_KEY") then "ANTHROPIC_API_KEY" else empty end' "$SETTINGS" 2>/dev/null || true)
        [ -n "$name" ] && where="in $SETTINGS"
    fi
    if [ -z "$name" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        name=ANTHROPIC_AUTH_TOKEN
        where="in the environment"
    fi
    if [ -z "$name" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        name=ANTHROPIC_API_KEY
        where="in the environment"
    fi

    if [ -n "$name" ]; then
        echo "  access     a key $where ($name) — nothing to log in to"
        return
    fi

    # No key: the stored login, which only the CLI knows (`|| true`: no login
    # exits non-zero - an answer, not a failure).
    #
    # The three answers are spelled out because the obvious short form is
    # wrong: in jq, `//` treats false as absent, so `.loggedIn // "unknown"`
    # answers "unknown" for a `loggedIn: false`.
    local auth answer
    auth=$("$claude_bin" auth status 2>/dev/null || true)
    answer=$(printf '%s' "$auth" |
        jq -r 'if .loggedIn == true then (.authMethod // "a login") elif .loggedIn == false then "none" else "unknown" end' 2>/dev/null || true)
    case "$answer" in
        none)    echo "  access     nothing yet — a key in the settings, or a login" ;;
        unknown) echo "  access     unknown — 'claude auth status' had nothing to say" ;;
        *)       echo "  access     a login ($answer)" ;;
    esac
}

# Where the requests go, from the same place as the key above.
endpoint() {
    local url=""

    if [ -f "$SETTINGS" ]; then
        url=$(jq -r '(.env // {}).ANTHROPIC_BASE_URL // empty' "$SETTINGS" 2>/dev/null || true)
    fi
    [ -z "$url" ] && url=${ANTHROPIC_BASE_URL:-}

    if [ -n "$url" ]; then
        echo "  endpoint   $url"
    else
        echo "  endpoint   the Anthropic API — no ANTHROPIC_BASE_URL set"
    fi
}

# The named provider, and whether the settings hold what it says: the second
# half catches a token rotated in the dictionary and not applied.
profile_line() {
    local id applied want

    id=$(profile_var)
    applied=$(applied_env)

    if [ -z "$id" ]; then
        if [ "$applied" = "{}" ]; then
            echo "  provider   none — gmake claude_profile picks one"
        else
            echo "  provider   none named — the settings hold a provider of their own"
        fi
        return
    fi
    if ! json_ok || [ "$(entries "$id")" != 1 ]; then
        echo "  provider   $id — no such entry in $PROFILES"
        return
    fi
    want=$(profile_env "$id" | jq -S -c .)
    if [ "$want" = "$applied" ]; then
        echo "  provider   $id — applied"
    else
        echo "  provider   $id — NOT applied, the settings hold something else"
        echo "             gmake claude_profile CLAUDE_PROFILE=$id writes it"
    fi
}

status() {
    echo ""
    echo "Claude Code, in this instance"
    echo ""

    # Absent while the pack's folder is still there: removed by hand, or an
    # install that did not finish - either way, install.sh puts it back.
    if [ -z "$claude_bin" ]; then
        echo "  ❌ Claude Code is not installed in this instance."
        if [ -n "$foreign_bin" ]; then
            # The case a WSL instance hits as soon as Windows has one: `claude`
            # answers, and it is not this one.
            echo "     Your PATH finds $foreign_bin instead - that one runs on Windows."
        fi
        echo "     Put the pack's own back:  bash ~/.config/packs/claude/install.sh"
        echo ""
        return 1
    fi

    echo "  program    $("$claude_bin" --version)"

    # The launcher is a symlink into the versions: the target is where the disk goes.
    local target
    target=$(readlink -f "$claude_bin" 2>/dev/null || true)
    if [ -n "$target" ] && [ "$target" != "$claude_bin" ]; then
        echo "  launcher   $claude_bin → $target"
    else
        echo "  launcher   $claude_bin"
    fi

    # One file per version, and the whole weight of the pack.
    if [ -d "$HOME/.local/share/claude/versions" ]; then
        local count size
        count=$(find "$HOME/.local/share/claude/versions" -maxdepth 1 -type f 2>/dev/null | wc -l)
        size=$(du -sh "$HOME/.local/share/claude/versions" 2>/dev/null | cut -f1)
        echo "  versions   $count on disk, $size — $HOME/.local/share/claude/versions"
    fi

    # What the CLI writes for itself, and what a removal leaves in place.
    if [ -d "$HOME/.claude" ]; then
        echo "  config     $HOME/.claude"
    else
        echo "  config     none yet — the first session writes it"
    fi

    profile_line
    access
    endpoint

    echo ""
}

case "${1:-}" in
    status)
        status
        ;;
    profile)
        shift
        cmd_profile "${1:-}"
        ;;
    edit_profiles)
        cmd_edit_profiles
        ;;
    project)
        cmd_project
        ;;
    *)
        echo "Usage: $(basename "$0") <status|profile|edit_profiles|project>" >&2
        exit 2
        ;;
esac
