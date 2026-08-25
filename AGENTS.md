# Using foxtail from an agent

For automated callers — coding agents, CI jobs, scripts — that need to reach a
host on a tailnet other than the machine's native one.

The README explains what foxtail is and how it works. This covers driving it
non-interactively, and the parts that bite.

## The one command that matters

```bash
foxtail exec <tailnet> <cmd…>
```

`exec` runs `cmd` with `ALL_PROXY` / `HTTP_PROXY` / `HTTPS_PROXY` pointed at that
tailnet's userspace daemon. That is the entire integration surface: any tool that
honours proxy environment variables — `curl`, `kubectl`, `git`, `psql`,
`python3` with `urllib` — reaches the private tailnet with no other setup.

```bash
foxtail exec work curl -s http://service.internal/health
foxtail exec work kubectl get nodes
```

There is no "connect first" step. If the daemon is down, `exec` fails loudly
rather than silently falling through to the native tailnet.

## Orient before acting

```bash
foxtail ls                 # every tailnet and its state, native one included
foxtail nodes <tailnet>    # what is on that tailnet, with IPs and link status
foxtail doctor             # setup and daemon health; run this when exec fails
```

`foxtail ls` is how you learn the tailnet *name* to pass to `exec`. Never guess
it, and never assume the target is on the native tailnet.

All three are safe to run at any time — they read state and change nothing.

## Machine-readable output

`ls`, `nodes` and `doctor` print aligned columns for humans. To branch on state,
query the daemon directly rather than parsing them:

```bash
# is a tailnet up and logged in?
tailscale --socket="$HOME/.tailscale-<name>/sock" status --json | jq -r '.BackendState'

# is a specific peer online?
tailscale --socket="$HOME/.tailscale-<name>/sock" status --json \
  | jq -r '.Peer[] | select(.HostName=="build-box") | .Online'
```

`doctor` exits non-zero when a check fails, so it works as a gate:

```bash
foxtail doctor >/dev/null || { echo "tailnet setup is broken" >&2; exit 1; }
```

## Patterns that hold up

**Wrap only the network call, not the whole pipeline.** Local processing stays
local, which keeps output parsing debuggable and avoids proxying interpreters for
no reason.

```bash
foxtail exec work curl -s http://service.internal/status \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['revision'])"
```

**Ask for a single value when polling.** Structured selectors survive `grep -q`
in a wait loop; table output does not.

```bash
until foxtail exec work curl -sf http://service.internal/version \
        | grep -q "$EXPECTED"; do
  sleep 20
done
```

**Poll on an interval matched to the thing you are waiting for.** Deploys and
rollouts take minutes; a 20 s interval is reasonable, a 1 s one is waste. Clean
up strays:

```bash
pgrep -fl "foxtail exec work" | head
```

**Run code on the remote host when the target is that host's own resources.**
`exec` gets you to a service's API; credentials and libraries often live only on
the far side.

**Pass secrets through the environment, never in the command line or a file.**
Arguments are visible in `ps` to every local user.

```bash
export API_TOKEN="$(security find-generic-password -s <service> -a <account> -w)"
foxtail exec work env API_TOKEN="$API_TOKEN" ./tools/check.sh
```

`foxtail exec work env -u API_TOKEN …` is the mirror, for asserting a tool still
degrades correctly with no credential present.

**Never print a secret's value.** Length or presence is sufficient evidence:

```bash
foxtail exec work curl -sf -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $API_TOKEN" http://service.internal/whoami
```

## Quoting

Nested quoting is where these commands actually break. The layers, outermost
first: your shell → `foxtail exec` → any remote `sh -c` → the remote interpreter.

- Prefer a heredoc, or a single-quoted body, and use `\"` for inner strings only
  where unavoidable.
- Selector expressions containing `{}` or `.` must be single-quoted.
- A backslash meant for the remote side has to survive your local shell first.

## When exec fails

1. `foxtail doctor` — machine setup and daemon health.
2. `foxtail ls` — is that tailnet `up`? `foxtail up <name>` restarts it.
   `TS_AUTHKEY=tskey-…` skips the browser, which is the only way this works
   unattended.
3. `foxtail nodes <name>` — daemon is up, but is the target node online?

Do not retry the command without `foxtail exec` "to see if it works". On the
native tailnet it will reach a different host, or nothing at all, and either
result is misleading.

## Unattended setup

Browser login cannot work without a human. For a machine an agent operates:

```bash
TS_AUTHKEY=tskey-auth-… foxtail up work
foxtail enable work        # launchd agent; survives reboots, restarts on crash
```

The key is written to a `0600` temporary file and passed as a `file:` reference,
so it never appears in `ps`.

## Limits worth knowing before you debug

`exec` is a SOCKS5 proxy. It carries **TCP only**.

- `ping` over a foxtail tailnet is not a reachability test. It cannot work. Use
  the actual TCP call you care about.
- No UDP, no exit-node routing, no subnet routes.
- Tools that ignore proxy environment variables need
  `foxtail forward <tailnet> <host> <local>:<remote>` and a `127.0.0.1`
  connection instead.
- MagicDNS names resolve inside the proxy, not on the host. `dig` and `host`
  will return NXDOMAIN for them, correctly. Names work fine through `exec`.
