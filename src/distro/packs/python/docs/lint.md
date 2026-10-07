# Lint

[← Back to the README](../../../README.md#optional-tooling)

Static checks for Python (`ruff`) and shell (`shellcheck`) — non-destructive
by default, with an auto-fix lane.

## Targets

| Target | Action |
|---|---|
| `lint` | Run all checks (Python + shell), non-destructive |
| `lint-py` | Check Python code with ruff |
| `lint-sh` | Check shell scripts with shellcheck |
| `lint-format` | Auto-fix and format Python code with ruff |

## Variables

| Variable | Default | Notes |
|---|---|---|
| `PY_TARGETS` | `.` | Scan roots for Python (files or directories) |
| `SH_TARGETS` | `.` | Scan roots for shell (files or directories) |

## Auto-fix guard

`lint`, `lint-py` and `lint-sh` only read: they run on the project as it is,
whole project by default, no question asked. `lint-format` is the one target
that **rewrites** files, so it refuses to start when the working tree is not
committed — ruff's edits would otherwise mix with work in progress. A project
that is not a git repository yet — what `fnew` leaves behind — has nothing to
mix with: `lint-format` runs there.

The scan roots stay scopeable on every target:

```bash
gmake lint PY_TARGETS="src/" SH_TARGETS="scripts/"
gmake lint-py PY_TARGETS="src/"
```

## Tools

- `ruff` comes with the `python` pack (`uv tool install ruff`, in its
  `install.sh`); lint rules live in each project's `pyproject.toml`
  (`[tool.ruff]`) — only the tool lives on the machine.
- `shellcheck` is bundled in the template image.
