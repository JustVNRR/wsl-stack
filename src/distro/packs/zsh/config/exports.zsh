# ============================================================
# ENVIRONMENT VARIABLES (BASE TEMPLATE)
# ============================================================

# 1. Standard Locales
export LANG=en_US.UTF-8

# 2. Default Editor
if command -v code >/dev/null 2>&1; then
  export EDITOR="code --wait"
else
  export EDITOR="nano"
fi
export VISUAL="$EDITOR"

# 3. Prompt Configuration Path (XDG Compliant)
export STARSHIP_CONFIG="$HOME/.config/zsh/prompts/starship.toml"

# 4. User Binaries (XDG Standard)
export PATH="$HOME/.local/bin:$PATH"