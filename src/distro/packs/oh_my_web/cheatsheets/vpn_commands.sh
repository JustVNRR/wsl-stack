# ==========================================
# TUNNEL CHEATSHEET (wireguard)
# requires: wg
# ==========================================
# The `oh_my_web` pack's tunnel: your servers are in ~/.config/vpn/servers.json, its
# settings in ~/.config/zsh/gmake/.env.global, and /etc/wireguard/vpn.conf is
# written from both before every mount - read, never edited. Offered only while
# the tools are installed: the `# requires:` line above hides the sheet once
# they were removed by hand.

# --- 1. THE TUNNEL (gmake) ---
gmake vpn_status                               # Up or down, the server, the kill switch, the DNS, the exit IP
gmake vpn_up                                   # Connect, with the server VPN_PROFILE names
gmake vpn_up VPN_PROFILE=ch                    # ... or name another for this one call
gmake vpn_up_from_list                         # Connect, picking the server from the JSON in a menu
gmake vpn_down                                 # Disconnect
gmake vpn_server                               # Choose the server the distro starts with (menu)
gmake vpn_server VPN_PROFILE=ch                # ... or name it, and skip the menu
gmake vpn_ks_on                                # Put the kill switch in (this instance only), and remount
gmake vpn_ks_off                               # Take it out - sweeps the rules, tunnel or not
gmake vpn_auto_on                              # Bring the tunnel up when the distro starts
gmake vpn_auto_off                             # Stop bringing it up with the distro

# --- 2. THE SERVERS ---
gmake vpn_edit_profiles                        # The JSON of servers, in nano ($EDITOR wins when set)
jq . ~/.config/vpn/servers.json                # What it holds, when you want to read it
jq -r '.servers[].id' ~/.config/vpn/servers.json   # Just the ids, one per line

# --- 3. THE SETTINGS ---
grep -E 'VPN_|BASE_DNS' ~/.config/zsh/gmake/.env.global  # the pack's settings
gmake env_global_enable                        # Adds what the samples carry and the file lacks

# --- 4. WHAT IS REALLY HAPPENING ---
sudo wg show                                   # The interface, its peer, the last handshake
sudo cat /etc/wireguard/vpn.conf               # What the pack generated - a read, never an edit
cat /etc/resolv.conf                           # the tunnel's DNS while up, BASE_DNS while down
curl -s https://api.ipify.org                  # The exit IP the world sees
sudo iptables -S OUTPUT | head -3              # The kill switch, while a tunnel is up
tail -20 /var/log/web-vpn.log                  # What the boot hook tried, and why it stopped
