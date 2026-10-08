# ============================================================
# FZF CONFIGURATION (ENGINES & UI)
# ============================================================

# --- 1. Default Traversal Engines ---
export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --strip-cwd-prefix'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# --- 2. Global UI Layout ---
export FZF_DEFAULT_OPTS='
  --height=60%
  --layout=reverse
  --border=rounded
  --prompt="> "
  --pointer="> "
  --preview-window=right:65%:wrap:border-left
'

# --- 3. Preview Hooks ---
export _FZF_PREVIEW_CMD='batcat --color=always --style=plain,numbers --line-range=:500 {}'
export _FZF_PREVIEW_DIR='eza --tree --level=2 --color=always --icons {}'
export FZF_CTRL_T_OPTS="--preview '$_FZF_PREVIEW_CMD'"
