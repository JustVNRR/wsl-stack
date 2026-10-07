#!/usr/bin/env bash
# ==============================================================================
# CLAUDE CODE'S STATUS LINE, IN THIS INSTANCE
# ==============================================================================
# Two rows: the folder is the one value whose length nobody controls, and on a
# single row it pushed the context off the screen. Row 1 holds the short
# values; row 2 ends with the folder.
#
# The CLI hands the session's JSON on stdin. install.sh writes this script into
# ~/.claude/settings.json as the statusLine, once, and never over one already
# there; remove.sh takes back exactly this one.
#
# Everything below the SHARED line is byte-for-byte the same as the copy on
# Windows, in ~/.claude/statusline-command.sh: one code, two machines.
#
# ==============================================================================
# SHARED - the same file on both machines, from this line down
# ==============================================================================

# ----------------------------------------------------------------------------
# JSON
# ----------------------------------------------------------------------------
# One call, eight fields, when jq is there: the line redraws at every message,
# and a jq per field was eight processes per redraw. Where jq is missing - Git
# Bash on Windows has none - the same eight names are filled by grep and sed.
# Both paths must stay in step, and the fallback is the half that is never
# exercised where the work happens: it is what breaks when a field moves.

input=$(cat)

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

if [ "$HAVE_JQ" = 1 ]; then
  eval "$(
    printf '%s' "$input" | jq -r '
      def s: if . == null then "" else tostring end;

      @sh "model=\(.model.display_name // .model.id | s)",
      @sh "dir_real=\(.workspace.current_dir // .cwd | s)",
      @sh "used=\(.context_window.used_percentage | s)",
      @sh "toks=\(.context_window.total_input_tokens | s)",
      @sh "size=\(.context_window.context_window_size | s)",
      @sh "effort=\(.effort.level | s)",
      @sh "pr_num=\(.pr.number | s)",
      @sh "pr_state=\(.pr.review_state | s)"
    ' 2>/dev/null
  )"
else
  # json_str <key> / json_num <key>: the KEY alone. Reading a second argument
  # is the bug that made every value empty and the whole line disappear.
  json_str() {
    printf '%s' "$input" |
      sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
      head -n 1 |
      sed 's/\\"/"/g; s/\\\\/\\/g'
  }

  json_num() {
    printf '%s' "$input" |
      grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]*" |
      head -n 1 |
      sed 's/.*:[[:space:]]*//'
  }

  model=$(json_str display_name)
  [ -n "$model" ] || model=$(json_str id)

  dir_real=$(json_str current_dir)
  [ -n "$dir_real" ] || dir_real=$(json_str cwd)

  used=$(json_num used_percentage)
  toks=$(json_num total_input_tokens)
  size=$(json_num context_window_size)

  effort=$(json_str level)
  pr_num=$(json_num number)
  pr_state=$(json_str review_state)
fi

# ----------------------------------------------------------------------------
# APPEARANCE
# ----------------------------------------------------------------------------
# Nerd Font glyphs, written as octal escapes on purpose: $'\uXXXX' does not
# expand under a locale that is not UTF-8 (measured in Git Bash, where the
# icons printed as the literal text), and the raw characters do not survive
# every editor. ICONS=0 is for a terminal without such a font.
#
# No prefix in the texts beside them (the venv is ".venv", not "py: .venv"):
# the icon is where the word lives, so the ASCII set cannot double it.

ICONS=1

if [ "$ICONS" = 1 ]; then
  icon_model=$(printf '\357\225\204')    # robot,      U+F544
  icon_dir=$(printf '\357\201\273')      # folder,     U+F07B
  icon_ctx=$(printf '\357\207\200')      # database,   U+F1C0
  icon_venv=$(printf '\357\217\242')     # python,     U+F3E2
  icon_branch=$(printf '\357\204\246')   # code-fork,  U+F126
  icon_effort=$(printf '\357\203\247')   # bolt,       U+F0E7
  icon_pr=$(printf '\357\202\233')       # github,     U+F09B
  icon_provider=$(printf '\357\207\246') # plug,       U+F1E6
else
  icon_model=">"
  icon_dir="@"
  icon_ctx="%"
  icon_venv="py:"
  icon_branch="git:"
  icon_effort="~"
  icon_pr="#"
  icon_provider="api:"
fi

# ----------------------------------------------------------------------------
# PATH
# ----------------------------------------------------------------------------
# Two forms of the same path: the real one, for looking things up (git, a
# project's venv), and the short one for the row, with $HOME spelled ~. Looking
# up under the short form is a bug that hides well - bash does not expand a ~
# inside a variable, so a project under the home directory would show neither
# its branch nor its venv.

