[日本語](manual-validation.md) | [English](manual-validation.en.md)

# What to validate by hand

**First, swap tracks 5 and 6 once in the dedicated test project.** Before/after JSON, MIDI, and Logic's undo history let us check whether a reorder reaches the MCU display and name checks. Eight previous attempts using synthesized mouse input and related methods did not produce a reorder; [EXP-MCU-023](../Research/experiments/EXP-MCU-023-add-delete-reach-surface.en.md) remains unverified.

| Priority | Human contribution | Evidence |
|---|---|---|
| 1 | Manually swap 5 and 6 in `LogicCLI-Test.logicx` | Actual order, undo history, before/after LCD, JSON and MIDI |
| 2 | Report the same observations on another macOS / Logic version | Version differences, including missing values and failures |

## 1. Prepare observation before moving tracks

Use **only `LogicCLI-Test.logicx`**. Keep names, volume, mute, solo and record arming unchanged, and note the initially selected track. The previous session ended with `Trk06` selected; check the actual screen and JSON for this run. Also note the latest entries in the undo history, then close it before preparing observation.

Before the move, note the last few entries in undo history and close the panel. This is the baseline for checking whether a new reorder entry appears afterward.

When working with an agent, say “The test project is open and I am ready to reorder,” then wait for its signal that tracing and the baseline are ready. The previous tracing daemon was stopped, so do not assume it is running.

To record the run yourself, execute these commands from the repository root. If release binaries are missing, run `swift build -c release` first. Each run gets a new folder excluded from Git.

```sh
manual_run_dir="Research/raw/mcu-trace/manual-reorder-$(TZ=Asia/Tokyo date +%Y%m%d-%H%M%S)"
mkdir -p "$manual_run_dir"
sw_vers > "$manual_run_dir/macos.txt"
git rev-parse HEAD > "$manual_run_dir/logicctl-commit.txt"
.build/release/logicctl daemon stop > "$manual_run_dir/daemon-stop-before.json"
.build/release/logicd --trace > "$manual_run_dir/daemon.stdout.log" 2> "$manual_run_dir/trace.log" &
manual_trace_pid=$!
```

Wait until the trace log says “接続を待っています” (waiting for connections). If startup fails, do not proceed to the reorder.

```sh
tail -n 12 "$manual_run_dir/trace.log"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-ready.json"
.build/release/logicctl track list --backend mcu > "$manual_run_dir/tracks-before.json"
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-before.json"
```

Check that `result.daemon.pid` in `status-ready.json` equals `$manual_trace_pid`, and that `result.mcu.connected` is `true`. The CLI starts a daemon automatically when none is available; if the PID differs, prepare tracing again.

In the `result` array of `tracks-before.json`, check `name` and `identity.name_unique` at positions 5 and 6. Use the following examples **only if the returned names are actually `Trk05` / `Trk06` and both are unique**. These five-character ASCII names avoid ambiguity from shortened or duplicate names. For different names, change the examples to the exact short, unique names returned. If those conditions cannot be met, record incomplete preparation instead of renaming tracks.

Check that the list and state have `ok` / `observation.complete` set to `true`. Do not reinterpret `null` or incomplete observations as zero or off.

## 2. Swap 5 and 6 by hand

Read position 5 and save the LCD and time immediately before the operation. `track get` / `track list` can move the MCU display range, so do not run them again until the move is finished. `status` returns a copy of the current LCD.

```sh
.build/release/logicctl track get 5 --expect-name Trk05 --backend mcu > "$manual_run_dir/track5-before.json"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-before.json"
date -u '+BEFORE_SWAP %Y-%m-%dT%H:%M:%SZ' >> "$manual_run_dir/markers.txt"
```

1. Bring Logic to the foreground and inspect the names and current order of tracks 5 and 6.
2. With your own mouse, move track 6 above track 5. Start away from the `M`, `S`, and record-arm buttons.
3. Check whether the order changed from `Trk05 → Trk06` to `Trk06 → Trk05`. If it did not, record “reorder did not occur”; do not mark it successful.

## 3. Capture the immediate result before moving the display

After the swap, make no other changes and wait briefly before running these commands. **Run `status` first** to capture the LCD before position alignment.

```sh
date -u '+AFTER_SWAP %Y-%m-%dT%H:%M:%SZ' >> "$manual_run_dir/markers.txt"
.build/release/logicctl status --backend mcu > "$manual_run_dir/status-after.json"
.build/release/logicctl track get 5 --expect-name Trk05 --backend mcu > "$manual_run_dir/old-name-check.json"
.build/release/logicctl track get 5 --expect-name Trk06 --backend mcu > "$manual_run_dir/new-name-check.json"
.build/release/logicctl track list --backend mcu > "$manual_run_dir/tracks-after.json"
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-after.json"
```

These commands **check** whether the old name returns `target_mismatch` and the new name matches. Preserve the actual JSON even if it differs. They check by reading; this experiment does not write mute state.

After capturing the result, open Logic's undo history and look for a new entry corresponding to the reorder. Record the actual entry text, before/after order and operation time. Opening history can also affect the trace, so distinguish it from the immediate swap observations. If neither the screen order nor history changed, the reorder remains unverified for this run.

## 4. Restore the project and share the result

Use Undo only if the corresponding reorder can be undone; availability is not guaranteed. Otherwise, manually restore the original order in the same test project and record how you did it. Check the original order and selection, then compare names, volume, mute, solo and record arming with the baseline. Record any accidental change or record-arm change caused by selection, and restore it through the UI.

```sh
.build/release/logicctl state --backend mcu > "$manual_run_dir/state-restored.json"
.build/release/logicctl daemon stop > "$manual_run_dir/daemon-stop-after.json"
wait "$manual_trace_pid"
```

**Do not save the project during this experiment.** Record any possibly remaining unsaved changes or history. If you need the usual daemon, `.build/release/logicctl status --backend mcu` starts it after tracing stops, provided the `LOGICD_TRACE` environment variable is not enabled.

Share whether the operation occurred, before/after order and checks, the MIDI observation window, reproduction count, and restored state. One run does not establish a guarantee across environments. Use the [experiment template](../Research/experiments/TEMPLATE.en.md), then share through the [contribution guide](../CONTRIBUTING.en.md) or [research issue template](../.github/ISSUE_TEMPLATE/research.md). Keep raw logs locally and share only minimal anonymized examples.

For another-version report, include macOS, Logic version / build, the `logicctl` commit, initial state in the same dedicated project and returned JSON. The commands above save macOS and the commit; also check and record Logic version / build in About Logic Pro. This procedure adds no AppleEvent sending or Logic Remote connection experiment.
