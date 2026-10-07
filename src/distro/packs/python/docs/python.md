# Python

[← Back to the README](../../../README.md#optional-tooling)

## What it brings

| Piece | For | Commands |
| :--- | :--- | :--- |
| [uv](https://docs.astral.sh/uv/) | installing Python, and a project's dependencies | `uv`, `uvx` |
| Python 3 | the interpreter the projects run on, downloaded by uv | through `uv run` |
| Compiler and headers | building the wheels that ship no compiled version | `gcc`, `g++` |
| [ruff](https://docs.astral.sh/ruff/) | formatting and linting Python code | `ruff` |

## What it adds to the shell and to gmake

| Page | What it drives |
| :--- | :--- |
| [The virtual environment](venv.md) | `init_venv`, the step that runs after one of this pack's template rows |
| [Lint](lint.md) | `lint`, `lint-py` (ruff), `lint-sh` (shellcheck), `lint-format` |
| [Tests](tests.md) | `test`, `test-fast`, `test-functional`, `test-gcp` |

## Installing and removing it

```powershell
.\wsl.ps1 add_pack      # pick the instance, then python
.\wsl.ps1 remove_pack   # the reverse
```


