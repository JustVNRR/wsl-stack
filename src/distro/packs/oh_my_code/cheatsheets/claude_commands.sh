# ==========================================
# CLAUDE CODE CHEATSHEET
# requires: claude
# ==========================================
# The `oh_my_code` pack: Anthropic's agentic CLI, in the instance - a terminal
# program installed under ~/.local (no apt, no root, no Node). Offered only
# while the program is on the PATH: the `# requires:` line above hides the
# sheet once it was removed by hand.

# --- 1. WHAT THIS INSTANCE HAS ---
gmake claude_status                            # Version, versions on disk, the login
claude --version                               # The version alone
claude auth status                             # loggedIn, authMethod, apiProvider (JSON)
claude doctor                                  # The CLI's own check-up

# --- 2. THE PROVIDER ---
gmake claude_profile                           # Choose it from a menu, and apply it
gmake claude_profile CLAUDE_PROFILE=glm        # ... or name it, and skip the menu
gmake claude_edit_profiles                     # The dictionary, in nano ($EDITOR wins when set)
jq -r '.profiles[].id' ~/.config/claude/profiles.json   # What it holds: the ids alone
jq -S . ~/.config/claude/profiles.json                  # ... all of it, without the secrets
jq -S '.env' ~/.claude/settings.json           # What the CLI reads: the applied profile
grep CLAUDE_PROFILE ~/.config/zsh/gmake/.env.global      # The entry in force
jq .statusLine ~/.claude/settings.json         # The status line the pack put there

# --- 3. YOUR PROJECTS ---
gmake claude_project                           # Pick a project, then a session - or a new one
claude --continue                              # ... the same, from the folder you are already in
claude --resume                                # ... or choose among that folder's sessions

# --- 4. WHAT TAKES THE SPACE ---
du -sh ~/.local/share/claude                   # The versions on disk, and their weight
ls -l ~/.local/share/claude/versions/          # ... one file per version
claude project purge --dry-run                 # What one project's history takes

# --- 5. THE FIRST RUN, AND WHEN SOMETHING IS STUCK ---
claude                                         # Open a session here (it asks you to log in once)
claude auth logout                             # Forget the login of this instance
claude update                                  # Update now (it also updates itself at startup)
bash ~/.config/packs/oh_my_code/install.sh         # Put the program back when it was removed by hand
