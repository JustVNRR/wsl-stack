# What a Pack Is

[← Back to the README](../README.md#makefile-gmake)

A pack is optional tooling — a CLI the image does not ship, the gmake targets
that drive it, the shell commands, the variables it reads — and the two scripts
that install and remove it, all of it living in one folder under `src/distro/packs/`. The
socle knows nothing about any particular pack: it finds the folders and loads
what they carry. Adding a pack touches no file outside that folder.

A pack needs no tool: what it brings is what its folder carries, and that may be
targets, a tool, or both — `devops` is targets only, `vision` a tool only.

## The folder

```text
src/distro/packs/<name>/
├── pack.conf              # what the socle and the installer read
├── install.sh             # what `.\wsl.ps1 add_pack` runs inside the instance
├── install_root.sh        # what needs root, run by install.sh as one sudo
├── remove.sh              # what `.\wsl.ps1 remove_pack` runs before the folder goes
├── remove_root.sh         # what needs root, run by remove.sh as one sudo
├── make/*.mk              # its targets, loaded as soon as the folder is there
├── zsh/*.zsh              # its shell files, read where they live (never copied)
├── env.global.sample      # its share of the shared defaults
├── env.project.sample     # its share of a project's variables
├── cheatsheets/*.sh       # its fcheat sheets, each with a `# requires:` header
└── docs/*.md              # its pages: one per module, and whatever else it needs
```

| Code | What it says | What happens |
| :--- | :--- | :--- |
| `0` | what the pack carries is installed | its folder stays, and the pack is installed |
| `1` | the installation failed | its folder goes back out, and so do the folders of the packs that had not run yet — the folder is what the menu reads, and one left behind is a menu that lies |
| `2` | **the user was asked something and said no** | the same, but nothing failed: the run goes on, and no caller reports anything |

## `pack.conf`

| Declaration | What it says |
| :--- | :--- |
| `PACK_DESCRIPTION` | the line `add_pack` shows in its list of packs |
| `PACK_REQUIRES` | the packs it is installed on top of |
| `PACK_VISIBLE` | `no` keeps it out of every list: nobody chooses it |
| `PACK_PACKAGES` | the system packages it installs — named once, read by both scripts, and by a neighbour's removal |
| `PACK_OUTSIDE_APT` | the tools it installs outside apt (a binary in `~/.local`) — named for the same reason, and read the same way |
| `PACK_IDENTIFYING_VARS` | the variables refused in a shared `.env.global` |
| `PACK_WELCOME` | the line `build` prints on a fresh instance, when this pack is among the chosen ones |

Only the first is always there. `PACK_IDENTIFYING_VARS` is read with `sed`, not
by including the file: the socle needs it while it is still loading
`.env.global`, before a pack may define anything. `PACK_DESCRIPTION` is read by
`add_pack`, from Windows.

## Installed, or not

The folder **is** the state. The socle loads `packs/*/make/*.mk` and asks
nothing else: a pack is installed exactly when its folder is in
`~/.config/packs`, which is where `.\wsl.ps1 add_pack` puts it — the files and
the tool together. Nothing is recorded anywhere, so nothing can disagree with
what is on the machine.

`gmake help` follows the same rule: it is built by reading the **text** of the
files make loaded, so a pack whose folder is gone contributes no line at all.

A pack's targets are ordinary ones, with one thing they can declare: a target
that only makes sense from `~/projects` (scaffolding) says so in its module —
`SCAFFOLD_GOALS += copier_project cruft_project ccds_project`, in
`src/distro/packs/scaffold/make/project-setup.mk` — and the location gate in the Makefile
reads that declaration. The gate is checked after the modules are loaded,
precisely so it can: `$(error)` fires when make *reads* the line.

A pack also curates its own template catalog (`cheatsheets/templates.tsv`), and
the `scaffold` pack's `fnew` reads every installed pack's, showing each row with
the pack it was read from. What runs once such a row's template has been copied
is that pack's to declare — `SCAFFOLD_AFTER_python := init_venv`, in its own
module, beside the macro it names — and `fnew` names the row's pack on the make
command line. A pack that declares nothing names nothing: its projects are
copied and left alone.

Removing is the same story from the other end: `.\wsl.ps1 remove_pack` runs the
pack's own `remove.sh` first, then deletes the folder, then takes back the
dependencies that came in with the pack and that no `remove.sh` ever named —
the bulk of the weight. What the install wrote in your files — a login, a `.env`
you filled in — stays, because it is yours and not the pack's. The rule that
decides what may go is in [Instance commands](wsl/commands.md#remove_pack).

Several packs at once go through `.\wsl.ps1 manage_packs`, which is a checklist
of every pack this repository carries: the ones the instance has arrive checked,
and one Enter installs what is missing and takes out what is not. It copies the
newcomers' folders before removing anything, so a package two packs share is
left where it is — [the order, and why](wsl/commands.md#manage_packs).

A new instance can start with its packs already in place: `.\wsl.ps1 build`
asks the same checklist before it builds, and installs the answer once the
instance exists.

They are all documented in
[Instance commands](wsl/commands.md#add_pack).

## The shell

A pack may bring shell files (`zsh/*.zsh`), and the socle reads them **where
they live** — `~/.config/packs/*/zsh/*.zsh`, from the `.zshrc` that loads
everything else. Nothing is copied into `~/.config/zsh`: a pack that leaves
takes its commands out of the shell exactly as it takes its targets out of the
menu, and an instance carrying no pack reads nothing there at all. The
`scaffold` pack's `fnew` and the catalogs it reads travel together that way — the
picker resolves them from its own file's location, not from a path that only
exists in the socle.

## Two packs, one choice

`PACK_REQUIRES` names a pack it is installed on top of — one name, or several.
What it requires arrives **before** it, a pack lands on what it needs, and it
leaves **after** it, when the last pack that required it goes.

The second half is what makes an invisible pack possible. `PACK_VISIBLE := no`
is a pack in no list: not in `add_pack`'s, not in `manage_packs`' checklist, not
in `gmake packs_list`. You cannot choose it, and you cannot remove it by hand —
either one would pull the base out from under a pack still installed. It arrives
with the pack that requires it, it leaves with the last one that does, and it is
never alone.

The rule runs the other way too, and that half is the guard: a pack still
installed cannot lose one it requires. Unchecking it in the checklist is
refused — the claimant is named, and nothing of the answer is applied — and
`remove_pack` refuses the choice the same way. The demanding pack goes out in
the same pass, or both stay. And the cascade never takes a *visible* pack
along: a visible one leaves only because somebody unticked it — it is the
invisible ones that follow their last claimant.

`devops` and `scaffold` are the two: the project targets `python` and `gcp`
both need, and the act of creating a project.

They are required for what they bring, not for a macro: `devops` ships the
sample that carries `PACKAGE_NAME` and `DOCKER_BASE_IMAGE`; `scaffold` is what
runs once a template has been copied (`SCAFFOLD_AFTER_python`). What a target
*calls* — `check_vars`, `confirm_action` — is the socle's, loaded with every
module.

## Two packs, one package

Two packs may install the same package — a compiler, a media library — and they
will, the day a use case arrives that needs what another one already wanted.
The second install is a non-event: apt answers *already the newest version*, uv
answers *already installed*. What must not happen is the second pack breaking
when the first one leaves.

So a pack **does not own** what it installs: it is one of the claimants. Before
removing a package, its `remove.sh` looks for that name in the declarations of
the packs still installed — `pack.conf`, and `install.sh` as well for a pack
written before `PACK_PACKAGES` existed. A claimed package is left where it is,
and the last pack to want it takes it away with it.

What apt never sees goes through the same question. A tool a pack installs
itself — a binary under `~/.local`, outside dpkg's graph — is declared in
`PACK_OUTSIDE_APT`, and its `remove.sh` asks before erasing a single file. `uv`
is the case: `python` uses it for a project's environment, `scaffold` for every
tool it runs, so the first to leave leaves it and the last takes it away.

Two things a `remove.sh` never does:

- **`autoremove` from inside a `remove.sh`.** apt removes the package it is
  given and leaves its dependencies alone — taking `tesseract-ocr` away leaves
  `libtesseract5` behind. Those are taken back by `remove_pack`, not by the
  pack: "does anything still need this?" is a question about the whole
  instance, and a pack cannot see the instance it lands in.
- **Remove a library.** apt takes the programs that depend on it along when a
  library goes — and says so before doing it. A pack names programs.

A library a program loads **at runtime** is a third case, and the one the two
rules above do not cover: apt cannot see the need (the program asks for it by
name when it starts, so nothing declares it), which is exactly why a pack cannot
name it either — removing it would take a neighbour's program along. The pack
installs it beside the program that wants it, and never in `PACK_PACKAGES`;
its `remove.sh` marks it automatic on the way out
(`apt-mark auto`), which makes it an orphan the moment the pack is gone, and the
cleanup `remove_pack` runs afterwards takes it back. `web` is the case that
exists: Firefox loads `libavcodec60` for H.264 and `libpulse0` for the sound,
and nothing declares either.

No pack has to be cut to avoid an overlap: a pack that needs a package installs
it, neighbour or not.

## The cheatsheets

A sheet declares what it needs in its header, and the picker asks again every
time it opens:

```
# requires: <binary>      shown only when that binary is on the PATH
# requires: !<binary>     shown only when it is not
```

A tool removed by hand (`sudo apt remove google-cloud-cli`) leaves a folder
behind and a sheet whose commands would not run: the header hides it.

## The variables

A pack ships samples, never the real files. `gmake env_global_enable` and
`gmake env_project_enable` read the socle's samples and every installed pack's,
and append only what the file does not already define — so a value you filled
in survives, and a pack installed later is covered by the next run. See
[Environment files](make/env.md).
