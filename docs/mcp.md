# MCP adapter

[日本語の入口](../README.md) · [English overview](../README.en.md) · [Reference review](../Research/notes/logic-pro-mcp-reference-001.en.md)

日本語要約：`logicmcp` は既存のCLI操作をMCPから呼び出す入口です。再生・停止・ミキサーなど14操作を4つのツールにまとめ、状態取得も提供します。実際の読み戻し結果を保持します。MIDIリージョン編集・プラグイン操作・汎用MIDI割り当ての自動設定は、今回の公開ツールには含まれません。

## Build and launch

Requires the same macOS 13 / Swift 5.9 environment as logicctl. No additional
package dependency is needed:

```sh
swift build -c release
```

Configure your MCP client to launch the absolute path to `.build/release/logicmcp`
with no arguments. For clients using a `mcpServers` JSON configuration:

```json
{
  "mcpServers": {
    "logicctl": {
      "command": "/Users/nagataharuto/logicpro cli/.build/release/logicmcp",
      "args": []
    }
  }
}
```

Replace the path if your checkout is elsewhere. `logicmcp` finds `logicctl` beside
it, or uses `LOGICCTL_PATH`. The existing `LOGICD_PATH` and `LOGICCTL_SOCKET`
environment settings still apply. Initialize/list requests do not launch Logic
or logicd; the first operation invokes logicctl, which may start logicd as usual.
Logic/MCU connection prerequisites and the supported backend profiles remain those
of the [CLI](../README.en.md). This adapter adds no new Logic-version support.

The transport is UTF-8 newline-delimited JSON-RPC on stdin/stdout. Diagnostics and
child-process diagnostics go to stderr. It implements the
[2025-11-25 initialization lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) and
[resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources).
Only protocol version `2025-11-25` is implemented. An initialize request offering
another version receives `2025-11-25`; the client must support that negotiated
version. Modern stateless protocol variants, HTTP transport, subscriptions,
tasks, prompts and server-initiated requests are not advertised.

## Tools and state

| Tool | Actions | Relevant arguments |
|---|---|---|
| `logic_read` | `status`, `state`, `list`, `get` | `track` for `get` |
| `logic_transport` | `play`, `stop`, `cycle`, `click` | Boolean `state` for cycle/click; optional `backend` (`mcu`, or `appleevent` for play/stop only) |
| `logic_track` | `select`, `mute`, `solo`, `arm` | 1-based `track`; Boolean `state` for mute/solo/arm |
| `logic_mixer` | `volume`, `pan` | 1-based `track`; `db` (number or `"-inf"`) for volume, `value` in −1…1 for pan; optional volume `tolerance` |

Common optional guards are `expect_session`, `deadline_ms` (1…30000),
`idempotency_key` on writes, and `expect_name` on track operations. Their meaning
and compatibility gates are unchanged from the [execution contract](execution-contract.md)
and [target identity](target-contract.en.md). Read before writing; use the returned
track name and connection generation when identity matters.

Fixed resources are `logicctl://status`, `logicctl://state`, and
`logicctl://tracks`. The template `logicctl://tracks/{track}` reads a single
1-based strip. Each resource read invokes the corresponding CLI read; no separate
MCP cache or polling process is introduced. Read failures return protocol errors
with the CLI failure attached. Missing or stale fields keep their original
`observation` metadata; requesting a resource does not make partial data complete.

Example tool arguments after reading track 1's actual name and session:

```json
{
  "name": "logic_mixer",
  "arguments": {
    "action": "pan",
    "track": 1,
    "value": -0.5,
    "expect_name": "Synth",
    "expect_session": 1,
    "idempotency_key": "pan-example-001"
  }
}
```

`Synth` and generation `1` above are examples, not discovered target identities.
The full CLI JSON appears in both text content and `structuredContent`.
`isError` reflects the CLI's `ok`; `verified`, requested/observed values,
backend, `observation` and `execution` are preserved. A transport delivery or
returned requested value is never promoted to a verified effect.

## Limits and verification

Calls are serialized. Each child process has a 40-second outer timeout and a
1 MiB stdout limit; unfinished incoming messages are bounded to 1 MiB. If a
command times out, its outcome is reported unknown: terminating the client cannot
undo work already sent to the daemon. The adapter does not retry or switch
backends automatically. Explicit idempotency keys retain the daemon's duplicate
protection when a caller decides to retry.

This first adapter exposes existing transport and mixer commands. Generic CC/key
assignment, Step input, Pattern Regions, Session Players, Apple Loops, plug-ins,
raw MCU sends and daemon shutdown remain outside its tool set. The MIDI research
provides observed routes and candidate integrations, not additional public MCP
tools yet.

The architecture takes the compact action/state organization from the reviewed
[logic-pro-mcp design](../Research/notes/logic-pro-mcp-reference-001.en.md).
The adapter is independently written against the MCP specification; no upstream
source code was copied. Existing CLI validation and daemon safeguards remain the
execution boundary.

Offline tests use fake executors/processes and a fake daemon socket. They cover
protocol negotiation, schemas, argument rejection, guard forwarding, result
preservation, resource reads and uncertain failures. They do not establish a new
live Logic capability or MCP-client application interoperability.
