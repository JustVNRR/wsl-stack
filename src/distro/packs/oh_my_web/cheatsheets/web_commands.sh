# ==========================================
# WEB BROWSER CHEATSHEET
# requires: firefox
# ==========================================
# Firefox, which the `oh_my_web` pack installs, and the one function it adds.
# Offered only while the browser is installed: the `# requires:` line above
# hides the sheet once it was removed by hand.

# --- 1. OPEN ---
fox                                            # Open Firefox (the pack's function, light privacy profile)
firefox                                        # ... the command itself
fox https://example.com                        # Open a page
fox --private-window                           # A private window
pfox                                           # A private window, on the strict profile - with the live check page first
fox --new-window                               # A new window, even if one is open
fox https://example.com/report.pdf             # A URL with a query string, quoted if it has &

# --- 2. WHEN SOMETHING IS WRONG ---
fox --safe-mode                                # Start without extensions or hardware acceleration
fox --version                                  # Which version is installed
MOZ_ENABLE_WAYLAND=1 fox                       # Wayland for one call (the pack runs X11: it is what behaves under WSLg)
ls ~/.mozilla/firefox                          # The profiles: bookmarks, passwords, history

# --- 3. THE SOUND (the volume needs: sudo apt install pulseaudio-utils) ---
pactl get-sink-volume @DEFAULT_SINK@           # The level the instance plays at (its own, not Windows')
pactl set-sink-volume @DEFAULT_SINK@ 50%       # Set it - +10% / -10% moves by a step
pactl set-sink-mute @DEFAULT_SINK@ toggle      # Cut the sound, and bring it back
pactl list sinks short                         # What WSLg offers as an output (one: its own)

# --- 4. PRIVACY (the launcher picks the profile: fox = light, pfox = strict) ---
gmake fox_tweak_on                             # The strict profile, put in place by hand
gmake fox_tweak_off                            # Everything out - the browser stock again
fox about:config                               # Where one value can be watched or relaxed

# --- 5. FILES ON THIS MACHINE ---
fox "$(wslpath 'C:\Users')"                    # Open a Windows folder through /mnt/c
xdg-open report.pdf                            # Open any file with the default application
