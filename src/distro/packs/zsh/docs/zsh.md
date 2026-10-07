# The Shell, as a Pack

[← Back to the README](../../../../README.md#bundled-software--stack)

The shell's settings — the `.zshrc`, the modules, `gmake`, the cheatsheets,
the prompt — live in one folder, `src/distro/packs/zsh/config/`, and the pack
is what deploys them: `.\wsl.ps1 add_pack` copies the folder in and runs
`install.sh`, which fills `~/.config/zsh`, writes the `.zshenv` that points
zsh at it, and lays the same files into `/etc/skel` for the accounts that
come after. Chosen while an instance is built, it runs the same way, right
after the image is in place.

The image carries the tools: the zsh package itself, Oh-My-Zsh and its two
plugins, Starship, tealdeer, the modern CLI set. An instance built without
the pack has zsh and none of the settings — a bare shell. The tools are never
fetched twice, and the settings arrive only when asked for.

On a **foreign Debian** — a base this repository never built — the pack
carries the tools too: `PACK_PACKAGES` names them, `install_root.sh` installs
them from the two repositories it registers itself, and the clones and the
two static binaries land under `~/.local`.

## What it carries

What the shell's own pages describe — [`docs/zsh/`](../../../../docs/zsh/) for
plugins, keys, aliases and tools, [`docs/make/`](../../../../docs/make/) for
the gmake modules — arrives with this pack. Its `pack.conf` names it once:

- `PACK_PACKAGES` — the apt list, the image's own: zsh and Oh-My-Zsh's
  runtime dependencies, git, the modern CLI set (fzf, eza, bat, ripgrep,
  fd-find, zoxide, direnv), jq, gh, sqlite3, the archive tools, locales, and
  sudo — every other pack stands on this one, and the installs' passwordless
  door needs it. On the built image every name is already there, and the
  install's apt side is skipped whole.
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

Every step asks before it acts, and nothing that exists is ever replaced: the
configuration copy skips files already in place, the apt side is skipped
whole when every declared package is already installed, and the clones and
the binaries are asked about before they start. Re-running the install on an
instance whose settings are already there writes nothing and fetches nothing.

Leftovers from a shell used before the pack are tidied in the same spirit:
the image's bare `~/.zshrc` is taken back, a `~/.zshrc` of your own is moved
to `~/.zshrc.before-zsh-pack` rather than deleted, and a `~/.zsh_history` is
folded into `~/.local/state/zsh/history`.

The one file that is never touched is `~/.zshenv`: it is where a login
starts, and a file of your own is yours. The install writes it only when it
is missing, and when it exists without a `ZDOTDIR` line it says what to add
rather than add it.

## Removing it

`remove_pack` is the reverse, and the removal is guarded upstream: this pack
leaves only when no installed pack requires it any more, so the packages go
one at a time and any name a standing pack claims is left in place. The
configuration leaves `~/.config/zsh`, **except** the `.env` files the gmake
keeps your variables in — only its Makefile and modules, which are the pack's,
go. The history under `~/.local/state/zsh` and the cache are yours and stay,
and so does a `~/.zshenv` that was not written by the install.
