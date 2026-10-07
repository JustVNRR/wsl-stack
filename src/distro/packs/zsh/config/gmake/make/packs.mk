# ==============================================================================
# THE PACKS THIS INSTANCE CARRIES
# ==============================================================================
# A pack is installed when its folder is in ~/.config/packs - the folder IS the
# state. One line per pack, from its own pack.conf: the name and the
# description, nothing else - what a pack brings is what `gmake help` and the
# picker are for.
#
# It lists what the user CHOSE: a pack marked PACK_VISIBLE := no is a shared
# dependency of the packs that require it, so the list answers "what did I ask
# for?". What it cannot say is what is AVAILABLE - that is `.\wsl.ps1 add_pack`,
# from Windows, which is also where a pack arrives or leaves.

packs_list: ## List the packs this instance carries
	@if [ ! -d "$(PACKS_DIR)" ] || [ -z "$$(ls -A "$(PACKS_DIR)" 2>/dev/null)" ]; then \
		echo ""; \
		echo "No pack currently installed."; \
		echo ""; \
		printf '$(C_MUTED)Packs are managed from Windows (.\\wsl.ps1)$(C_RESET)\n'; \
	else \
		echo ""; \
		echo "Packs currently installed:"; \
		echo ""; \
		chosen=0; \
		for dir in "$(PACKS_DIR)"/*/; do \
			[ -f "$${dir}pack.conf" ] || continue; \
			visible=$$(sed -n 's/^PACK_VISIBLE *:=[[:space:]]*//p' "$${dir}pack.conf"); \
			[ "$$visible" = "no" ] && continue; \
			name=$$(basename "$$dir"); \
			desc=$$(sed -n 's/^PACK_DESCRIPTION *:=[[:space:]]*//p' "$${dir}pack.conf"); \
			printf "  $(C_TITLE)%-10s$(C_RESET) %s\n" "$$name" "$$desc"; \
			chosen=$$((chosen + 1)); \
		done; \
		if [ $$chosen -eq 0 ]; then \
			echo "  These packs are dependencies."; \
			echo "  Packs that required them are gone."; \
		fi; \
		echo ""; \
		printf '$(C_MUTED)Packs are managed from Windows (.\\wsl.ps1)$(C_RESET)\n'; \
	fi
