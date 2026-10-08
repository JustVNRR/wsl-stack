# ==============================================================================
# THE INSTANCE ITSELF: ITS FILES, ITS STATE, AND ITS SWITCHES
# ==============================================================================
# The machine's, not a project's: the three files the instance keeps outside
# ~/.config - /etc/wsl.conf, written whole by onboarding.sh at the first boot;
# /etc/resolv.conf, which answers the DNS; /etc/fstab, the mounts to apply at
# start - the status that reports what it runs on, and the ten switches.
#
# The three files belong to root: the editors run under sudo, and nano is named
# rather than $EDITOR - the instance's $EDITOR is the Windows `code --wait`,
# which saves as the Windows user and cannot write root's files.
#
# All fourteen run from anywhere: what they touch is the machine's.
GATE_EXEMPT_GOALS += wsl_config dns_resolve wsl_status fstab_config
GATE_EXEMPT_GOALS += systemd_up systemd_down automount_up automount_down interop_up interop_down
GATE_EXEMPT_GOALS += windows_path_up windows_path_down fstab_up fstab_down

# Commands, not files: one of these names landing in the working directory must
# not turn its target into a no-op.
.PHONY: wsl_config dns_resolve wsl_status fstab_config
.PHONY: systemd_up systemd_down automount_up automount_down interop_up interop_down
.PHONY: windows_path_up windows_path_down fstab_up fstab_down

# The closing line the switches print once the change is written: the command
# that applies it, in green inside a yellow sentence. One line on purpose: it
# expands inside a recipe's joined command.
define apply_hint
	printf '$(C_HINT)Run $(C_COMMAND).\\wsl.ps1 restart$(C_HINT) from Windows to apply.$(C_RESET)\n'
endef

wsl_config: ## Open /etc/wsl.conf in nano (sudo): default user, automount, interop
	@sudo nano /etc/wsl.conf
	@printf '\n$(C_HINT)Run $(C_COMMAND).\\wsl.ps1 restart$(C_HINT) from Windows to apply any change.$(C_RESET)\n'

# The resolver file: as long as it is a symlink to WSL's own
# (/mnt/wsl/resolv.conf), WSL writes it again at every start, and an edit goes
# with the next one - the notice says so before nano opens. The lasting way is
# generateResolvConf = false in /etc/wsl.conf, which wsl_config opens.
dns_resolve: ## Open /etc/resolv.conf in nano (sudo)
	@if [ -L /etc/resolv.conf ]; then \
		printf '$(C_HINT)Ensure $(C_COMMAND)generateResolvConf = false$(C_HINT) in /etc/wsl.conf if you want your change to survive a restart.$(C_RESET)\n'; \
	elif [ ! -e /etc/resolv.conf ]; then \
		echo "ℹ️  There is no /etc/resolv.conf — nothing resolves until one exists; WSL will write its own at the next start."; \
	fi
	@sudo nano /etc/resolv.conf

# The mount list, root's too, read at start only when mountFsTab says so -
# false by default, so the closing line names fstab_up rather than invite a
# restart that would mount nothing. `sudo mount -a` applies an edit right now.
fstab_config: ## Open /etc/fstab in nano (sudo) - the mounts to apply at start
	@sudo nano /etc/fstab
	@if grep -q '^[[:space:]]*mountFsTab[[:space:]]*=[[:space:]]*true' /etc/wsl.conf 2>/dev/null; then \
		printf '\n$(C_HINT)Run $(C_COMMAND).\\wsl.ps1 restart$(C_HINT) from Windows to apply.$(C_RESET)\n'; \
	else \
		printf '\n$(C_HINT)Nothing here is mounted at start: set mountFsTab = true first - gmake fstab_up.$(C_RESET)\n'; \
	fi

