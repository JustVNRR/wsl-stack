# ============================================================
# PYTHON RUNTIME: UV
# ============================================================
# The shell reads it where it lives; nothing is copied.

# uv's tools (copier, cruft...) live here.
export PATH="$HOME/.local/bin:$PATH"

# The pack's own uv path, never what `uv` on the PATH resolves to: the PATH
# carries the Windows directories, and a Windows program would run at every
# shell start.
if [ -x "$HOME/.local/bin/uv" ]; then
    eval "$("$HOME/.local/bin/uv" generate-shell-completion zsh)"
    eval "$("$HOME/.local/bin/uvx" --generate-shell-completion zsh 2>/dev/null)"
fi
