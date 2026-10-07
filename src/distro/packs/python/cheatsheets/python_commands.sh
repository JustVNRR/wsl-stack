# ==========================================
# PYTHON & UV CHEATSHEET
# requires: uv
# ==========================================
# Offered only while uv is installed, which is to say while the python pack is:
# an instance without it has no uv at all, and none of these commands would run.
# The header is also what hides the sheet when the manager was removed by hand
# and the folder stayed.

# --- 1. PYTHON RUNTIME MANAGEMENT (UV PYTHON) ---
uv python list                               # List installed and available upstream Python versions
uv python install <VERSION>                  # Download and install a Python version (e.g. 3.12, 3.11)
uv python uninstall <VERSION>                # Remove an installed Python version
uv python pin <VERSION>                      # Pin directory Python version (writes to .python-version)
uv python find [VERSION]                     # Locate the binary path for an installed Python version

# --- 2. VIRTUAL ENVIRONMENTS (UV VENV) ---
uv venv                                      # Create virtual environment in '.venv' (uses active/pinned Python)
uv venv <NAME> --python <VERSION>            # Create custom-named venv with specific Python (e.g. uv venv .venv --python 3.12)
source .venv/bin/activate                    # Manual activation (fallback if direnv is not used)
deactivate                                   # Deactivate the currently active virtual environment
direnv reload                                # Force reload current environment configuration

# --- 3. PACKAGE MANAGEMENT (UV PIP) ---
# Note: Works automatically inside an active venv or detects a local .venv folder
uv pip install <PACKAGE>                     # Install a package from PyPI
uv pip install <PACKAGE>==<VERSION>          # Install an exact package version
uv pip install --upgrade <PACKAGE>           # Upgrade a package to its latest available release
uv pip uninstall <PACKAGE>                   # Uninstall a package from the environment
uv pip list                                  # List installed packages in the current environment
uv pip tree                                  # Display dependency tree for installed packages
uv pip freeze > requirements.txt             # Export pinned dependencies to requirements.txt
uv pip install -r requirements.txt           # Install all dependencies from a requirements file

# --- 4. ISOLATED CLI TOOLS (UV TOOL / UVX) ---
uv tool install <TOOL>                       # Install global CLI tool in isolation (e.g. copier, cruft, ruff)
uv tool list                                 # List all globally installed CLI tools
uv tool upgrade --all                        # Upgrade all installed tools to their latest version
uv tool uninstall <TOOL>                     # Remove an isolated CLI tool
uvx <TOOL> [ARGS]                            # Run a tool ephemerally without installing it (e.g. uvx ruff check .)

# --- 5. EXECUTION & SCRIPTS ---
uv run <FILE>.py                             # Run script automatically using the project's venv / dependencies
uv run python                                # Launch Python REPL within project environment context
uv run python -c "<CODE>"                    # Execute inline code within environment context