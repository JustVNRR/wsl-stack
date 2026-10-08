# The tunnel (WireGuard)

[← Back to the README](../../../../../README.md#bundled-software--stack) · [The pack](web.md)

A WireGuard tunnel inside the instance, driven by `gmake`, from the
configuration your provider gives you. No VPN client: the profile *is* the
authentication.

It carries the traffic of this distro — Firefox, `curl`, `pip`, a `git push`.
Not Windows, not your other distros, not Docker Desktop.

## The targets

| Target | What it does |
| :--- | :--- |
| `vpn_status` | Up or down, the server, the kill switch and where its rules are, the DNS, the exit IP, what the distro starts with |
| `vpn_up [id]` | Connect. Naming a server — `gmake vpn_up VPN_PROFILE=NL72` — uses it for this call only |
| `vpn_up_from_list` | Connect, picking the server in a menu |
| `vpn_down` | Disconnect |
| `vpn_server [id]` | The server the distro starts with; switches to it now if a tunnel is up |
| `vpn_ks_on` / `vpn_ks_off` | The kill switch in the tunnel, or out — its rules too, from any instance — and a remount |
| `vpn_auto_on` / `vpn_auto_off` | Bring the tunnel up when the distro starts, or stop |
| `vpn_edit_profiles` | Open the JSON of servers in `$EDITOR` (nano when unset), then pick the server |

`vpn_up`, `vpn_up_from_list` and `vpn_down` end on what `vpn_status` shows,
after the server's first handshake. `wg-quick`'s own trace prints only on
failure.

## The servers

`~/.config/vpn/servers.json`, mode `600` — it carries your private keys, and
the pack never writes in it.

```json
{
  "id": "NL72",
  "note": "free server",
  "address": "10.2.0.2/32, 2001:db8::2/128",
  "private_key": "…",
  "DNS": "10.2.0.1, 2001:db8::1",
  "peer": {
    "public_key": "…",
    "endpoint": "198.51.100.1:51820",
    "allowed_ips": "0.0.0.0/0, ::/0"
  }
}
```

| Field | What it is |
| :--- | :--- |
| `id` | The name the menus show and `VPN_PROFILE` carries |
| `address`, `private_key` | From the provider's configuration |
| `DNS` | The resolver that configuration names |
| `peer.*` | The server's key, its address, what goes through the tunnel |
| `note` | Yours |
| `mtu`, `peer.persistent_keepalive` | Optional; without them: `VPN_MTU`, none |

Adding a server is one more entry. There is no import command.

## The settings

| Variable | What it decides |
| :--- | :--- |
| `VPN_PROFILE` | The `id` in use, and the one the distro starts with |
| `VPN_KILL_SWITCH` | `true`: the tunnel rejects what would leave outside it |
| `VPN_MTU` | The tunnel's MTU, for every server whose entry says nothing |
| `BASE_DNS` | What the instance resolves with while no tunnel is up |

They live in `~/.config/zsh/gmake/.env.global`; `gmake vpn_server` and the kill
switch targets write the first two, the last two are yours — an entry of
`servers.json` saying its own wins.

## The generated profile

`/etc/wireguard/vpn.conf` is written from the two files above before every
mount. Not a file to read or edit: the interface is always `vpn`, and a hand
correction is gone at the next mount.

## When it does not connect

| What you see | What it means |
| :--- | :--- |
| `sudo wg show` has no `latest handshake` line | The server never answered. First suspect: the endpoint — an IPv6 address an instance without an IPv6 route cannot reach (`ip -6 route show`) |
| The exit IP is unreachable, handshake present | The traffic leaves but something eats it: lower the MTU (`"mtu": "1380"` in the entry), or check the kill switch |
| No interface at all | `wg-quick`'s own words are on screen — printed on failure |

## The DNS

`openresolv` owns `/etc/resolv.conf`: the profile's `DNS` while the tunnel is
up, `BASE_DNS` below it while it is down.

The file is openresolv's symlink into `/run`, and `/run` is empty at every
start: the boot hook puts the base back each time, so a restarted instance is
never left without a resolver.

**WSL fights for that file.** It puts its own back at every start and answers
the instance's DNS itself — any nameserver resolves, and a missing file means
no resolution at all. To hand the file back, in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
dnsTunneling=false
```
## The kill switch

`vpn_ks_on` writes `VPN_KILL_SWITCH=true` and puts two `iptables` rules in the
profile; `vpn_ks_off` takes them out. They reject what would leave outside the
tunnel — **for this instance only**: all distros share one kernel and one
firewall, so each rule names this instance's own place in it (its cgroup).

```bash
sudo iptables -S OUTPUT | grep -c 'wsl-stack kill switch'   # 2, one per family
```

Both carry that label so they can be found from anywhere: `vpn_ks_off` sweeps
whatever the label finds, any instance, and `vpn_up` sweeps before raising.
`vpn_status` says what the kernel really holds (here, another instance,
nothing) — not always what the variable was set to.

WSL renumbers that place at every start of the distro. A mount — the boot
hook's included — rebuilds the profile first, so its rules carry the current
number; rules from a previous start stop matching until the next `vpn_up`,
`vpn_ks_on` or `vpn_down`.

While a tunnel is up, services on Windows reached through the WSL gateway are
rejected too.

