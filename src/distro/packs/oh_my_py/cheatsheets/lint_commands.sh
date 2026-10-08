# ==========================================
# LINT CHEATSHEET (RUFF & SHELLCHECK)
# ==========================================
# The lint targets of this pack (make/lint.mk). `ruff` comes with the pack;
# `shellcheck` is the image's. No `# requires:` header: the pack's folder is
# the switch, and a sheet that left with it cannot be missing its tool.

# --- 1. THE CHECKS ---
gmake lint                                   # Run all lint checks (Python + shell), non-destructive
gmake lint-py                                # Check Python code with ruff (PY_TARGETS="..." to scope)
gmake lint-sh                                # Check shell scripts with shellcheck (SH_TARGETS="..." to scope)

# --- 2. THE ONE THAT WRITES ---
gmake lint-format                            # Auto-fix and format Python code with ruff (refuses an uncommitted tree)
