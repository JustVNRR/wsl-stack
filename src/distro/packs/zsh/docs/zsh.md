# The Shell Socle, as a Pack

[← Back to the README](../../../../README.md#bundled-software--stack)

The shell socle — zsh, Oh-My-Zsh, Starship and the daily CLI tools — is a pack
like any other: one folder, `src/distro/packs/zsh/`, with its own `pack.conf`,
install, removal, and the `config/` folder holding the configuration itself.
Two roads deploy it, and they read the same files:

- the **built image**: the Dockerfile's one `COPY` line bakes `config/` into
  `/etc/skel`, and the rest of the socle (packages, repositories, clones,
  binaries) is baked earlier in the same Dockerfile — every instance starts
  with the shell in place;
- a **foreign Debian**: `.\wsl.ps1 add_pack` copies the folder in and runs
  `install.sh`, which lays down the same packages, repositories, clones,
  binaries, configuration and skeleton.

## What it carries

What the shell's own pages describe — [`docs/zsh/`](../../../../docs/zsh/) for
plugins, keys, aliases and tools, [`docs/make/`](../../../../docs/make/) for
the gmake modules — arrives with this pack. Its `pack.conf` names it once:

- `PACK_PACKAGES` — the apt list the image installs: zsh and Oh-My-Zsh's
  runtime dependencies, git, the modern CLI set (fzf, eza, bat, ripgrep,
  fd-find, zoxide, direnv), jq, gh, sqlite3, the archive tools, locales, and
  sudo — every other pack stands on this one, and the installs' passwordless
  door needs it.
- `PACK_OUTSIDE_APT` — `starship` and `tldr`, the two static binaries apt
  never sees: fetched into `~/.local/bin` when the machine does not already
  carry them.
- The `config/` folder — what lands in `~/.config/zsh`: the `.zshrc`, the
  modules, `gmake/`, `lib/`, `prompts/`, `cheatsheets/`.
- The three clones — Oh-My-Zsh and its two plugins, into
  `~/.local/share/oh-my-zsh`, each asked about before it starts so a run that
  stopped half way picks up where it stopped.
- The skeleton — `/etc/skel/.zshenv` and `/etc/skel/.config/zsh`, made by the
  root half, for the accounts that come after this one.

## Installing it on a running instance

Every step asks before it acts. On the built image everything is already in
place, so the whole install is a quiet no-op except for the configuration
copy — which is the point: `add_pack` again after a `git pull` is how an
instance picks up a socle change, since `~/.config/zsh` is a copy and the
repository is the truth. An instance built by an older image and never touched
is brought up to the current socle the same way.

The one file that is never touched is `~/.zshenv`: it is where a login starts,
and a file of your own is yours. The install writes it only when it is
missing, and when it exists without a `ZDOTDIR` line it says what to add
rather than add it.

## Removing it

`remove_pack` is the reverse, and the removal is guarded upstream: this pack
leaves only when no installed pack requires it any more, so the packages go
one at a time and any name a standing pack claims is left in place. The
configuration leaves `~/.config/zsh`, **except** the `.env` files the gmake
keeps your variables in — only its Makefile and modules, which are the pack's,
go. The history under `~/.local/state/zsh` and the cache are yours and stay,
and so does a `~/.zshenv` that was not written by the install.
