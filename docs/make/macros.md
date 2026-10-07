# What a Target Says Before It Runs

[← Back to the README](../../README.md#makefile-gmake)

| Macro | What it does | Called by |
| :--- | :--- | :--- |
| `check_vars VARS` | Refuses to run when one of `VARS` is unset. Warns when the values in effect come from neither a project `.env` nor the command line. | `docker_*`, and every GCP target |
| `confirm_action TITLE VARS` | Prints `TITLE` and the value of each variable, then waits for a `y`. | every target that creates or deletes something |

Both are `define`d, never run: they cost nothing until a recipe calls them, so
the module can be loaded before or after the targets that use it.

The third macro, `merge_env_samples`, sits in `make/env.mk` beside the targets
that call it and is the shell's for the same reason: it assembles the `.env`
files, and the `.env.global` it builds is loaded by this Makefile before it
reads a single pack. See [Environment files](env.md).

