# Reference review: logic-pro-mcp and its public forks

[Research guide](../README.md) · [Evidence and source bindings](logic-pro-mcp-reference-001.json) · [MIDI integration map](../static-analysis/SA-MIDI-ROUTE-001.en.md)

**The useful connections are a compact dispatcher/state API, current GUI element discovery, explicit delivery-versus-effect results, and timed MIDI experiments.** These can complement logicctl's verified MCU/assignment/Step paths. This is a code review of pinned snapshots, not a live validation or installation of an external server.

日本語要約：元リポジトリと公開フォーク30件を比較し、独自コード差分のある5件を重点的に確認。少数の操作窓口と状態取得の設計、GUIの対象検索、読み戻し、予約MIDI送信は参考になる。MIDIノート送信・時間を合わせた録音・ネイティブリージョン編集は区別する。外部コードは実行せず、既存の実機結果と照合して導入候補を選ぶ。

## Snapshot and review scope

Upstream: [koltyj/logic-pro-mcp](https://github.com/koltyj/logic-pro-mcp), default branch `main`, inspected commit [`bdc105e7defd3622b1869e2dcd0dfd5159e1409c`](https://github.com/koltyj/logic-pro-mcp/tree/bdc105e7defd3622b1869e2dcd0dfd5159e1409c). The repository's [license](https://github.com/koltyj/logic-pro-mcp/blob/bdc105e7defd3622b1869e2dcd0dfd5159e1409c/LICENSE) is MIT. No external source was copied into product code. Any later code reuse should retain the applicable notices.

GitHub's direct-fork list was checked on 2026-10-08: **30 public direct forks**. Default-branch comparisons found 8 identical, 16 behind, one ahead with documentation only, and five divergent code forks. Own fork changes were isolated against merge bases; upstream changes missing from an older fork were not counted as new capabilities. This is not a review of every non-default branch or every descendant fork. Exact heads, API comparison results, inspected file hashes and line ranges are retained in the JSON.

## Upstream mechanisms and practical limits

| Area | Code evidence | Connection to logicctl |
|---|---|---|
| API/state organization | Eight action dispatchers, six resources plus one track resource template, and an adaptive state poller | A small MCP layer over existing validated commands could reduce repeated tool definitions. Returned state still needs freshness, target identity and error information |
| MIDI note/CC/MMC | Byte builders and CoreMIDI delivery exist. Packet timestamp is 0; messages fan out to virtual sources and successful delivery is returned as unverified | Reuse pure encoding/validation ideas. Keep explicit source targeting, actual host timestamps and native result checks used by our MIDI experiments |
| Routing | The router stops after `success` or `unverified` | Delivery without a measured effect needs its own status. Retrying through another channel after an uncertain mutation can duplicate an operation; fallback needs a pre-delivery failure distinction |
| OSC mixer | Dispatcher passes `index/send_index`, while the OSC channel requires `track/send`. UDP send completion returns success, and fixed `/track/...` addresses lack a demonstrated Logic registration path | These are candidates for analysis, not a verified replacement for the observed controller-assignment or Remote paths |
| AX mixer writes | [setMixerValue](https://github.com/koltyj/logic-pro-mcp/blob/bdc105e7defd3622b1869e2dcd0dfd5159e1409c/Sources/LogicProMCP/Channels/AccessibilityChannel.swift#L307-L323) ignores the Boolean result of `AXHelpers.setAttribute` and returns the requested value without rereading it | Our operation contract must retain requested value, actual result and `verified`; an API call's return does not prove the knob moved |
| GUI discovery | Role/description/tree heuristics find transport, tracks and sliders; process discovery supports both Logic bundle IDs | Useful locator examples, subject to current version, language, visibility, selection and window checks. Positional strip indices do not establish stable target identity |
| Keyboard route | It activates Logic before synthetic events. Hardcoded and partly approximate shortcuts remain, including the quantize/goto-position key-code overlap | Use the current KC001 inventory and named menu/action evidence; the README's background-event and latency claims are not benchmarks of our installed app |
| Feedback/state | MIDI/OSC streams exist but lack consumers in the inspected source. Parser state does not implement the advertised running-status/spanning-SysEx behavior | Retain the observed MCU/GUI/native readback paths; validate packet traversal and stateful parsing before adopting feedback code |

Several plug-in, region and automation AX operations explicitly return “not implemented.” A MIDI send operation is not a native region editor or a verified recording procedure. No reviewed upstream route establishes current generic learned-MIDI assignment → internal numeric command-ID dispatch.

## Five forks with substantive code changes

| Fork | Inspected additions | Bounded assessment |
|---|---|---|
| [jaanvahk/logic-pro-mcp](https://github.com/jaanvahk/logic-pro-mcp) | `record_pattern`, straight/shuffle note timing, chord/instrument operations | A concrete scheduling example. Recording setup clears existing Piano Roll notes and uses a fixed 95 ms start offset; `recorded: true` is not native region readback. Test only in a new empty region if adapted |
| [guitargnarr/logic-pro-mcp](https://github.com/guitargnarr/logic-pro-mcp) | Chord and timed sequence playback | Useful sequence representation; some dispatcher/channel operation names mismatch, and asynchronous sequence completion is not verified when the initial result returns |
| [patpatmedia/logic-pro-mcp](https://github.com/patpatmedia/logic-pro-mcp) | HID selection/track creation, selected readback, dialog guards and Track Stacks | Useful observation/guard patterns. Stack creation acknowledges confirmation without final stack readback; mixer/toggle mutation verification is still incomplete |
| [wonderstone/logic-pro-mcp](https://github.com/wonderstone/logic-pro-mcp) | Explicit manual/unverified MIDI bridges and staged source/identity/readback workflow | Useful vocabulary for preconditions and evidence. It does not establish generic key-command/internal-ID dispatch on our current Logic |
| [jovincroninwilesmith/logic-pro-mcp](https://github.com/jovincroninwilesmith/logic-pro-mcp) | Current AX locator adjustments | Candidate locator comparisons; validate only against the current observed UI and avoid restoring old behavior already corrected upstream |

Older fork bases and independently incorporated upstream fixes can overlap. These rows identify inspected additions, not a guarantee that each is unique to the current upstream or works on Japanese Logic 12.4.

## Adopt in this order

1. **Action/state contract:** build any MCP adapter over logicctl's existing command router and capability/readback data. Keep eight-or-fewer broad action groups as an option; avoid advertising unfinished operations. Treat delivery, completion and verified effect separately.
2. **GUI target discovery and readback:** compare the locator and blocked-dialog examples with the official guide and current UI. Prefer a named control and before/after measurement; tie cached values to a project/target and observation time.
3. **MIDI assignment to current commands:** reuse our [KC001 inventory](../experiments/EXP-KC-001-key-command-inventory.en.md) and [KC002 learned CC24 execution](../experiments/EXP-KC-002-midi-to-key-command-loop-browser.en.md), then trace the corresponding current record/handler. The upstream raw `send_cc` operation supplies no replacement for assignment setup or ID proof.
4. **Note scheduling experiments:** use fork pattern/sequence formats as comparison material, with measured host timestamps, BPM-derived timing, explicit source and result validation. Retain [MIDI033 Step input](../experiments/EXP-MIDI-033-step-region-edit.en.md) for the already observed native note placement; timed recording still needs recording-start/latency and note-position proof.
5. **Future GUI operations:** use Track Stacks, instrument and region candidates to choose one official-guide-led experiment at a time. They can extend the command/target map after actual readback.

No external installation, build, test suite or Logic operation was performed for this review. Source analysis cannot establish latency, recording accuracy, Japanese UI compatibility or universal parameter access. Curated evidence links this review to the ongoing controller/command work while preserving those boundaries.

## Adopted: compact MCP entry over existing commands

After this review, logicctl gained an independently written `logicmcp` stdio
adapter using the 2025-11-25 MCP protocol. The design adoption is compact action
groups plus state resources; no upstream source code was copied or executed.
See [setup and supported scope](../../docs/mcp.md).

Four tools expose 14 existing CLI operations: reads, transport, track switches
and mixer values. Three fixed state resources and one track resource template
reuse CLI reads. The adapter preserves requested/observed values, `verified`,
observation freshness and the execution contract. Missing daemon capabilities
still reject protected operations before delivery; uncertain failures do not
trigger retries or fallback through another backend.

Offline validation passed 20 new Swift tests and five real MCP → CLI → fake-daemon
wire tests, including an interactive handshake before stdin closes. All 193
existing Swift tests passed. An interactive check caught Foundation pipe reads
waiting for a full buffer; the executable now uses a bounded single POSIX read.
These tests validate the adapter and contract preservation, not a new live Logic
feature or a full client-application interoperability trial.

| Comparison at this adoption milestone | Reviewed logic-pro-mcp | logicctl |
|---|---|---|
| MCP interface | Existing Swift SDK server, eight dispatcher groups, seven resource surfaces | New four-group stdio adapter, three resources plus a track template; narrower scope |
| Operation breadth | Includes note/CC sends, key commands, GUI/OSC/AppleScript routes; implementation and verification vary | Existing transport/track/mixer commands exposed; research MIDI/region operations not yet public tools |
| Effect reporting | Inspected channels range from explicit unverified delivery to requested-value echoes | CLI readback, target/session guards, execution uncertainty retained at the MCP boundary |
| Current controller/internal research | No inspected proof of learned-MIDI → current numeric internal dispatch | Current assignment and key-command observations plus bounded function/getter links; dispatcher rebinding remains pending |

The reviewed upstream is ahead in interface breadth and existing MCP product
surface. Our current strength is a narrower operation contract with explicit
readback and research evidence. This comparison does not rank measured latency,
all GUI features or arbitrary plug-in access, which were not tested here.
