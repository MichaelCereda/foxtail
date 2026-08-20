# foxtail

Use several Tailscale tailnets at the same time on macOS.

The official Tailscale client connects to one tailnet at a time — switching
accounts is the only supported workflow ([tailscale#183][issue] has been open
for years). `foxtail` keeps the GUI app on one tailnet natively and runs every
*additional* tailnet as a userspace `tailscaled` behind a local SOCKS5/HTTP
proxy.

[issue]: https://github.com/tailscale/tailscale/issues/183

```
$ foxtail ls
NAME           PORT   STATE      TAILNET/ACCOUNT              NODES
(GUI app)      native native     dedi.example.com             4
work           1056   up         me@work.example              7
personal       1055   up         me@gmail.com                 6
```

## Why this works

Every tailnet allocates out of `100.64.0.0/10`, so two kernel-mode clients
would collide in the routing table. Userspace mode (`--tun=userspace-networking`)
gives the extra daemons no `utun` device, no route entries and no DNS
ownership — they hand you a proxy instead, so there is nothing left to fight
over. `--port=0` keeps their WireGuard sockets off the GUI app's 41641.

## Install

Needs `tailscaled` on PATH (`brew install tailscale`) alongside the GUI app,
plus `jq`.

```sh
git clone git@github.com:MichaelCereda/foxtail.git
ln -s "$PWD/foxtail/bin/foxtail" ~/.local/bin/foxtail
foxtail selftest
```

## Use

```sh
foxtail                    # interactive menu
foxtail ls                 # every tailnet and its state
foxtail up work            # start + log in, auto-picks a free port from 1055
foxtail down work          # stop the daemon, keep the login
foxtail exec work curl http://some-node/
foxtail ssh work some-node
foxtail rm work            # stop and delete state (asks first)
foxtail selftest
```

Browser login enrolls the node on whichever tailnet your browser session is
already signed into, which is easy to get wrong when you have several
accounts. To be certain which tailnet you land on, use an auth key:

```sh
TS_AUTHKEY=tskey-auth-... foxtail up work
```

## Limits

Extra tailnets are **TCP-only**: SSH, HTTP, database clients, tunnels. No
ICMP, no UDP, no exit-node routing, no Taildrop, and nothing for apps that
ignore proxy environment variables. Keep the tailnet you need full IP access
to — subnet routes, exit node — on the native GUI app.

Nothing listens on your behalf either; for inbound, use
`tailscale --socket=~/.tailscale-<name>/sock serve`.

Daemons do not survive a reboot. Re-run `foxtail up <name>` for each.

## State

One directory per tailnet, `~/.tailscale-<name>/`, holding the `tailscaled`
state, its socket, the chosen proxy port and a daemon log. There is no config
file — `foxtail ls` reads the directories and the running processes, so it
cannot drift out of sync with reality.

## License

MIT
