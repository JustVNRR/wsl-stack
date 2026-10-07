# ==============================================================================
# THE TUNNEL (WIREGUARD) - WHAT THE TARGETS CALL
# ==============================================================================
# One line per target, calling bin/vpn.sh - the menus and the decisions live
# there, not in a recipe. The server is an id in ~/.config/vpn/servers.json,
# and VPN_PROFILE says which; naming it on the command line skips the menu
# (`gmake vpn_up VPN_PROFILE=ch`).
# They run from anywhere: a tunnel is not a project's business.

GATE_EXEMPT_GOALS += vpn_status vpn_up vpn_up_from_list vpn_down vpn_server \
                     vpn_ks_on vpn_ks_off vpn_auto_on vpn_auto_off vpn_edit_profiles

# The script, resolved from this module's own path: make/ and bin/ are
# neighbours inside the pack folder, and the pack moves as one folder.
VPN := $(dir $(lastword $(MAKEFILE_LIST)))../bin/vpn.sh

# A server named on the command line - `gmake vpn_server VPN_PROFILE=ch`. From
# .env.global, the value would be the one this run is about to write.
NAMED_SERVER := $(if $(filter command line,$(origin VPN_PROFILE)),$(VPN_PROFILE))

vpn_status: ## Show the tunnel, the server, the kill switch, the DNS and the exit IP
	@$(VPN) status

vpn_up: ## Connect now - with the server VPN_PROFILE names, or the one you name
	@$(VPN) up $(VPN_PROFILE)

vpn_up_from_list: ## Connect now, picking the server from the JSON in a menu
	@$(VPN) up_from_list

vpn_down: ## Disconnect
	@$(VPN) down

vpn_server: ## Choose the server the distro starts with, and switch to it now
	@$(VPN) server $(NAMED_SERVER)

vpn_ks_on: ## Put the kill switch in the tunnel, and remount it
	@$(VPN) kill_switch on

vpn_ks_off: ## Take the kill switch out of the tunnel, and remount it
	@$(VPN) kill_switch off

vpn_auto_on: ## Bring the tunnel up when the distro starts
	@$(VPN) auto on

vpn_auto_off: ## Stop bringing it up with the distro
	@$(VPN) auto off

vpn_edit_profiles: ## Open the JSON of servers in the editor
	@$(VPN) edit_profiles
