# EQ-AX-002: Channel EQ exposes a value in Controls view

日本語概要: Codex側の読み取り経路で、Controls表示の「Master Gain」行から **0.0 dB** を取得した。画面の目視だけではなく、AXValueDescriptionの実測値である。ただし、新しい行指定処理の実機確認、MIDI送信前後の比較、トラック・スロット・プラグイン実体の識別は未完了。Macの画面ロックを確認し、その後のMIDI送信は行わなかった。

Evidence and hashes: [JSON](channel-eq-ax-context-002.json). Related: [CS inventory](../static-analysis/SA-CS-PREFS-001.en.md), [CA004 calibration](../experiments/EXP-CA-004-channel-eq-gain-calibration.en.md), [milestone plan](../plans/midi-assignment-automation-001.en.md).

## Positive observation, with a bounded claim

On installed Logic **12.4 / 6707**, Claude switched the open Channel EQ from Editor to Controls without sending CC. Codex's read-only probe captured 291 nodes, 86 control candidates and 49 static labels in `eq-readback-context-check-005.json`. The dedicated test-project window passed the guard. The auxiliary window's exact AX title was **`Synth `**, including a trailing space; its body contained an `AXStaticText` value **`Channel EQ`** at path `[8]`. Thus neither a title containing Channel EQ nor an exact title `Synth` was sufficient for discovery.

| Native AX attribute | Captured value |
|---|---|
| Static label | `Master  Gain:` (two spaces) |
| Label path | `[9,0,32,0,0]`, window index 0 |
| Neighboring numeric-field role/path | `AXSlider` / `[9,0,32,0,1,0]` |
| AXValueDescription | **`0.0 dB`** |
| AXValue / AXMinValue / AXMaxValue | **240 / 0 / 480** |
| Identifier, title and description on that field | No value (`-25212`) |

The display description carries the physical unit. The raw value and range are **control-domain values**, not already dB. This single reading does not prove a conversion for all 481 raw positions, exact unrounded precision, writability, or persistent parameter identity. Two other controls in the same apparent row expose raw 240 without a value description. AXTitleUIElement was not obtained for the captured candidates; the label was a separate static-text node.

The paths establish a common parent prefix in the saved capture, not a persistent row/instance identifier. The capture predates the added parent-role field and new `--parameter-label` selector. Its positive selector replay is **offline correlation**, not a live run of that final selector.

## Execution contexts and failures remain separate

RDCO reported `AXIsProcessTrusted() == false` through its Remote Desktop Commander context. That stops before discovery; it does not prove that EQ values are unavailable. Codex's local context was trusted, but initially AXWindows returned two objects with role `AXApplication`, title `Logic Pro`, and equality with the application itself. A direct C implementation using CFArrayGetValueAtIndex independently reproduced that result, excluding Swift array bridging as the sole explanation. Compositor metadata showed the test-project and auxiliary windows but supplied no parameter binding.

Later valid captures included Controls (005) and Editor (006, 011). Editor had no matching separate Master Gain label, so the row query correctly returned `label_not_found` in 011. This is a limit of the current query, not proof that every Editor value is unreadable.

During the later view-only check, Codex activated Logic, captured the visible test project/Synth/Channel EQ with Gain **0.0 dB**, and opened the View menu once. Exact `コントロール` / `エディタ` items were observed. The guarded selection exited **before pressing Controls** when the test-window guard failed. A subsequent black capture and explicit session query recorded `screen_locked: true`, foreground `loginwindow` at 09:30:02Z. The final probe returned `ax_window_tree_unusable`, exit 1, both verification flags false. No CC was sent. The menu may remain open or dismiss on unlock; inspect before resuming.

The lock establishes the later session state. It does **not** retrospectively establish the cause of every earlier malformed-tree result. Codex did not alter TCC permissions, parameters, track selection, Solo, Pickup, slots or preferences. Claude's earlier GUI restoration from −6.2 to 0.0 dB is recorded by its experiment owner.

## Reader changes and checks

[logic-plugin-inspect.swift](../../Tools/research-scripts/logic-plugin-inspect.swift) accepts an observed PID, optional exact window-title hint, and optional parameter label. It searches auxiliary-window content, includes AXValueIndicator candidates, records attribute result codes and UTC observation time, and rejects malformed window objects. A title hint is discovery only; a named value additionally requires an exact Channel EQ **body static-text** label.

```sh
swift Tools/research-scripts/logic-plugin-inspect.swift --pid OBSERVED_PID --parameter-label 'Master Gain'
```

Label matching normalizes whitespace, a trailing colon and case. A selected value requires one matching label, a nonwindow AXGroup parent, no competing labels under that parent, one control with a value description, and a complete traversal. Ambiguity or transient AX errors suppress selection. Leaf `AXChildren.noValue` is valid absence; it must not be confused with a transport failure. Paths/indices remain ephemeral. Every output retains **`verified: false`** and **`plugin_instance_identity_verified: false`**, including errors.

The script compiled and recorded the live Editor negative query and locked-session rejection. An independent bounded review checked the saved label/value association and exposed guards against unrelated windows, broad containers, competing labels and partial trees. **The final guarded selector's positive live run remains pending.** No product endpoint or capability claim was added; no full product suite/CI expansion was needed.

## Next coordinated experiment

After unlock, confirm the dedicated project and current window state. Claude owns GUI/MIDI; Codex owns the reader and this note; RDCO owns its original feasibility notes and independent acceptance review. Reopen Controls, prove the final selector reads the baseline, then coordinate one CC127 → post-read and one CC48 → post-read, separately. Restore the owned view/value through Logic and capture restoration. Until that baseline is available, the send plan is **not armed**.

Keep delivery, assignment and observed value separate. Claude's seven GUI calibration samples support the rounded model `−24 + 48v/127`; they are not this probe's MIDI readbacks. Under that model CC48 predicts **−5.858267717 dB**, CC47 **−6.236220472 dB**, and exact −6 requires **47.625**. The earlier crossing explanation was corrected by Claude; the ignored first CC64 remains undetermined. Two-track validation, document → track → slot → instance → parameter binding, and replacement/ambiguity rejection precede a verified product operation.

Apple's [official plug-in-window guide, 10.7](https://support.apple.com/en-az/guide/logicpro/lgcpbc21a1fd/10.7/mac/11.0) documents Editor/Controls alternatives. The attempted 12.3 page was not retrievable in this client; installed 12.4 behavior above is live evidence, not a legacy-version guarantee. Apple's [Expert value parameters, guide 12.3](https://support.apple.com/guide/logicpro/expert-view-value-parameters-ctls71c308ee/12.3/mac/15.6) documents assignment modes/ranges; it does not guarantee AX identity or numerical precision.
