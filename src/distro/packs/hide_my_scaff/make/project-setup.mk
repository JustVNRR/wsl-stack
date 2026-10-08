# ==============================================================================
# PROJECT SCAFFOLDING
# ==============================================================================
# The act: copy a template, finish the copy, and let the pack whose row it came
# from do its part. The tools are taken by uvx at the moment one of them runs,
# so nothing is installed here and nothing is left on the PATH.
#
# rlwrap, from the image: cookiecutter asks on a plain line with no editor in
# the process, so an arrow key's bytes land in the answer - rlwrap is that
# editor, put in front of the command. copier stays bare (questionary is a line
# editor of its own). No terminal test: in a pipe rlwrap hands the answer over
# untouched; the variable only guards an instance without rlwrap yet.
RLWRAP := $(shell command -v rlwrap 2>/dev/null)

# The part every project wants, whatever its language: the .env its own sample
# describes - copied once, an existing one never touched, nothing when there is
# no sample.
#
# The .envrc that sources a Python venv belongs to the pack that has one, with
# its `direnv allow`.
define scaffold_generic_after
	@cd $(PROJECT_NAME) && ( [ -f .env ] || [ ! -f .env.sample ] || { echo "📝 Creating ./.env from the project's .env.sample..."; cp .env.sample .env; } )
endef

# What the pack that curates the row adds is declared by that pack, beside the
# macro it names (SCAFFOLD_AFTER_oh_my_py := init_venv). $(call $(VAR)) is the
# trick: this file never spells a pack's step name, and a row that names none
# leaves the project copied and its .env written.
scaffold_after = $(if $(SCAFFOLD_AFTER_$(1)),$(call $(SCAFFOLD_AFTER_$(1))))

# ==============================================================================
# THE THREE TARGETS
# ==============================================================================
# These targets only run from ~/projects itself; the gate that enforces it
# reads this declaration - which is why the names are written here, beside the
# targets. A target nobody declares is treated as an ordinary one.
SCAFFOLD_GOALS += copier_project cruft_project ccds_project finish_scaffold

copier_project: ## Scaffold a project with Copier from ~/projects (fnew picker)
	$(call check_vars, PROJECT_NAME PROJECT_TEMPLATE_REPO)
	@echo "🏗️  Scaffolding project with Copier..."
	@uvx -q --from copier copier copy $(COPIER_REF_ARG) $(PROJECT_TEMPLATE_REPO) ./$(PROJECT_NAME)
	$(call scaffold_generic_after)
	$(call scaffold_after,$(TEMPLATE_PACK))
	@echo "✅ Project ready in $(PROJECT_NAME)/"

# Optional pinned template ref/tag: --vcs-ref for Copier, --checkout for Cruft
COPIER_REF_ARG = $(if $(PROJECT_TEMPLATE_VERSION),--vcs-ref $(PROJECT_TEMPLATE_VERSION),)
CHECKOUT_ARG = $(if $(PROJECT_TEMPLATE_VERSION),--checkout $(PROJECT_TEMPLATE_VERSION),)

cruft_project: ## Scaffold a project with Cruft/Cookiecutter from ~/projects (fnew picker)
	$(call check_vars, PROJECT_TEMPLATE_REPO)
	@echo "🏗️  Scaffolding project with Cruft..."
	@$(RLWRAP) uvx -q --from cruft cruft create $(PROJECT_TEMPLATE_REPO) $(CHECKOUT_ARG)
	CREATED_DIR=$$(command ls -td -- */ | head -n 1 | tr -d '/'); \
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) finish_scaffold PROJECT_NAME="$$CREATED_DIR" TEMPLATE_PACK=$(TEMPLATE_PACK)

# `ccds` asks for project_name and repo_name itself, so neither is passed - the
# directory it creates is found the way cruft's is. --accept-hooks yes answers
# its hook question, like copier and cruft. The package is
# `cookiecutter-data-science`; `ccds` the command inside it.
ccds_project: ## Scaffold a project with CCDS v2 from ~/projects (fnew picker)
	$(call check_vars, PROJECT_TEMPLATE_REPO)
	@echo "🏗️  Scaffolding project with ccds..."
	@$(RLWRAP) uvx -q --from cookiecutter-data-science ccds --accept-hooks yes $(CHECKOUT_ARG) -o . $(PROJECT_TEMPLATE_REPO)
	CREATED_DIR=$$(command ls -td -- */ | head -n 1 | tr -d '/'); \
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) finish_scaffold PROJECT_NAME="$$CREATED_DIR" TEMPLATE_PACK=$(TEMPLATE_PACK)

# For the two tools that create the folder themselves: the target above hands
# it the name it just found. Called with no name - the target typed by hand, or
# a template that created nothing - every step below would `cd` with no
# argument, which is $HOME, and the venv would land in the person's own
# directory. It refuses instead.
finish_scaffold:
	@[ -n "$(PROJECT_NAME)" ] || { echo "❌ No folder to finish — nothing was created, and nothing was done."; exit 1; }
	$(call scaffold_generic_after)
	$(call scaffold_after,$(TEMPLATE_PACK))
	@echo "✅ Project ready in $(PROJECT_NAME)/"
