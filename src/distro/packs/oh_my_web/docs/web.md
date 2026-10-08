# Web browser and tunnel

[← Back to the README](../../../../../README.md#bundled-software--stack)

| Piece | For | Commands |
| :--- | :--- | :--- |
| Firefox | browsing, from inside the instance | `firefox` |
| the launchers | the session bus the image lacks; light profile with `fox`, strict with `pfox` | `fox`, `pfox` |
| the privacy profiles | switchable by hand too | `fox_tweak_on`, `fox_tweak_off` |
| the tunnel | the traffic, through your own WireGuard server | [the tunnel's page](vpn.md) |

## Installing and removing it

```powershell
.\wsl.ps1 add_pack      # pick the instance, then web
.\wsl.ps1 remove_pack   # the reverse
```

The commands arrive with the pack's folder and show up in the picker
(`Alt + z`). On removal, a package another installed pack still claims stays
in place.

## Firefox

**`fox` and `pfox` open it with a session bus.** The image has no dbus, and
Firefox without one never opens its first window. The first launch of a shell
starts the bus; plain `firefox` works afterwards too.

**The privacy profiles** come in two, and the launcher picks:

- `fox` light,
- `pfox` strict, with the check page first.

`pfox` refuses while Firefox is running.

`fox_tweak_on` / `fox_tweak_off` are the manual switches. What each profile
holds: [the privacy page](fox.md).

Your profile (`~/.mozilla`) is yours: removal does not delete it.

## The tunnel

WireGuard, from the profile your provider gives you, with the kill switch, the
DNS through `openresolv`, and the choice of what starts with the distro:
[the tunnel's page](vpn.md).
