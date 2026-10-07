# ==============================================================================
# 🧹 LINT
# ==============================================================================
# Python: ruff, installed by this pack; rules per project in pyproject.toml
# ([tool.ruff]). Shell: shellcheck, a machine tool (apt-get install shellcheck).

PY_TARGETS ?= .
SH_TARGETS ?= .

# The scan roots default to the whole project: scope them on the command line,
# e.g. gmake lint PY_TARGETS="src/" SH_TARGETS="scripts/". Reading asks
# nothing; only lint-format writes, and it guards itself - see the target.

.PHONY: lint lint-py lint-sh lint-format

lint: lint-sh lint-py ## Run all checks (Python + shell), non-destructive

lint-py: ## Check Python code with ruff (optional: PY_TARGETS="...")
	@command -v ruff >/dev/null 2>&1 || { \
		echo "❌ ruff is not installed. Install: uv tool install ruff" >&2; \
		exit 1; \
	}
	@echo "🔍 Running Ruff on: $(PY_TARGETS)"
	ruff check --no-fix $(PY_TARGETS)
	ruff format --check $(PY_TARGETS)

lint-sh: ## Check shell scripts with shellcheck (optional: SH_TARGETS="...")
	@# The scan roots are resolved at RUN time, in a shell variable rather than a
	@# make-level shell call: make expands a whole recipe before any of its lines
	@# runs, and `make -n` would execute such a call instead of only printing it.
	@files=$$(find $(SH_TARGETS) -type f -name "*.sh" -not -path "*/.*/*" -not -path "*/venv/*" 2>/dev/null); \
	if [ -z "$$files" ]; then \
		echo "ℹ️  No shell scripts found to analyze."; \
	else \
		command -v shellcheck >/dev/null 2>&1 || { \
			echo "❌ shellcheck is not installed. Debian/Ubuntu/WSL: sudo apt-get install shellcheck — macOS: brew install shellcheck" >&2; \
			exit 1; \
		}; \
		echo "🔍 Running ShellCheck on: $$files"; \
		shellcheck -x $$files; \
	fi

lint-format: ## Auto-fix and format Python code with ruff (optional: PY_TARGETS="...")
	@command -v ruff >/dev/null 2>&1 || { \
		echo "❌ ruff is not installed. Install: uv tool install ruff" >&2; \
		exit 1; \
	}
	@# The only target that rewrites files, so it refuses to start on a tree that
	@# is not committed - ruff's edits would otherwise mix with work in progress.
	@# Nothing to mix with where there is no git repository yet: that case steps
	@# aside.
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		git diff --quiet -- . && git diff --cached --quiet -- . || { \
			echo "❌ Uncommitted changes - commit or stash them first, or ruff will rewrite files you are still working on." >&2; \
			exit 1; \
		}; \
	fi
	@echo "🧹 Formatting with Ruff on: $(PY_TARGETS)"
	ruff check --fix $(PY_TARGETS)
	ruff format $(PY_TARGETS)
