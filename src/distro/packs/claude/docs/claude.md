# Claude Code

[← Back to the README](../../../README.md#optional-tooling)

| Piece | For | Commands |
| :--- | :--- | :--- |
| the program | a session, in a project or anywhere | `claude` |
| your projects | pick up work where it stopped | `gmake claude_project` |
| what this instance has | version, versions on disk, the login | `gmake claude_status` |

## Installing and removing it

```powershell
.\wsl.ps1 add_pack      # pick the instance, then claude
.\wsl.ps1 remove_pack   # the reverse
```

## Getting in

Claude Code needs a credential to talk to a model. There are two
kinds.

| Route | What it is | What you do |
| :--- | :--- | :--- |
| a key | an API key | keep it in the dictionary, and apply it — [which provider](#which-provider) |
| a login | a subscription | let `claude` open the authorisation page once |

## Which provider

A key needs somewhere to live, and several providers is several keys. The pack
keeps them in one file of yours:

| | |
| :--- | :--- |
| `~/.config/claude/profiles.json` | one entry per provider — an id, then the environment that provider needs |
| `gmake claude_edit_profiles` | opens it in the editor (nano, or `$EDITOR`) |
| `gmake claude_profile` | picks one from a menu, and applies it |
| `gmake claude_profile CLAUDE_PROFILE=glm` | applies that one, without the menu |
| `CLAUDE_PROFILE` in `.env.global` | the entry in use |

An entry is the environment Claude Code reads — the same names as in
`settings.json`, so a block you already have goes in as it stands:

```json
{ "id": "...",
  "ANTHROPIC_BASE_URL": "...",
  "ANTHROPIC_AUTH_TOKEN": "…",
  "ANTHROPIC_MODEL": "..." }
```

`id` and `note` belong to the file; every other key is the provider's.

**Where it lands**: the `env` block of `~/.claude/settings.json`.

**What the pack owns there**: every key any of your entries names, plus
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY` and
`ANTHROPIC_MODEL`.

## The status line

Installing the pack gives the instance a status line for its sessions, on two
rows:

```text
 Opus 5.5 |  max |  ctx 86k/200k (43%)
 glm |  py: .venv |  main |  #12 pending |  ~/projects/demo
```

## Where things live

| Path | What it is |
| :--- | :--- |
| `~/.local/bin/claude` | the launcher — a symlink into the versions below |
| `~/.local/share/claude/versions/` | every version installed, one file each |
| `~/.claude/` | settings, credentials, prompt history, sessions |
| `~/.claude/projects/` | one folder per project this instance has worked in — what `claude_project` lists |
| `~/.claude/settings.json` | the settings the CLI reads at every start |

`~/.local/bin` is already on the PATH — the shell exports it — and the installer
runs with it there, so its leave-me-in-your-PATH note never appears.