# The reporter: it reads, it changes nothing, and a state that cannot be read is
# said plainly.
#
# Three lines of the /etc/wsl.conf block end in `# OK` when the machine really
# is in the state the line declares, `# NOK` when it is not (a switch thrown
# without its restart, most of the time). Each answer comes from the machine,
# never from the file - the mount table, a Windows binary really run, /mnt in
# the PATH - and section-aware, because `enabled` lives in two sections.
wsl_status: ## Show what this instance runs on: base image, init, WSL's files, memory
	@$(call title,Base Image and the kernel)
	@printf "Kernel     : "; uname -r
	@printf "Base Image : "; grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
	@$(call title,Service Manager)
	@printf "PID 1      : "; ps -p 1 -o comm= || true
	@printf "systemd    : "; state=$$(systemctl is-system-running 2>/dev/null || true); \
		if [ -n "$$state" ]; then echo "$$state"; else echo "not installed - gmake systemd_up adds it"; fi
	@$(call title,/etc/wsl.conf (local))
	@if [ -f /etc/wsl.conf ]; then \
		am=off; \
		if [ -n "$$(mount | sed -n 's|.* on /mnt/\([a-z]\) .*|\1|p')" ]; then am=on; fi; \
		wp=off; \
		if printf '%s' "$$PATH" | tr ':' '\n' | grep -q '^/mnt/'; then wp=on; fi; \
		ip=off; \
		if [ -x /mnt/c/Windows/System32/cmd.exe ] && /mnt/c/Windows/System32/cmd.exe /c exit 0 >/dev/null 2>&1; then \
			ip=on; \
		elif command -v powershell.exe >/dev/null 2>&1 && powershell.exe -NoProfile -Command 'exit 0' >/dev/null 2>&1; then \
			ip=on; \
		fi; \
		awk -v am="$$am" -v ip="$$ip" -v wp="$$wp" '/^[[:space:]]*\[/ { s = $$0; gsub(/[^A-Za-z]/, "", s); sec = tolower(s); print; next } { t = $$0; if (t !~ /^[[:space:]]*#/ && index(t, "=") > 0) { k = t; sub(/ *=.*/, "", k); gsub(/[^A-Za-z]/, "", k); k = tolower(k); v = t; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]#].*/, "", v); v = tolower(v); obs = ""; if (sec == "automount" && k == "enabled") obs = am; else if (sec == "interop" && k == "enabled") obs = ip; else if (sec == "interop" && k == "appendwindowspath") obs = wp; if (obs != "" && (v == "true" || v == "false")) { want = (v == "true") ? "on" : "off"; sub(/[[:space:]]+$$/, "", t); t = t ((obs == want) ? " # OK" : " # NOK") } } print t }' /etc/wsl.conf; \
	else echo "No such file - WSL starts with its defaults."; fi
	@$(call title,%USERPROFILE%\.wslconfig (windows))
	@if ! powershell.exe -NoProfile -Command 'exit 0' >/dev/null 2>&1; then \
		echo "Windows is not reachable from here - interop is off, or there is no Windows."; \
	else \
		win_home=$$(powershell.exe -NoProfile -Command '$$env:USERPROFILE' 2>/dev/null | tr -d '\r'); \
		drive=$$(printf '%s' "$$win_home" | cut -c1 | tr 'A-Z' 'a-z'); \
		rest=$$(printf '%s' "$$win_home" | cut -c3- | tr '\\' '/'); \
		wslconfig=/mnt/$$drive$$rest/.wslconfig; \
		if [ -z "$$win_home" ]; then \
			echo "Windows did not answer - nothing to read."; \
		elif [ -f "$$wslconfig" ]; then \
			cat "$$wslconfig"; \
		else \
			echo "No $$wslconfig - WSL runs with its own defaults (.\wsl.ps1 wslconfig creates it)."; \
		fi; \
	fi
	@$(call title,Memory and services)
	@printf "Memory     : "; free -h | awk '/^Mem:/ {print $$3 "/" $$2 " in use"}'
	@if systemctl is-system-running >/dev/null 2>&1; then \
		printf "Services   : %s running, %s failed\n" "$$(systemctl list-units --type=service --state=running --no-legend | wc -l)" "$$(systemctl --failed --no-legend | wc -l)"; \
	else \
		printf "Services   : %s up under init.d (systemd is not running)\n" "$$(service --status-all 2>/dev/null | grep -c '\[ + \]')"; \
	fi
	@printf '\n'

# ==============================================================================
# THE TEN SWITCHES - WSL'S OWN FEATURES, TURNED ON AND OFF
# ==============================================================================
# Each pair edits one line of /etc/wsl.conf and nothing else in it, and takes
# effect at the next start.
#
# The edit they share: read the file into $new, with `$(2)` set to `$(3)` inside
# the `[$(1)]` section - replaced where it exists, inserted under its header
# where it does not, the section appended when the file has none.
#
# Section-aware because `enabled` lives in two sections, and two passes because
# one cannot know whether to insert under the header - it would insert AND
# replace, and the file would grow a line per run. The awk programs stay on one
# line: inside single quotes, sh keeps a backslash.
#   $(1) the section   $(2) the key   $(3) the value
define wsl_conf_set
	if [ -f /etc/wsl.conf ]; then \
		has=$$(awk -v sec="$(1)" -v key="$(2)" 'BEGIN { ins = 0 } /^\[/ { ins = ($$0 ~ "^\\[[[:space:]]*" sec "[[:space:]]*\\]") } ins && $$0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { c++ } END { print c + 0 }' /etc/wsl.conf); \
		new=$$(awk -v sec="$(1)" -v key="$(2)" -v val="$(3)" -v has="$$has" '/^\[/ { if ($$0 ~ "^\\[[[:space:]]*" sec "[[:space:]]*\\]") { print; if (!has) { print key "=" val; seen = 1 }; ins = 1; next } ins = 0; print; next } ins && $$0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { print key "=" val; seen = 1; next } { print } END { if (!seen) { print ""; print "[" sec "]"; print key "=" val } }' /etc/wsl.conf); \
	else \
		new=$$(printf '[$(1)]\n$(2)=$(3)'); \
	fi
endef

