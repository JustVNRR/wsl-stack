# Packs Installed Here

[← Back to the README](../../README.md#makefile-gmake)

## Target

| Target | Action | Confirmation |
|---|---|---|
| `packs_list` | List the packs installed in this instance | — |

## What it reads

A pack is installed when its folder is in `~/.config/packs`, carrying its own
`pack.conf` — the Windows side asks the same question of the same file, so both
answer alike. Nothing else is consulted: no list to keep up to date, no binary
to test. The command reads those folders and prints one line per pack — its
name, and the description from its own `pack.conf`:

```text
Packs currently installed:

  hide_my_ops  The Google Cloud CLI
  oh_my_py     Python 3, uv, ruff and the compilation tools
  oh_my_peg    ffmpeg, ImageMagick and Tesseract OCR

Packs are managed from Windows (.\wsl.ps1)
```

A pack marked `PACK_VISIBLE := no` in its `pack.conf` has no line here either.
It is a shared dependency — `hide_my_ops`, the project targets `oh_my_py` and `oh_my_cloud` both
need — and a shared engine is not a car: it does not belong in the list of what you
asked for. It arrived with the pack that requires it, and leaves with the last
one that does.
