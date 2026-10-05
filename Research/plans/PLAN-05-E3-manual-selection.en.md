# PLAN-05 E3-1: Match a manual selection change to Remote updates

[日本語](PLAN-05-E3-manual-selection.md) · [English](PLAN-05-E3-manual-selection.en.md) · [Previous approval scope](PLAN-05-approval-brief.en.md)

The first run's reception, timing, and verification scope are recorded in [EXP-REMOTE-003](../experiments/EXP-REMOTE-003-reconnect-selection-baseline.en.md).

**The goal is to match a human selection change in Logic to received messages and statically identified sender functions.** The previous reception covered initial state only. This run changes selection once while receiving, then compares `/sti` and other updates with the existing Ghidra results.

| Item | Scope |
|---|---|
| Status | On 2026-10-05, the user approved one connection, which ended after 120 seconds. No selection change was observed in that window, so the comparison remains incomplete. A retry awaits approval for an additional connection |
| Project | Dedicated `LogicCLI-Test.logicx` only. Do not run with another song open |
| Connection | Same research peer `logicctl-research-peer`, once. Only `/protocolVersion=10` and `/jsonSupport=1` are sent, once each |
| Changed condition | Selection only. No simultaneous creation, deletion, reorder, volume, mute/solo or song switch |
| Duration | At most 120 seconds from `receive_window`, after connection and both initial send calls succeed. Baseline and manual-action waiting share this window |
| Storage | `Research/raw/remote-recv/<timestamp>-e1/`. Publish only organized results and bilingual experiment notes |

```mermaid
sequenceDiagram
    participant U as User
    participant L as LogicCLI-Test
    participant C as Research receive peer
    participant A as Codex
    U->>L: Check the open song and selection
    A->>C: Connect once under the same name
    U->>L: Accept a connection dialog if shown
    L-->>C: Initial state
    A-->>U: Baseline captured; identify one target
    U->>L: Select that track once
    L-->>C: Updates
    A->>A: Compare before/after and static functions
    A->>C: End capture and close connection
```

## Procedure

1. The user opens the dedicated project and checks the selected track and stopped transport. Codex records the starting state. Track names are chosen from the current screen.
2. Build the research app from the corrected source, record source and launched executable hashes, then run `run.sh e1 --seconds 120 --target <current advertised name>` once. Keep the existing peer name. The user accepts a Logic prompt if one appears. Require two initial `sent` events and no send failure. Success here means `MCSession.send` did not throw; it does not guarantee Logic's acceptance.
3. Codex identifies receipt of decoded initial `/ati`, `/sti` and `/gtFaderData` in the logs as a baseline. This is an experiment boundary, not a claim that all initial transmission is complete. If any is absent, decoding fails or too little time remains to instruct the user, end without changing selection.
4. After Codex's signal, the user selects one different track. Record its name, before/after action times and frame numbers. Make no other changes during this window. Baseline detection and manual markers are an operator procedure, not automatic features of the receive peer.
5. List changed and unchanged `/sti`, `/ati`, `/gtFaderData` and `/cs/…` messages. Record an absent item as absent; do not fill it with zero.
6. End on timeout, disconnection, the user's stop signal or unexpected UI changes. For an operator abort, Codex uses `touch <output>/STOP` and checks `finish` and the summary. If restoring the selection, the user does so after capture and records restoration as a separate action. No automatic save or Undo.

Append baseline and action records to a separate `manual-actions.jsonl`. Each row records `kind` (baseline / action_before / action_confirmed / abort / restore), UTC time, the latest received frame, each baseline `/ati` / `/sti` / `/gtFaderData` frame and `t_ms`, and the selection name / index. Human action times do not prove a strict causal order of received frames; compare the before/after interval. Do not append externally to the peer's receive logs.

## Comparisons

| Observation | Static candidate / check |
|---|---|
| Does `/sti` follow selection? | `sendChannelStripInfo:` and selection handlers in [SA-REMOTE-STATE-001](../static-analysis/SA-REMOTE-STATE-001.en.md). Receipt alone does not prove execution at a particular address |
| Do the `/sti` index, name and `tn` match the current `/ati`? | Check that Swift `RemoteStateBuilder` and the offline validator resolve the same snapshot |
| Are `/ati` or faders updated by the same action? | Distinguish initial state, deltas, duplicates, ordering and unknown fields |
| Does selection also change record-enable? | Separate the deliberate selection from linked state changes. Additional record-enable operations are outside this run |

The previous single initial capture contained no deltas. This run does not validate identity across reordering, every value range or a completion marker for initial transmission. **Before/after reordering is a separate subsequent experiment** with a fresh baseline.

## Why confirmation is required before starting

The [existing plan](PLAN-05-approval-brief.en.md) reserves E3 and later for a separate discussion after E2. This run adds reconnection and a manual action during reception. Logic may show a connection dialog or register a device even under the same name. Start after the user accepts this plan. The peer remains receive-only and sends no editing commands.

## First attempt and proposed retry

The first attempt was `20261005-134359-e1`. Codex recorded the three-message baseline and signalled a change from Amped Up to Ballad, but that change was not observed during the 120-second reception. The connection ended; no additional connection has been made.

For a retry, after the user approves one additional connection for at most 120 seconds, **Codex will click a different track's selection control once through computer use immediately after capturing the baseline**. Recheck the dedicated project, stopped transport and current selection; record before/after AX states and the interval in `manual-actions.jsonl`. Do not edit the name field or click M/S/R. The user makes no other changes until reception ends and accepts a connection prompt only if one appears. No other operation, save, Undo or new connection name is included.
