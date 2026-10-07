# ==============================================================================
# WHAT A TARGET SAYS BEFORE IT RUNS
# ==============================================================================
# The two macros every module that writes a target uses: one refuses to run
# when a variable it needs is unset, the other prints what the target is about
# to touch and waits for a yes. A pack that writes a target uses them and
# declares nothing.
#
# A PACK MUST NEVER DEFINE EITHER. The socle's modules are read first, so a
# pack's own `define check_vars` would win in silence and every target that
# calls it - its neighbours' included - would lose its check. The CI greps for
# it on every push; a comment cannot notice.
#
# Defined, never run here: everything expands at the moment a recipe calls it.

# Macro 1: every variable named must be set — the error says when no project
# .env was found. A warning first when the values come only from .env.global.
define check_vars
	$(foreach var,$(1),$(if $(value $(var)),,$(error ❌ ERROR: Variable $(var) is required but unset$(if $(PROJECT_ENV),, (no .env in this directory — only .env.global is loaded)))))
	@if [ -z "$(PROJECT_ENV)" ] && [ -z "$(strip $(foreach var,$(1),$(if $(filter command line,$(origin $(var))),x)))" ]; then \
		echo "⚠️  No .env in this directory — values in effect come from .env.global or the environment only."; \
	fi
endef

# Macro 2: print the target's variables, then wait for a yes.
define confirm_action
	@echo "\n⚠️  TARGET ACTION: $(1)"
	@$(foreach var,$(2),printf " 🔹 $(var) : $(C_HINT)%s$(C_RESET)\n" "$($(var))";)
	@read -p "Confirm execution? [y/N] " ans; \
	if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then echo "\n❌ Operation cancelled by user." >&2; exit 1; fi
endef
