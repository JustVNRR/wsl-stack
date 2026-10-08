# ==========================================
# TESTS CHEATSHEET (PYTEST LANES)
# ==========================================
# The test targets of this pack (make/tests.mk). pytest is a project
# dependency, not a machine tool: install it per project with `uv add --dev
# pytest`, and run these from the project folder so its environment is active.
# A `# requires: pytest` header would hide the sheet, since pytest is never on
# the machine's PATH - the pack's folder is the switch.

# --- 1. THE LANES ---
gmake test                                   # Run the whole test suite
gmake test-fast                              # Run fast tests only, without external infrastructure (CI lane)
gmake test-functional                        # Run functional tests (real local infra needed, e.g. .env, Docker, model)
gmake test-gcp                               # Run tests hitting a real GCP environment (test/staging/prod)
