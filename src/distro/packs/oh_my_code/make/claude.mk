# ==============================================================================
# CLAUDE CODE
# ==============================================================================
# The pack's targets, one line each, calling bin/claude.sh where the reading,
# the deciding and the wording live.
#
# What a target may run, and where it may run from, is this file's only
# declaration: GATE_EXEMPT_GOALS, read by the location gate after every module
# is loaded - which is why it sits here, beside the targets it names. All four
# are exempt: the provider and the project are the machine's business, asked
# from wherever you stand.

GATE_EXEMPT_GOALS += claude_status claude_profile claude_edit_profiles claude_project

# The script, from this module's own path: make/ and bin/ are neighbours, and
# the pack moves as one folder.
CLAUDE := $(dir $(lastword $(MAKEFILE_LIST)))../bin/claude.sh

# A provider named on the command line applies that one and skips the menu.
# Read from the command line only: from .env.global it would be the value the
# run is about to write back.
NAMED_PROFILE := $(if $(filter command line,$(origin CLAUDE_PROFILE)),$(CLAUDE_PROFILE))

claude_status: ## Show Claude Code here: version, the versions on disk, the provider in force
	@$(CLAUDE) status

claude_profile: ## Choose the provider this instance talks to, and apply it
	@$(CLAUDE) profile $(NAMED_PROFILE)

claude_edit_profiles: ## Open the dictionary of providers in the editor
	@$(CLAUDE) edit_profiles

claude_project: ## Pick a project of this instance, and reopen its last session
	@$(CLAUDE) project
