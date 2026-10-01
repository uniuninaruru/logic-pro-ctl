# EXP-A3-001: relaunch Logic → does the Logic Remote TCP port change?

| Field | Value |
|---|---|
| Date | 2026-10-01 13:25 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a (no client connected) |
| Test project | ~/Music/Logic/LogicCLI-Test.logicx |
| Initial state | Logic pid 25338 (started 12:34:39), TCP *:51463, UDP *:7000, `_apple-lgremote._tcp` instance `174jnk4ko0l8w` |
| Single action | Quit Logic (Logic Pro > 終了), `open -a … LogicCLI-Test.logicx` |
| Expected change | Prior art: TCP port randomized per launch |
| Reproduction count | 1 relaunch |

## Observations
| | Before | After |
|---|---|---|
| pid | 25338 | 37546 |
| TCP listen (IPv4+IPv6) | 51463 | 52476 |
| UDP | 7000 | 7000 |
| `_apple-lgremote._tcp` instance | 174jnk4ko0l8w | 08n2x7g7zvtu4 |

Listening sockets appeared ≤3 s after launch.
Raw: `Research/raw/*-exp-a3-001-before/`, `Research/raw/*-exp-a3-001-after/`.

## Hypothesis
Hypothesis: TCP port and Bonjour instance name (peer ID) are regenerated per launch; UDP 7000 is fixed.
Confidence: high for "TCP port is not fixed" (direct counterexample); medium for "random each launch" (n=1); medium for "7000 fixed" (n=2 launches, it may be a configurable OSC setting).
Evidence: table above.
Counterexamples: none.
Next validation experiment: relaunch twice more; check whether the OSC port is configurable in Control Surface settings.

## Consequence for logicctl
The Remote backend must resolve `_apple-lgremote._tcp` via Bonjour at connect time; never cache the port.
