# The Template Pack

[← Back to the README](../../../../../README.md)

A pack that does nothing: its four scripts only say they ran. It is the
skeleton a new pack is copied from — duplicate it from the settings window
(the Catalogue section, the copy button), rename it, and fill it in. Its own
name says where it belongs: `_oh_my_pack` heads every list, out of the working
packs' way.

## The files

| File | What it is for |
|---|---|
| `pack.conf` | What the catalogue reads — description, family, requires; the other keys documented, commented |
| `install_root.sh` | What needs root, run as WSL's root before `install.sh` |
| `install.sh` | The install, run as the instance's own user |
| `remove.sh` | What leaves with the pack — where an install's traces are erased |
| `remove_root.sh` | What needs root to leave, called by `remove.sh` as one sudo |
| `make/template.mk` | Where the gmake targets go — loaded as soon as the folder is in `~/.config/packs` |
| `zsh/template.zsh` | Where the shell files go — read where they live, never copied |
| `env.global.sample` | Its share of the shared defaults, merged when the key is not already set |

An install of it says:

```text
run install root template
run install template
```

and its removal says the same with `remove` — which is everything it does.
