# ==============================================================================
# THE MAKE COLOURS
# ==============================================================================
# The gmake side of zsh/lib/colours.sh - make cannot read a shell file, so the
# codes are spelled here too; a colour changed in one file is changed in the
# other. A recipe asks for a ROLE, never for a colour.
#
# No comment on a value's own line, and no `##` in this file: make keeps the
# blanks that precede a `#` in the value (one stray space would shift every
# line of `gmake help`), and a `##` would offer the file in the menu and on Tab.
C_TITLE := \033[36m
C_COMMAND := \033[32m
C_HINT := \033[33m
C_MUTED := \033[90m
C_RESET := \033[0m

# A block title - the `=== ... ===` lines of wsl_status: a blank line, the
# title in cyan, a newline. One macro rather than a printf per call: the shape
# is the same for every title.
define title
	printf '\n$(C_TITLE)=== %s ===$(C_RESET)\n' "$(1)"
endef
