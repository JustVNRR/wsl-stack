# The Virtual Environment

[← Back to the README](../../../README.md#optional-tooling)

## Who calls it

```make
SCAFFOLD_AFTER_python := init_venv      # packs/python/make/venv.mk
```

`fnew` reads that declaration off the row it picked: a row from this pack's
catalog runs `init_venv`, a row from another pack's runs that pack's step, and
nothing else runs at all.

## The three cases

`init_venv` looks at what the template wrote, and exactly one branch installs
dependencies:

| What the project has | What runs |
| :--- | :--- |
| `uv.lock`, or a `pyproject.toml` with a PEP 621 `[project]` table | `uv sync` — creates `.venv`, installs the dependencies and the `dev` group |
| `requirements.txt` | `uv venv`, then `uv pip install` (and `requirements_dev.txt` when present) |
| none of the above | a bare `uv venv`, with a warning — the dependencies are yours to install |

## direnv, and the project's activation

The macro ends by making the project usable on the way in:

- **`.envrc`** — written only where the project has none, so the one a template
  ships is left alone. The line it writes sources `.venv/bin/activate` behind a
  guard that keeps it quiet before the first `uv sync`.
- **`direnv allow`** — approves whichever `.envrc` is there, so the environment
  activates on `cd` into the project.

## Skipping the picker

```bash
cd ~/projects
gmake copier_project PROJECT_NAME=my-analysis PROJECT_TEMPLATE_REPO=gh:owner/python-copier-template-ds
```

`TEMPLATE_PACK` decides whose step runs after the copy — `python` unless you say
otherwise. `TEMPLATE_PACK=` copies the template, writes the `.env`, and stops
there: no environment, no direnv.
