# ==============================================================================
# FIREFOX - THE PRIVACY SETTINGS - WHAT THE TARGETS CALL
# ==============================================================================
# The manual switches. The profiles themselves are chosen by the launchers at
# every launch - `fox` light, `pfox` strict (docs/fox.md) - through the link
# the install leaves in the browser's directory, so a launch costs no
# password. `fox_tweak_on` puts the strict profile in place (and sets the link
# up if it never was - one sudo, once); `fox_tweak_off` takes everything out.
# They run from anywhere.

GATE_EXEMPT_GOALS += fox_tweak_on fox_tweak_off

# The script, resolved from this module's own path: make/ and bin/ are
# neighbours inside the pack folder, and the pack moves as one folder.
FOX := $(dir $(lastword $(MAKEFILE_LIST)))../bin/fox.sh

fox_tweak_on: ## Apply the strict privacy profile (fox/pfox pick one on their own)
	@$(FOX) on

fox_tweak_off: ## Take the profile out - the browser's own defaults again
	@$(FOX) off
