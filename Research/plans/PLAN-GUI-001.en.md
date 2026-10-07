# PLAN-GUI-001: visible operations to command candidates

Status: plan and offline tooling only; no menu capture or feature operation is
reported as observed here. Use `LogicCLI-Test.logicx` only. Claude owns GUI/live
observation; Codex owns catalog matching and internal-route analysis. Agree on
the GUI slot and receiver ownership in the private board before a live run.

## Capture one context

1. Record UTC, Logic build, test-project title, stopped state, and a local
   screenshot/AX evidence path. Record region/track type, cursor hit zone and
   selection before opening a menu.
2. Open the menu once. Capture item label, enabled state, original order and
   submenu path. Dismiss without invoking an item; record selection afterward.
   Keep separators in raw evidence; omit them from label matching without
   renumbering the remaining entries.
3. For a comparison, restore the baseline and change one condition. If opening
   a menu also changed selection, record that confound and do not attribute the
   difference solely to cursor position.
4. Feed the captured labels to the offline matcher described below. Candidate
   IDs identify registrations, not a proven GUI handler or a usable command.
5. Choose one visible, enabled operation. Record its before/after effect and
   restore reversible changes. Then trace its ID/action/selector to the smallest
   relevant function set. An unmatched label is a localization/action target for
   follow-up, not permission to substitute a similar command.

## First queue

| Case | GUI question | Static lead, not observed applicability |
|---|---|---|
| GUI-01 | How do track-header and empty-Tracks menus differ? | Capture labels first; no fixed item index |
| GUI-02 | Does a region body's menu differ from its edge with the same selection? | Capture region type and exact hit zone |
| MIDI-01 | Can a generic MIDI message learn one visible key command? | Record assignment class/message and effect; class-9/source edge unproven |
| LOOP-01 | Which visible control opens/closes the Loop Browser? | ID 748, handler `0x00f50328`, arg `0x0` |
| PLAYER-01 | Which context exposes creation of a Session Player region? | ID 150, handler `0x0068e680`, arg `0x2` |
| PATTERN-01 | Which context exposes creation of a Pattern region? | ID 151, same handler, arg `0x3` |
| PATTERN-02 | Which selected region offers conversion to MIDI? | ID 1122, handler `0x0120ecac`, arg `0x0` |

IDs, labels and handler/arg pairs come from the existing
[static command catalog](../protocol/operation-catalog.tsv). Menu labels may
differ from catalog names. Eligibility, routing, generation and data formats
remain unverified. Player and Pattern creation sharing a handler does not prove
that they share region data or editing behavior.

## Offline label matching

The matcher never connects to Logic, opens menus, sends commands or touches a
project. It retains disabled items and duplicate registrations, and does not
translate or guess unmatched labels.

```sh
python3 Tools/research-scripts/gui_command_candidates.py --label 'Show/Hide Loop Browser'
python3 Tools/research-scripts/gui_command_candidates.py --capture Research/raw/gui/<run>/menu.json
```

Capture input is JSON with `context` and `items`. Each item requires a nonempty
`label`; include observed `enabled`, `order` and `path` when available. Context
carries target/region types, hit zone and selection before/after. Missing fields
remain unknown. Preserve raw evidence separately. Output is JSON with catalog
and capture SHA-256 provenance and candidate mappings; runtime/applicability
verification remains false even for an exact label match. Matching normalizes
Unicode NFKC, whitespace, case and a trailing ellipsis only. Context does not
automatically filter registrations, and unmatched localized labels stay unmatched.

日本語要約：画面で対象・選択・メニューの差を記録してから、既存の命令台帳へ
候補を照合します。右クリックの順番を固定しません。MIDI・Apple Loops・
セッションプレイヤー・パターンリージョンは優先候補ですが、この計画には
新しい実機観測や機能の確認結果は含まれていません。
