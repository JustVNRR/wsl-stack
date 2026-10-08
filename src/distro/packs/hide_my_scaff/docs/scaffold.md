# Project Scaffolding, the Pack

[← Back to the README](../../../../../README.md#bundled-software--stack)

Making a project: the `fnew` picker, the three gmake targets it delegates to,
the `.env` every project wants, and the one line a pack declares so that its own
step follows the copy. It used to live in the oh_my_py pack, where most of it was
not python.

## What it brings

| Piece | For | Commands |
| :--- | :--- | :--- |
| [uv](https://docs.astral.sh/uv/) | taking the template tools, on demand | `uv`, `uvx` |
| `fnew` | picking a template from the catalogs, then scaffolding it | `fnew` |
| The three targets | the same act, without the picker | `copier_project`, `cruft_project`, `ccds_project` |
