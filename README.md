# WSL Stack

A reproducible WSL2 stack: one PowerShell command builds a fresh Ubuntu 24.04 distro with:
- the shell,
- optional tooling as packs, added with `.\wsl.ps1 add_pack`:
  - `python`: Python 3, `uv`, ruff and the compilation tools
  - `gcp`: the Google Cloud CLI
  - `vision`: ffmpeg, ImageMagick and Tesseract OCR
  - `web`: Firefox, and a WireGuard tunnel
  - `claude`: Claude Code, the agentic CLI
  - `pandoc`: Pandoc and XeLaTeX, to build a markdown document into a PDF

## Features

- **Minimal setup** — the build asks for your username, then whether sudo should ask for a password (say no and it never does); Ubuntu then asks for your region and city.
- **A modern shell** — Zsh, Oh My Zsh, and Starship, with fzf everywhere and Rust-based replacements for `ls` and `cat` ([shell environment](#shell-environment-zsh)).
- **Command memory** — cheatsheets stored as plain files, injected into the prompt with `Alt + z`.
- **Data Science ready** — the `python` pack brings `uv`, Python 3 and the C build toolchain most wheels are compiled with; `vision` brings the media and OCR tools.
- **Project scaffolding** — `fnew` fuzzy-picks a template from the catalogs the installed packs curate, or takes one by URL, and the pack the row came from finishes the job: a Python project gets its virtual environment and direnv.
- **Modular targets** — `gmake` exposes its targets, and the packs add their own: `devops` (Docker, GitHub PRs), `gcp` (BigQuery, Cloud Run, VMs), `python` (lint, tests), `pandoc` (PDF). They appear as the packs do ([the gmake Makefile](#makefile-gmake), [optional tooling](#optional-tooling)).
- **A browser, and a tunnel** — the `web` pack installs Firefox from Mozilla's own repository and opens it with `fox`, on its light privacy profile, with `pfox` for the strict one in private; its `vpn_*` targets connect the instance to your WireGuard server — the servers live in one JSON, the settings in `.env.global` — and bring it up with the distro.

---

## Prerequisites

- Windows 10/11 with **WSL2** installed and enabled.
- **Docker Desktop** (or Docker Engine running via WSL).
- **PowerShell 7** (`winget install Microsoft.PowerShell`), allowed to run
  local scripts — check it:
  ```powershell
  Get-ExecutionPolicy # Should return RemoteSigned or Unrestricted
  ```
  If it returns `Restricted` or `AllSigned` run:

  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```

---

## Quick Start

Make sure Docker Desktop is running before you start.

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/JustVNRR/wsl-stack.git
   cd wsl-stack
   ```

2. **Build and register the instance:**

   ```powershell
   .\wsl.ps1 build
   ```

   It asks for the instance's name, then confirms where it will live —
   `D:\WSL\<name>` by default. Ctrl+C aborts.

---

## Shell Environment (zsh)

The shell experience is documented per topic under [`docs/zsh/`](docs/zsh/):

| Topic | Doc | Highlights |
| :--- | :--- | :--- |
| Plugins | [Oh My Zsh plugins](docs/zsh/plugins.md) | `git`, `fzf`, autosuggestions, syntax highlighting |
| Keybindings | [ZLE shortcuts](docs/zsh/keybindings.md) | fuzzy-open in VS Code, insert paths, aliases, cheatsheet commands |
| Aliases | [Custom aliases](docs/zsh/aliases.md) | modern `ls` / `cat` / `grep`, `ports`, `reload` |
| Interactive tools | [fzf-powered commands](docs/zsh/interactive.md) | fuzzy navigation, git pickers, `fcheat`, `extract` |

---

## Makefile (`gmake`)

- **Cascading configuration** — what all projects share lives in
  `.env.global`; what identifies one project lives in its own `.env`. Both are
  gitignored and built from committed samples by [`gmake
  env_global_enable` / `gmake env_project_enable`](docs/make/env.md), and the
  commands only ever add what is missing.

- **`gmake` vs `make`:**
  - Type `gmake` (without any arguments) to display a formatted help menu listing every gmake target (GCP compute, BigQuery, Docker, Cloud Run, etc.).
  - Type `gmake` then Tab to complete a target — the same list, each entry followed by its description.
  - Use `fnew (recommended)`, `gmake copier_project`, `gmake cruft_project` or `gmake ccds_project` from `~/projects` to scaffold a project template.
  - Use `gmake <target>` from `~/projects/<your-project-folder>` to run project relative tasks from the `Makefile` in `~/.config/zsh/gmake`.
  - Use `make <target>` from `~/projects/<your-project-folder>` to run project relative tasks from the local `Makefile` in your current project folder.

The gmake Makefile is one module per domain, each documented beside it: the
socle's under `gmake/make/`, with their pages in [`docs/make/`](docs/make/); a
pack carries its modules *and* its pages in its own folder, so it can be lifted
out whole. Indexed along a project's lifecycle:

| Stage | Module | Main targets |
| :--- | :--- | :--- |
| Any | [The colours, written once](docs/make/colours.md) | — (the roles a recipe asks for) |
| Any | [Environment files](docs/make/env.md) | `env_global_enable`, `env_global_manage`, `env_project_enable`, `env_project_manage` |
| Any | [What a target says](docs/make/macros.md) | — (the two macros a module calls) |
| Any | [Packs installed here](docs/make/packs.md) | `packs_list` |
| Any | [The instance's own settings](docs/make/wsl.md) | `wsl_config`, `dns_resolve`, `fstab_config`, `wsl_status`, `systemd_*`, `automount_*`, `interop_*`, `windows_path_*`, `fstab_up`, `fstab_down` |

Everything else a project needs — its image, its pull requests — is a pack's.
The socle stops at what an instance with no project can still do: carry packs,
write the `.env` files, report what it runs on, open `/etc/wsl.conf` and
`/etc/resolv.conf`, and turn WSL's features on and off.

Then the packs — each listed once: a pack leaves with its folder.

| Pack | Start here | Main targets |
| :--- | :--- | :--- |
| `claude` | [Claude Code](packs/claude/docs/claude.md) | `claude_status`, `claude_profile`, `claude_edit_profiles`, `claude_project` |
| `devops` | [The devops pack](packs/devops/docs/devops.md) | `docker_*`, `gh_pr_*` |
| `gcp` | [GCP onboarding guide](packs/gcp/docs/onboarding.md) | `gcp_*`, `gcs_*`, `iam_*`, `bigquery_*`, `cloudrun_*`, `vm_*`, `artifact_registry_*` |
| `pandoc` | [Pandoc & PDF](packs/pandoc/docs/pandoc.md) | `pdf_from_md`, `pdf_open`, `docx_from_md`, `csl_from_catalog`, `font_from_*` |
| `python` | [Python](packs/python/docs/python.md) | `lint*`, `test*` |
| `scaffold` | [Project scaffolding, the pack](packs/scaffold/docs/scaffold.md) | `fnew`, `copier_project`, `cruft_project`, `ccds_project` |
| `vision` | [Vision & OCR](packs/vision/docs/vision.md) | — |
| `web` | [Web browser and tunnel](packs/web/docs/web.md) | `fox`, `pfox`, `fox_tweak_*`, `vpn_*` |

The table holds a pack's extremes: `devops` brings targets and no tool,
`vision` a tool and no target. `devops` and `scaffold` are the two nobody
chooses — `python` and `gcp` require the first, `python` the second.

What a pack is, what it must contain, and how to add one:
[`docs/packs.md`](docs/packs.md). One reaches an instance with
[`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) — or by being chosen while
the instance is built, [`.\wsl.ps1 build`](docs/wsl/commands.md#build) — and
leaves with `remove_pack`.

---

## Bundled Software & Stack

### Core System & CLI Utilities

| Category | Tools |
| :--- | :--- |
| Core | `zsh`, `sudo`, `adduser`, `ca-certificates`, `curl`, `wget`, `openssh-client`, `iputils-ping`, `tzdata`, `nano`, `less`, `tree`, `strace`, `lsof`, `rlwrap`, `tar`, `unzip`, `bzip2`, `unrar`, `p7zip-full`, `gzip`, `xz-utils`, `zstd` |
| Search & navigation | `fzf` (fuzzy search), `fd-find` (linked to `fd`), `zoxide` (directory hopping), `ripgrep` (ultra-fast grep) |
| Inspection & display | `eza` (modern `ls` replacement), `batcat` (syntax highlighting, linked to `bat`), `jq` (JSON processor), `tldr` (command examples, an alternative to man pages) |
| DevOps & cloud | `gh` (GitHub CLI), `direnv`, `shellcheck`, `sqlite3` |

### Optional Tooling

| Category | Tools |
| :--- | :--- |
| Claude Code | [Claude Code](packs/claude/docs/claude.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |
| Google Cloud CLI | [GCP onboarding guide](packs/gcp/docs/onboarding.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |
| Pandoc & PDF | [Pandoc & PDF](packs/pandoc/docs/pandoc.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |
| Python | [Python](packs/python/docs/python.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |
| Vision & OCR | [Vision & OCR](packs/vision/docs/vision.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |
| Firefox & VPN | [Web browser and tunnel](packs/web/docs/web.md), [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) |

### Python & Data Science

None of it is in the image: `uv`, Python 3, ruff and the compiler a wheel needs
(`build-essential`, `python3-dev`, `libffi-dev`, `libssl-dev`) arrive with the
[`python` pack](packs/python/docs/python.md); the scaffolding tools with
[`scaffold`](packs/scaffold/docs/scaffold.md), which `python` requires and which
takes each tool from uv's cache the day it is first used.

---

## Project Structure

Two distinct trees: the **repository** you clone and version, and the **distro**
the build produces. The shell environment is the link between them — `zsh/` is a
source directory that the build copies into the image; nothing reads it from
the repository at runtime.

### The repository

```text
├── zsh/                     # Shell environment, deployed into the distro at build time
│   ├── .zshrc               # Main orchestrator (loads OMZ, modules, prompts)
│   ├── aliases.zsh          # Custom shortcuts and interactive falias picker
│   ├── bindings.zsh         # ZLE widgets and keybindings
│   ├── cheatsheet.zsh       # Interactive cheatsheet selector (fcheat)
│   ├── cheatsheets/         # Auto-scanned data files: CTRL+H command lists (fcheat)
│   │   └── *_commands.sh    # The commands an instance always has: bash, git, the gmake menu
│   ├── completion.zsh       # gmake's targets on Tab, read from the Makefile itself
│   ├── gmake/               # Makefile ecosystem (the gmake command)
│   │   ├── Makefile         # Entrypoint: loads the modules, builds the menu, gates where targets run
│   │   └── make/            # The socle's modules (pages in docs/make/)
│   │       ├── colours.mk   # the colours a recipe asks for, written once
│   │       ├── env.mk       # the .env files, and the commands that build them
│   │       ├── macros.mk    # what a target calls before it runs (check_vars, confirm_action)
│   │       ├── packs.mk     # what this instance carries (gmake packs_list)
│   │       └── wsl.mk       # the instance itself: its files, its state, its switches
│   ├── exports.zsh          # Environment variables and dynamic PATH exports
│   ├── fzf.zsh              # Fuzzy finder engines, layout, and preview templates
│   ├── history.zsh          # History file sizing, persistence, and what is kept out of it
│   ├── lib/                 # The colours, and the messages built on them
│   │   ├── colours.sh       #   the only shell file writing a colour code
│   │   └── message.sh       #   a line says its kind (hint, error...); the colour follows
│   ├── navigation.zsh       # Advanced directory hopping (cdv, cda, fv, fa)
│   ├── prompts/
│   │   ├── starship.toml    # Starship visual configuration
│   │   └── starship.zsh     # Starship initialization hook
│   └── unzip.zsh            # Interactive archive extraction handler
├── assets/
│   └── make-icon.ps1        # Draws an instance's icon from its name (standalone PowerShell)
├── docs/
│   ├── make/                # Documentation of the socle's gmake modules
│   ├── wsl/                 # Instance administration: the commands, their options, examples
│   └── zsh/                 # Shell environment documentation (plugins, keys, aliases, tools)
├── packs/                   # Optional tooling, one folder per pack
│   ├── claude/              # Claude Code, the agentic CLI, under ~/.local
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── profiles.sample  # the providers, in JSON, waiting for your tokens
│   │   ├── env.global.sample   # CLAUDE_PROFILE, for .env.global
│   │   ├── bin/             # the script behind its targets, and the status line
│   │   ├── make/            # its gmake module: claude_status, claude_profile, claude_project
│   │   ├── cheatsheets/     # its fcheat sheet: the CLI, the provider, the projects, the disk
│   │   └── docs/            # the pack's page
│   ├── devops/              # the project targets: Docker, GitHub PRs
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── env.project.sample # the pack's project variables (PACKAGE_NAME, DOCKER_*)
│   │   ├── make/            # the pack's modules, loaded as soon as the folder is there
│   │   ├── cheatsheets/     # its fcheat sheets: the docker commands, its gmake targets
│   │   └── docs/            # the pack's pages, one per module
│   ├── gcp/                 # Google Cloud CLI, BigQuery, Cloud Run, VMs, Artifact Registry
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── install_root.sh  # the root half of the install, run by install.sh
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── remove_root.sh   # the root half of the removal, run by remove.sh
│   │   ├── env.global.sample  # the pack's shared defaults (GCP_REGION, CLOUDRUN_MEMORY…)
│   │   ├── env.project.sample # the pack's project variables (GCP_PROJECT, BUCKET_NAME…)
│   │   ├── make/            # the pack's modules, loaded as soon as the folder is there
│   │   ├── cheatsheets/     # the pack's fcheat sheets, each with its `# requires:` header
│   │   └── docs/            # the pack's pages, onboarding walkthrough included
│   ├── pandoc/              # Pandoc and XeLaTeX: Markdown to PDF, bibliography included
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── install_root.sh  # the root half of the install, run by install.sh
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── env.project.sample # the pack's project variables (PDF_SRC, DOCX_REFERENCE...)
│   │   ├── bin/             # the scripts behind the targets: the build, the viewer, the styles, the fonts
│   │   ├── make/            # its gmake module: the document targets, the styles, the fonts
│   │   ├── cheatsheets/     # its fcheat sheet: the targets, the commands, the PDF tools
│   │   └── docs/            # the pack's page
│   ├── python/              # Python 3, uv, ruff, the compiler a wheel is built with
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── install_root.sh  # the root half of the install, run by install.sh
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── make/            # its modules: lint, the test lanes, the venv
│   │   ├── cheatsheets/     # its fcheat sheets, and the catalog fnew reads
│   │   ├── zsh/             # its shell files: uv's PATH and completions
│   │   └── docs/            # the pack's pages, one per module
│   ├── scaffold/            # making a project: fnew, the picker, the three targets
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── env.global.sample  # the direct-call variables (PROJECT_TEMPLATE_*, TEMPLATE_PACK)
│   │   ├── make/            # the scaffolding targets, and the after-copy step
│   │   ├── cheatsheets/     # its fcheat sheets: the scaffolding commands
│   │   ├── zsh/             # its shell files: uv's PATH, the fnew picker
│   │   └── docs/            # the pack's pages, one per module
│   ├── vision/              # ffmpeg, ImageMagick, Tesseract: media and OCR tools
│   │   ├── pack.conf        # what it installs, and the line `add_pack` shows
│   │   ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│   │   ├── install_root.sh  # the root half of the install, run by install.sh
│   │   ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│   │   ├── cheatsheets/     # their commands, in the fcheat picker
│   │   └── docs/            # the pack's page
│   └── web/                 # Firefox (Mozilla's repository) and the WireGuard tunnel
│       ├── pack.conf        # what it installs, and the line `add_pack` shows
│       ├── install.sh       # what `wsl.ps1 add_pack` runs inside the instance
│       ├── install_root.sh  # the root half of the install, run by install.sh
│       ├── remove.sh        # what `wsl.ps1 remove_pack` runs before the folder goes
│       ├── fox-privacy-*.js # the two privacy profiles (light, strict) the launchers choose
│       ├── privacy-check.html  # the live check page pfox opens
│       ├── vpn.servers.sample  # the servers, in JSON, waiting for your keys
│       ├── env.global.sample   # VPN_PROFILE and VPN_KILL_SWITCH, for .env.global
│       ├── bin/             # the two scripts: the tunnel's, the browser's - and the boot hook's
│       ├── make/            # its gmake modules: the vpn_* and the fox_tweak_* targets
│       ├── zsh/             # its shell files: the `fox` and `pfox` functions
│       ├── cheatsheets/     # its fcheat sheets: the browser and the tunnel
│       └── docs/            # the pack's pages, one per module
├── scripts/                 # Instance administration, one file per command
│   ├── instance.ps1         # What they share: the marker, the look, Docker Desktop
│   ├── message.ps1          #   and the colour a message takes, read from the
│                            #   colour scheme of the window it is printed in
│   ├── prompts.ps1          # The questions a command asks: the instance's full
│                            #   name, its packs checklist, the user it opens as
│   ├── theme.ps1            # What `theme` opens, and the menu it asks with
│   ├── icon.ps1             #   the icon alone: its letters, its colours, an image
│   ├── font.ps1             #   the font alone
│   ├── color.ps1            #   the colours alone
│   └── *.ps1                # list, build, start, stop, shell, add_pack,
│                            # remove_pack, manage_packs, theme, unregister,
│                            # archive, restore, duplicate, shrink
├── tests/                   # The suites that RUN the code: the arrow menu with a
│                            # scripted keyboard, the pack checklist, build's
│                            # questions over a stand-in docker, the icon a name
│                            # draws, the icon, font and colour commands, the
│                            # colour a message takes, the name a Windows
│                            # account proposes, starting and restarting
│                            # over a stand-in wsl, archiving and coming back
│                            # from an archive, removing an instance, doc drift
│   ├── fake-docker/         # That stand-in: answers the preflight, fails the import
│   └── fake-wsl/            # And the suites that drive wsl: logs every call, writes
│                            # what an export would, creates what an import would
├── .github/
│   └── workflows/
│       ├── ci.yml           # Static checks, then the code suites on Windows
│       └── image.yml        # Rootfs image build (push/PR + weekly, catches upstream drift)
├── Dockerfile               # Rootfs build recipe: Ubuntu 24.04 and the socle's tools
├── first_boot.sh            # User creation, sudo, timezone, /etc/wsl.conf
├── wsl.ps1                  # The way in: one command at the root, the scripts in scripts\
├── .dockerignore            # Keeps the context lean, keeps .env.global out of the image
├── .gitattributes           # Enforces strict LF line endings for shell scripts
├── .gitignore               # Prevents committing build artifacts (*.tar, *.vhdx)
├── LICENSE                  # MIT
└── README.md
```

### Inside the distro

Written by the build or by `gmake` targets. None of it is versioned, and
deleting the distro deletes all of it.

```text
~/.config/zsh/               # = zsh/ from the repository
├── gmake/
│   ├── .env.global          # Shared defaults (gmake env_global_enable)
│   ├── env.global.sample    # The header every .env.global opens on
│   ├── env.project.sample   # The header a project's .env opens on
│   ├── Makefile
│   └── make/*.mk            # the socle's modules
└── .zshrc, modules, lib/, prompts/, cheatsheets/

~/.config/packs/             # A pack lands here, its files and its tool together:
└── gcp/                     # added by `.\wsl.ps1 add_pack`, removed by remove_pack.
                             # ~/.zshrc reads its zsh/ here, gmake its make/ - nothing is copied

~/projects/<project>/        # One directory per project
├── .env.sample              # The template's list of variables (copied once to .env)
├── .env                     # This project's identity (filled in by you; env_project_enable tops it up)
├── .envrc                   # direnv hook (the template's, or written by the scaffolding)
└── .venv/

~/.local/share/oh-my-zsh/    # Cloned at build time
~/.local/bin/                # the packs that install outside apt: uv and its
                             # tools (python), the claude launcher (claude)
~/.local/share/uv/           # the Python builds it downloaded, and their environments
~/.config/gcloud/            # The two GCP logins (gcp_auth_cli, gcp_auth_libs)
/etc/wsl.conf                # Default user, automount, interop (first_boot.sh; reopened by gmake wsl_config)
/etc/resolv.conf             # Name servers (WSL's, or yours; reopened by gmake dns_resolve)
/etc/fstab                   # Mounts to apply at start (reopened by gmake fstab_config)
```

---

## Continuous Integration

Two GitHub Actions workflows, in `.github/workflows/`:

| Workflow | Runs on | What it proves |
| :--- | :--- | :--- |
| `ci.yml` — Checks | every push, PRs onto `main` | shellcheck, `zsh -n`, the colour codes confined to their files, the makefile parses with a complete help menu, docs and cheatsheets in sync with the `gmake` modules — then twelve suites on Windows drive the real code under PowerShell 7 |
| `image.yml` — Rootfs image build | every push, PRs onto `main`, weekly, manual | the Dockerfile still resolves end to end: apt repositories, download URLs, git clones |

They check the **repository** — the files, and the code run against stand-ins,
never a running distro — so none replaces a real `.\wsl.ps1 build` run. The
weekly `image.yml` run is the one that catches **upstream drift** — a package
that moved, a URL that changed — while the repository sits untouched. Each
workflow is documented in full at the top of its own file.

---

## Instance Administration (wsl.ps1)

Instances are listed, built, started, stopped, restarted, opened, copied,
archived, restored, compacted and removed from `wsl.ps1`, at the root of the
repository.
The scripts themselves live in `scripts\` — `wsl.ps1` is the only thing to type.

| Command | What it does |
| :--- | :--- |
| [`.\wsl.ps1 list`](docs/wsl/commands.md#list) | list our instances and the archives |
| [`.\wsl.ps1 build`](docs/wsl/commands.md#build) | build an instance from the image |
| [`.\wsl.ps1 start`](docs/wsl/commands.md#start) | start a stopped instance |
| [`.\wsl.ps1 stop`](docs/wsl/commands.md#stop) | stop a running instance |
| [`.\wsl.ps1 restart`](docs/wsl/commands.md#restart) | restart an instance |
| [`.\wsl.ps1 shell`](docs/wsl/commands.md#shell) | open a shell inside an instance |
| [`.\wsl.ps1 add_pack`](docs/wsl/commands.md#add_pack) | install a pack into an instance |
| [`.\wsl.ps1 remove_pack`](docs/wsl/commands.md#remove_pack) | uninstall a pack from an instance |
| [`.\wsl.ps1 manage_packs`](docs/wsl/commands.md#manage_packs) | choose the packs an instance should carry |
| [`.\wsl.ps1 theme`](docs/wsl/commands.md#theme) | choose the icon, font and colours |
| [`.\wsl.ps1 unregister`](docs/wsl/commands.md#unregister) | remove an instance |
| [`.\wsl.ps1 archive`](docs/wsl/commands.md#archive) | write an instance to a named archive |
| [`.\wsl.ps1 restore`](docs/wsl/commands.md#restore) | rebuild an instance from an archive |
| [`.\wsl.ps1 duplicate`](docs/wsl/commands.md#duplicate) | copy an instance under another name |
| [`.\wsl.ps1 shrink`](docs/wsl/commands.md#shrink) | reclaim the space an instance has freed |
| [`.\wsl.ps1 wslconfig`](docs/wsl/commands.md#wslconfig) | open the Windows-wide WSL settings |

Each command, with its options, its examples and what it prints, is documented
in [**Instance commands**](docs/wsl/commands.md).

---

## License

MIT — see [LICENSE](LICENSE).
