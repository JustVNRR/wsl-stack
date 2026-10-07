# ==============================================================================
# THE GMAKE MAKEFILE - THE ENVIRONMENT, THE MODULES, THE MENU, THE GATE
# ==============================================================================

# Where this file lives, and the packs: `packs/` next to `zsh/` in the
# repository is `~/.config/packs` next to `~/.config/zsh` in the instance.
THIS_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
PACKS_DIR := $(abspath $(THIS_DIR)/../../packs)

# 1. THE ENVIRONMENT: .env.global first, then the project's .env over it.

-include $(THIS_DIR)/.env.global

# A variable that decides WHICH project a command targets is refused this
# early: in .env.global it would silently retarget every command run outside a
# project directory. Each pack declares its own in its pack.conf, and the
# declarations are read with sed - before any pack is allowed to define
# anything, and so a commented line is not mistaken for one.
PACK_IDENTIFYING_VARS := $(shell sed -n 's/^PACK_IDENTIFYING_VARS *:=[[:space:]]*//p' $(PACKS_DIR)/*/pack.conf 2>/dev/null)
$(foreach var,$(PACK_IDENTIFYING_VARS),$(if $(filter file,$(origin $(var))),$(error ❌ ERROR: Variable $(var) identifies a project — it belongs in that project's .env, never in .env.global)))

-include .env

# Whether a project .env was found here (drives the warnings in check_vars).
PROJECT_ENV := $(wildcard .env)

# 2. Every variable reaches the recipes' subshells.
export

# 3. THE MODULES: the socle's own in make/*.mk, every installed pack's in
# packs/*/make/*.mk. Adding one is creating a file - nothing to edit here.
# `gmake help` and Tab read the modules' TEXT: a module that is not loaded
# carries no line, so the menu follows the machine by itself.
CORE_MODULES := $(wildcard $(THIS_DIR)/make/*.mk)
PACK_MODULES := $(wildcard $(PACKS_DIR)/*/make/*.mk)

include $(CORE_MODULES)
include $(PACK_MODULES)

# 4. THE LOCATION GATE: operational targets run from the root of a project
# under ~/projects, scaffolding targets from ~/projects itself, and the rest
# from anywhere. A pack declares its own, in the module that defines them;
# GMAKE_ANYWHERE=1 bypasses the gate.
#
# After the includes on purpose, and with `+=`: `$(error)` fires when make
# READS the line, so the gate can only know what a pack declares once the
# modules are in - and a plain `=` here would erase what they appended.
GATE_EXEMPT_GOALS += help packs_list
ifneq (,$(filter $(SCAFFOLD_GOALS),$(MAKECMDGOALS)))
ifeq (,$(GMAKE_ANYWHERE))
ifneq ($(HOME)/projects,$(CURDIR))
$(error ❌ ERROR: Scaffolding runs from ~/projects itself (current directory: $(CURDIR)) — set GMAKE_ANYWHERE=1 to bypass)
endif
endif
endif
ifneq (,$(filter-out $(GATE_EXEMPT_GOALS) $(SCAFFOLD_GOALS),$(MAKECMDGOALS)))
ifeq (,$(GMAKE_ANYWHERE))
ifneq ($(HOME)/projects,$(patsubst %/,%,$(dir $(CURDIR))))
$(error ❌ ERROR: gmake targets run from the root of a project under ~/projects (current directory: $(CURDIR)) — set GMAKE_ANYWHERE=1 to bypass)
endif
endif
endif

# 5. THE MENU: one line per target, from the `##` sentences the modules carry.
.DEFAULT_GOAL := help
help: ## Show this help menu
	@awk 'BEGIN { printf "\nUsage:\n  make $(C_TITLE)<target>$(C_RESET)\n\nTargets:\n" }'
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(C_TITLE)%-30s$(C_RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | sort -f

# The macros a target calls - check_vars, confirm_action, the .env merge - live
# in the modules, beside the targets that use them.