# systemd, on demand: the image ships none, and nothing the image starts is a
# service. Three packages, named, with --no-install-recommends like every apt
# line: systemd-sysv poses /sbin/init, and libpam-systemd + dbus-user-session
# are what WSL's user session needs. Naming them is also what keeps
# systemd-resolved out, a rival of the resolver the web pack installs.
#
# One sudo, and the file is written only once the packages are there - a
# half-enabled instance is not a state to leave behind. "Already enabled" is
# asked of PID 1, not read from the file.
#
# Two units are masked along the way - kmod-static-nodes (WSL owns /dev),
# systemd-binfmt (no binfmt_misc here): they can never succeed, and left alone
# they make `systemctl is-system-running` answer `degraded`. reset-failed clears
# them from the running boot.
systemd_up: ## Install systemd and turn it on for this instance (a restart boots it)
	@$(call wsl_conf_set,boot,systemd,true); \
	installed=0; \
	if dpkg -s systemd-sysv libpam-systemd dbus-user-session >/dev/null 2>&1; then \
		installed=1; \
	else \
		echo ""; \
		echo "Installing systemd, please wait..."; \
		tmp=$$(mktemp); printf '%s\n' "$$new" > "$$tmp"; \
		sudo sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y --no-install-recommends systemd-sysv libpam-systemd dbus-user-session && cat > /etc/wsl.conf' < "$$tmp"; \
		rc=$$?; rm -f "$$tmp"; \
		[ $$rc -eq 0 ] || { echo ""; echo "❌ The installation failed — /etc/wsl.conf was left untouched."; exit 1; }; \
	fi; \
	if [ "$$(systemctl is-enabled kmod-static-nodes 2>/dev/null)" != "masked" ] || [ "$$(systemctl is-enabled systemd-binfmt 2>/dev/null)" != "masked" ]; then \
		echo ""; \
		echo "Masking the two units WSL cannot use: kmod-static-nodes, systemd-binfmt."; \
		sudo sh -c 'systemctl mask kmod-static-nodes systemd-binfmt >/dev/null; systemctl reset-failed kmod-static-nodes systemd-binfmt 2>/dev/null || true'; \
	fi; \
	if [ "$$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]; then \
		echo "systemd is already enabled."; \
		exit 0; \
	fi; \
	if [ $$installed -eq 1 ]; then \
		printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	fi; \
	echo ""; \
	echo "✅ systemd is enabled."; \
	$(call apply_hint)

systemd_down: ## Stop booting systemd for this instance (the packages stay installed)
	@$(call wsl_conf_set,boot,systemd,false); \
	if ! grep -q '^[[:space:]]*systemd[[:space:]]*=' /etc/wsl.conf 2>/dev/null; then \
		echo "systemd is not declared in /etc/wsl.conf - it is already off."; \
		exit 0; \
	fi; \
	if [ "$$new" = "$$(cat /etc/wsl.conf)" ]; then \
		echo "systemd is already off for this instance."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ systemd is off. The packages stay installed."; \
	$(call apply_hint)

automount_up: ## Mount the Windows drives under /mnt at every start
	@$(call wsl_conf_set,automount,enabled,true); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "automount is already on for this instance."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ automount is on."; \
	$(call apply_hint)

automount_down: ## Stop mounting the Windows drives
	@$(call wsl_conf_set,automount,enabled,false); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "automount is already off for this instance."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ automount is off."; \
	$(call apply_hint)

interop_up: ## Let the instance run Windows programs
	@$(call wsl_conf_set,interop,enabled,true); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "interop is already on for this instance."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ interop is on."; \
	$(call apply_hint)

interop_down: ## Stop running Windows programs from the instance
	@$(call wsl_conf_set,interop,enabled,false); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "interop is already off for this instance."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ interop is off."; \
	$(call apply_hint)

windows_path_up: ## Add the Windows PATH to this instance's PATH
	@$(call wsl_conf_set,interop,appendWindowsPath,true); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "the Windows PATH is already appended here."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ the Windows PATH is appended."; \
	$(call apply_hint)

windows_path_down: ## Keep the Windows PATH out of this instance's PATH (interop stays on)
	@$(call wsl_conf_set,interop,appendWindowsPath,false); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "the Windows PATH is already out here."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ the Windows PATH is out."; \
	$(call apply_hint)

fstab_up: ## Apply /etc/fstab at every start (off until you say so)
	@$(call wsl_conf_set,automount,mountFsTab,true); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "the fstab entries are already applied at start."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ the fstab entries are applied at start."; \
	$(call apply_hint)

fstab_down: ## Leave /etc/fstab alone at start
	@$(call wsl_conf_set,automount,mountFsTab,false); \
	if [ "$$new" = "$$(cat /etc/wsl.conf 2>/dev/null)" ]; then \
		echo "the fstab entries are already left alone at start."; \
		exit 0; \
	fi; \
	printf '%s\n' "$$new" | sudo tee /etc/wsl.conf >/dev/null; \
	echo ""; \
	echo "✅ the fstab entries are left alone at start."; \
	$(call apply_hint)
