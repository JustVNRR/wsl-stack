# ==============================================================================
# THE ENVIRONMENT FILES
# ==============================================================================
# Two files decide what a gmake target sees: ~/.config/zsh/gmake/.env.global
# for the values every project shares, the project's own .env for what
# identifies it. Both are assembled from samples — the shell's, in the folder
# above, and the ones the packs ship beside their modules.
#
# The commands never rewrite a line that is already there: a value you set, and
# a pack added later, survive the next run. With no readable sample at all they
# stop rather than leave an empty file behind.
#
# They are the shell's because the file they write is: this Makefile loads
# .env.global before it reads a single pack.
#
# The two env_global targets run from anywhere — machine-wide files, and no
# question about the directory you stand in: the gate must let them through.
GATE_EXEMPT_GOALS += env_global_enable env_global_manage

# The samples, in the order they are read: the shell's own first — it carries
# the header that explains the file and its rule — then every installed pack's.
# The shell's two sit outside PACKS_DIR, so none can be found twice.
GLOBAL_ENV_SAMPLES := $(THIS_DIR)/env.global.sample $(wildcard $(PACKS_DIR)/*/env.global.sample)
PROJECT_ENV_SAMPLES := $(THIS_DIR)/env.project.sample $(wildcard $(PACKS_DIR)/*/env.project.sample)

env_global_enable: ## Create or complete ~/.config/zsh/gmake/.env.global from the samples
	$(call merge_env_samples,$(THIS_DIR)/.env.global,$(GLOBAL_ENV_SAMPLES))

env_project_enable: ## Create or complete this project's .env from the samples
	$(call merge_env_samples,.env,$(PROJECT_ENV_SAMPLES))

# The same two files, opened instead of assembled: `$EDITOR`, or nano. Each
# merges first, so the editor never opens on an empty file.
env_global_manage: ## Create or complete ~/.config/zsh/gmake/.env.global, then open it in the editor
	$(call merge_env_samples,$(THIS_DIR)/.env.global,$(GLOBAL_ENV_SAMPLES))
	@editor=$${EDITOR:-nano}; $$editor "$(THIS_DIR)/.env.global"

env_project_manage: ## Create or complete this project's .env, then open it in the editor
	$(call merge_env_samples,.env,$(PROJECT_ENV_SAMPLES))
	@editor=$${EDITOR:-nano}; $$editor .env

# Macro 3: create or complete an environment file from the samples, in order —
# each carries its own header. Never rewrites an existing variable, and never
# writes from nothing.
#   $(1) the file to write   $(2) the samples to read
define merge_env_samples
	@target=$(1); \
	readable=; \
	for s in $(2); do [ -f "$$s" ] && readable="$$readable $$s"; done; \
	if [ -z "$$readable" ]; then \
		echo "No sample to read: neither the shell nor an installed pack ships one for this file."; \
		echo "Nothing was written - $$target is unchanged."; \
		exit 1; \
	fi; \
	if [ ! -f "$$target" ]; then \
		echo "Creating $$target from the samples..."; \
		: > "$$target"; \
		for s in $$readable; do cat "$$s" >> "$$target"; done; \
	else \
		added=0; \
		for s in $$readable; do \
			missing=$$(awk -F= 'FNR==NR { if ($$0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/) seen[$$1]=1; next } $$0 ~ /^[A-Za-z_][A-Za-z0-9_]*=/ && !($$1 in seen)' "$$target" "$$s"); \
			[ -z "$$missing" ] && continue; \
			if [ $$added -eq 0 ]; then \
				printf '\n# --- gmake variables added from the samples ---\n' >> "$$target"; \
				added=1; \
			fi; \
			printf '%s\n' "$$missing" >> "$$target"; \
		done; \
		if [ $$added -eq 0 ]; then \
			echo "$$target already defines every gmake variable - nothing to add."; \
		else \
			echo "Added the missing variables to $$target."; \
		fi; \
	fi
endef