dir="$dir_real"
case "$dir" in
  "$HOME") dir="~" ;;
  "$HOME"/*) dir="~${dir#"$HOME"}" ;;
esac

# Display-only shortening: the middle keeps a head and a tail, which is what a
# path is read for. The real path is untouched everywhere else.
shorten_path() {
  local p="$1"
  local max="${2:-72}"

  [ -n "$p" ] || return 0
  [ "${#p}" -le "$max" ] && { printf '%s' "$p"; return 0; }

  local last="${p##*/}"
  local parent="${p%/*}"
  local keep=$((max - ${#last} - 5))

  if [ "$keep" -lt 8 ]; then
    printf '…/%s' "$last"
  else
    printf '%s…/%s' "${parent:0:$keep}" "$last"
  fi
}

dir=$(shorten_path "$dir")

# ----------------------------------------------------------------------------
# GIT
# ----------------------------------------------------------------------------

branch=""
if [ -n "$dir_real" ]; then
  branch=$(git --no-optional-locks -C "$dir_real" branch --show-current 2>/dev/null)
  # Detached HEAD: the short sha is what there is to show.
  [ -n "$branch" ] || branch=$(git --no-optional-locks -C "$dir_real" rev-parse --short HEAD 2>/dev/null)
fi

# ----------------------------------------------------------------------------
# PULL REQUEST
# ----------------------------------------------------------------------------
# Given by the CLI for the branch's PR. The state keeps one word:
# "changes_requested" is longer than the number it belongs to.

pr=""
if [ -n "$pr_num" ]; then
  case "$pr_state" in
    changes_requested) pr_state="changes" ;;
    "") pr_state="pending" ;;
  esac
  pr="#$pr_num $pr_state"
fi

# ----------------------------------------------------------------------------
# PROVIDER
# ----------------------------------------------------------------------------
# Which provider the pack has in force - its own line, read where gmake reads
# it. Empty on a machine that has no such file (Windows), and the segment then
# simply does not appear.

provider=""
if [ -r "$HOME/.config/zsh/gmake/.env.global" ]; then
  provider=$(sed -n 's/^CLAUDE_PROFILE=//p' "$HOME/.config/zsh/gmake/.env.global" | tail -n 1)
fi

# ----------------------------------------------------------------------------
# CONTEXT
# ----------------------------------------------------------------------------
# 86000 -> 86k: two numbers nobody reads to the last digit.

fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n < 1000) printf "%d", n
    else if (n < 1000000) printf "%.0fk", n / 1000
    else printf "%.1fM", n / 1000000
  }'
}

ctx=""
pct=""
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  if [ -n "$toks" ] && [ -n "$size" ]; then
    ctx="$(fmt_tokens "$toks")/$(fmt_tokens "$size") (${pct}%)"
  else
    ctx="${pct}%"
  fi
fi

# The one colour that means something: how full the window is.
context_colour() {
  if awk -v p="$1" 'BEGIN { exit !(p < 50) }'; then
    printf '\033[92m'   # green
  elif awk -v p="$1" 'BEGIN { exit !(p <= 75) }'; then
    printf '\033[93m'   # yellow
  else
    printf '\033[91m'   # red
  fi
}

# ----------------------------------------------------------------------------
# PYTHON ENVIRONMENT
# ----------------------------------------------------------------------------
# An activated one first, then the project's own .venv or venv - the same two
# the python pack's projects use.

venv=""
if [ -n "$VIRTUAL_ENV" ]; then
  venv=$(basename "$VIRTUAL_ENV")
elif [ -n "$CONDA_DEFAULT_ENV" ]; then
  venv="$CONDA_DEFAULT_ENV"
elif [ -n "$dir_real" ]; then
  for v in .venv venv; do
    if [ -f "$dir_real/$v/pyvenv.cfg" ]; then
      venv="$v"
      break
    fi
  done
fi

# ----------------------------------------------------------------------------
# COLOURS
# ----------------------------------------------------------------------------

c_reset=$'\033[0m'
c_model=$'\033[96m'                  # cyan
c_dir=$'\033[37m'                    # white
c_branch=$'\033[92m'                 # green
c_venv=$'\033[95m'                   # magenta
c_effort=$'\033[90m'                 # grey: secondary
c_pr=$'\033[90m'                     # grey: secondary
c_provider=$'\033[95m'               # magenta: the pack's own line
c_ctx=$'\033[37m'                    # neutral until there is a percentage
[ -n "$pct" ] && c_ctx=$(context_colour "$pct")

# ----------------------------------------------------------------------------
# RENDERING
# ----------------------------------------------------------------------------
# No separators on purpose: two spaces group the segments, and the colours do
# the rest. A segment that has nothing to say is the empty string - never a
# bare escape code, which a test for "is there anything here" reads as a value.

seg() {
  [ -n "$2" ] || return 0
  printf '%s%s %s%s' "$3" "$1" "$2" "$c_reset"
}

row() {
  local out="" part
  for part in "$@"; do
    [ -n "$part" ] || continue
    [ -n "$out" ] && out="$out  "
    out="$out$part"
  done
  printf '%s\n' "$out"
}

# Row 1 - what is running, and how full it is.
row \
  "$(seg "$icon_model" "$model" "$c_model")" \
  "$(seg "$icon_effort" "$effort" "$c_effort")" \
  "$(seg "$icon_ctx" "$ctx" "$c_ctx")"

# Row 2 - where it runs, on what, and on which provider. The folder is last,
# and the provider first when there is one.
row \
  "$(seg "$icon_provider" "$provider" "$c_provider")" \
  "$(seg "$icon_venv" "$venv" "$c_venv")" \
  "$(seg "$icon_branch" "$branch" "$c_branch")" \
  "$(seg "$icon_pr" "$pr" "$c_pr")" \
  "$(seg "$icon_dir" "$dir" "$c_dir")"
