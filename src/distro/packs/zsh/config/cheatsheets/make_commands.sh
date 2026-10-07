# ==========================================
# MAKEFILE CHEATSHEET (the gmake targets)
# ==========================================
# The shell's gmake targets: the ones that need no pack. A pack brings its
# targets and its sheet together, in its own folder.

# --- 1. PACKS ---
gmake packs_list                             # List the packs this instance carries

# --- 2. ENVIRONMENT FILES (.env.global / .env) ---
gmake env_global_enable                      # Create or complete the machine-wide .env.global from the samples
gmake env_global_manage                      # Create or complete it, then open the machine-wide .env.global in the editor
gmake env_project_enable                     # Create or complete this project's .env from the samples
gmake env_project_manage                     # Create or complete it, then open this project's .env in the editor

# --- 3. WSL CONFIGURATION AND STATUS (/etc/wsl.conf, /etc/resolv.conf) ---
gmake wsl_config                             # Open /etc/wsl.conf in nano (sudo): default user, automount, interop
gmake dns_resolve                            # Open /etc/resolv.conf in nano (sudo)
gmake fstab_config                           # Open /etc/fstab in nano (sudo): the mounts to apply at start
gmake wsl_status                             # Show what this instance runs on (base image, init, WSL's files, memory)

# --- 4. THE SWITCHES (they take effect at the next start) ---
gmake systemd_up                             # Install systemd and turn it on for this instance (a restart boots it)
gmake systemd_down                           # Stop booting systemd (the packages stay installed)
gmake automount_up                           # Mount the Windows drives under /mnt at every start
gmake automount_down                         # Stop mounting the Windows drives
gmake interop_up                             # Let the instance run Windows programs
gmake interop_down                           # Stop running Windows programs from the instance
gmake windows_path_up                        # Add the Windows PATH to this instance's PATH
gmake windows_path_down                      # Keep the Windows PATH out of this instance's PATH (interop stays on)
gmake fstab_up                               # Apply /etc/fstab at every start (off until you say so)
gmake fstab_down                             # Leave /etc/fstab alone at start
