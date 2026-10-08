# The Colours, Written Once

[← Back to the README](../../README.md#makefile-gmake)

A recipe asks for a role, never for a colour. The codes are written in this
module and nowhere else in the make world, so a colour changed here follows
every call site — they name a role, and the role is what changed.

| Name | Colour | What it carries |
| :--- | :--- | :--- |
| `C_TITLE` | cyan | A block title, a target's name in `gmake help`, a pack's name in `packs_list` |
| `C_COMMAND` | green | The command to type, inside a sentence |
| `C_HINT` | yellow | What to watch or do next — a sentence, a value brought forward |
| `C_RESET` | — | Closes every coloured run |

| Macro | What it does | Called by |
| :--- | :--- | :--- |
| `title TITLE` | Prints `TITLE` as a block title: a blank line, `=== TITLE ===` in cyan, a newline. | `wsl_status`'s five sections |

## The one thing to know

The shell side has its twin, [`src/distro/packs/oh_my_shell/config/lib/colours.sh`](../../src/distro/packs/oh_my_shell/config/lib/colours.sh):
make expands text and cannot read a shell file, so the codes are spelled in
both. **A colour changed in one file is changed in the other**, and those two
are the only files allowed to spell a code — the Claude status line, whose
block is shared with Windows, is the third and last; the CI refuses any other.

A value line also takes no comment of its own: make keeps the blanks that
precede a `#` in the value, and one stray space shifts every line of
`gmake help`.
