# ==============================================================================
# THE VIRTUAL ENVIRONMENT
# ==============================================================================
# What the python pack adds once the scaffolding act copied a template and
# wrote the project's .env. The act itself (the picker, the targets) is the
# scaffold pack's, which calls this macro through the declaration below.

# init_venv: detect the project's dependency manifest and bootstrap its
# environment:
#   1. uv.lock or a PEP 621 [project] table  ->  uv sync
#   2. requirements.txt                       ->  uv venv + uv pip install
#      (+ requirements_dev.txt)
#   3. no recognized manifest                 ->  bare uv venv, with a warning
#
# Branch 2: its line ends with the test on requirements_dev.txt, and a false
# test with no else returns 0 - a failing install above it would be swallowed
# as a success, which the `|| exit 1` next to it prevents.
#
# The direnv hook writes over nothing that is already there: ours - the line
# that activates this venv, with the guard that keeps it quiet before the first
# uv sync - only where no .envrc exists. Another template's is its own business.
define init_venv
	@if [ -f $(PROJECT_NAME)/uv.lock ] || { [ -f $(PROJECT_NAME)/pyproject.toml ] && grep -qx '\[project\]' $(PROJECT_NAME)/pyproject.toml; }; then \
		echo "🐍 uv project detected (uv.lock or [project] table) — running uv sync..."; \
		cd $(PROJECT_NAME) && uv sync; \
	elif [ -f $(PROJECT_NAME)/requirements.txt ]; then \
		echo "🐍 Creating virtual environment..."; \
		cd $(PROJECT_NAME) && uv venv; \
		echo "📦 Installing dependencies (requirements.txt)..."; \
		uv pip install -r requirements.txt || exit 1; \
		if [ -f requirements_dev.txt ]; then \
			echo "📦 Installing dev dependencies (requirements_dev.txt)..."; \
			uv pip install -r requirements_dev.txt; \
		fi; \
	else \
		echo "⚠️  No dependency manifest found (uv.lock / pyproject.toml [project] / requirements.txt)."; \
		echo "   Creating a bare venv — install your dependencies manually."; \
		cd $(PROJECT_NAME) && uv venv; \
	fi
	@echo "🪄 Configuring direnv..."
	@cd $(PROJECT_NAME) && ( [ -f .envrc ] || echo "[ -f .venv/bin/activate ] && source .venv/bin/activate" > .envrc ) && direnv allow
endef

# What runs once a template has been copied is declared by the pack that curates
# the row, here, beside the macro it names - so the two cannot drift apart. The
# scaffold pack reads the declaration off the row `fnew` picked and calls it;
# called directly, the target names the pack in TEMPLATE_PACK. Nothing else
# writes the name of this macro anywhere.
SCAFFOLD_AFTER_python := init_venv
