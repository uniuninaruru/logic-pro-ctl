# The write execution contract — retries, timeouts, conflicts, shutdown

[日本語](execution-contract.md) | [English](execution-contract.en.md)

[Back to the specification](specification.md) · [The read contract](observation-contract.en.md) · [README](../README.en.md)

`logicd` runs every command through one **executor**. It has one purpose:
**never turn an unknown result into success, and never run the same operation twice.**
An agent can tell what happened when a response is lost, a request times out or a command is resent.

## 1. Three safeguards (all optional)

| Option | What it protects |
|---|---|
| `--idempotency-key <key>` | Folds a resend of the same operation into one execution. Commands that change state only |
| `--expect-session <generation>` | Runs only if the connection is still the one you read from |
| `--deadline-ms <ms>` | Upper bound for queue wait plus execution. Default 30 s |

A key is 1–128 characters of letters, digits and `. _ : -`. Read commands cannot take one (`usage`).

## 2. `execution` in the response

Every response carries `execution`, saying how the request was handled.

```json
{"ok": true, "verified": true,
 "execution": {"state": "replayed", "idempotency_key": "mute-1-on",
               "queue_wait_ms": 0, "replayed_from": "2026-10-02T00:20:05Z"}}
```

| `state` | Meaning | What to do |
|---|---|---|
| `completed` | Ran, and the state was confirmed | Nothing |
| `replayed` | Returned the recorded result of the same key. Nothing was sent to Logic | Nothing |
| `read` | A read ran | Nothing |
| `not_applied` | Failed before reaching Logic. The key can be used again | Fix the cause and rerun |
| `rejected` | The request was not started (the reason is in `error`) | Follow the reason |
| `unknown` | **It may have run.** The result is not confirmed | Read the state; use a **new key** if you still want it |

## 3. Duplicates (idempotency keys)

Around each run a record (the journal) is kept per key. It holds a fingerprint of the command, arguments and route.

| Situation | Result |
|---|---|
| New key | Run and record |
| Same key, same content, previous run confirmed | **Not run again**; the previous result is returned as `replayed` |
| Same key, **different content** (arguments or route differ) | `idempotency_key_conflict`. Not run |
| An operation with that key is running | `request_in_flight`. Returned without waiting |
| Same key, previous result unknown | `outcome_unknown`. **Never rerun automatically** |
| Same key, previous attempt failed before reaching Logic (`not_applied`) | Run again |

A result becomes "unknown" when it is neither confirmed nor a failure known not to have reached Logic —
for example `verification_failed` (sent, state differs) or a timeout.
Failures known not to have reached Logic are `logic_not_running`, `surface_not_connected`, `invalid_argument`, `usage`,
`unknown_command`, `no_such_track`, `bank_unknown`, `bank_home_failed`, `precondition_failed`, `unsupported_*` and
`daemon_upgrade_required`. Any other failure is treated as unknown, on the safe side. For example
`readback_unavailable` counts as unknown because some paths cannot tell whether it happened before or after sending.

The journal is appended to `~/Library/Application Support/logicctl/journal.jsonl` (`LOGICCTL_JOURNAL`) and
survives a `logicd` restart. About the newest 500 entries are kept.

**A resend without a key cannot be deduplicated.** Give a key to any operation whose response might be lost.

## 4. Timeouts and lost responses

Execution has a deadline. When it passes, `logicd` returns `timeout` (`execution.state: "unknown"`).

- The operation on Logic **cannot be stopped**. It runs on in the background until it ends.
- Meanwhile the next command **does not overlap** it (there is one execution slot; the next waits for it).
- If the background operation **ends confirmed**, the record is updated to `completed` and a resend with the same key returns `replayed`.
  If it does not end confirmed it stays `unknown`.
- Waiting past the deadline gives `deadline_exceeded` and the command is **not started** (`rejected`).
- Too many waiting: `queue_full` (limit 8).

## 5. Writes based on a stale read (`--expect-session`)

`observation.session.handshake_generation` in a read is the generation of the connection to Logic.
With `--expect-session <generation>` a write is **not sent** and returns `precondition_failed` (`rejected`)
if the generation differs — Logic reconnected or restarted, or is not connected.

```sh
logicctl track list                     # note observation.session.handshake_generation (e.g. 4)
logicctl track mute 3 on --expect-session 4 --idempotency-key mute-3-on-001
```

The precondition guarantees only **the identity of the connection**. It cannot detect that someone changed a value
within the connection (a revision). A song change is detected only when Logic redoes the connection.

## 6. Shutdown and restart

- On `daemon stop` or a termination signal, writes still running are recorded as `unknown` (`daemon_stopped`).
  Later requests are refused with `shutting_down`.
- If `logicd` ended abnormally and left a running record, the next start marks it `unknown` (`daemon_restarted`).

## 7. Limits

- A running operation cannot be cancelled. A timeout means "stopped waiting".
- "Did not reach Logic" is decided from the list of error codes. A new error code falls on the unknown side.
- Exactly-once is not promised. What is promised: **a confirmed operation with the same key is not run twice**, and
  **an unknown run is never reported as success**.
- The journal belongs to this user on this Mac. It is not shared across Macs or users.
- A change made by a person in Logic cannot be detected by `--expect-session`.

Evidence: `Tests/LogicCoreTests/WriteExecutorTests.swift` (duplicates, conflicts, timeouts, restart, shutdown, preconditions).
