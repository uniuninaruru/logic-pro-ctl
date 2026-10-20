# REA-HANDOFF-001: inherit evidence without replacing the Ghidra database

日本語概要: REA 6.7.0を既存の調査へ追加した。保存済みLogic 12.3.1／12.4コピーをREAで検査し、従来のSHA-256・UUIDとの一致を確認した。ただし標準REA Ghidra経路は新規一時プロジェクトへのimportであり、既存`.gpr`の型・注釈をそのまま継承する機能ではない。既存Ghidra・出力・調査記録を本体として保持し、REAを版付きの補完証拠へ接続する。

Machine-readable identities, Evidence IDs and source bindings: [JSON](rea-ghidra-handoff-001.json). Existing anchors: [binary identity](../static-analysis/SA-IDENTITY-001-binary-inputs.en.md), [MIDI route map](../static-analysis/SA-MIDI-ROUTE-001.en.md), [current readback limit](channel-eq-ax-context-002.en.md).

## Verified readiness and actual REA use

The installed skill is version 42; the registered CLI package is `rea-agents@6.7.0`. Codex registration is aligned. A doctor run with the **registered process environment** recognized Ghidra **12.1.4** and JDK **21.0.12.1**. A plain-shell diagnostic initially lacked those environment variables; that was not proof Ghidra was absent. No client configuration, engines or global toolchains were installed or modified in this pass. REA MCP tools were not advertised in this active Codex session; live connection status remains unknown. The existing package CLI worked.

Two `inspect_macho` CLI calls inspected preserved copies. These are real REA Evidence, provider **native-macos**, not Ghidra database queries or runtime observations:

| Preserved artifact | SHA-256 prefix | Mach-O UUID | REA Evidence suffix |
|---|---|---|---|
| Logic 12.3.1 / 6682 | `2f141e1a…050998` | `641ea797-e5a3-3ff1-8188-b36067cf8361` | `…731b9260940083` |
| Logic 12.4 / 6707 | `48862b91…2bcda` | `6ce11532-8efb-3132-8c3d-d49ebef5ce34` | `…adcdbd522694` |

Full Evidence IDs, hashes and raw-file digests are in the JSON. An independent file SHA-256 check and REA's subject digest/UUID matched the prior profiles for both copies. The built-in inspector warns that stripped/toolchain-hidden symbols can be absent; normalized build metadata comes from otool, with vtool retained as provenance. Symbol absence is not proof of function absence.

## What the installed adapter actually inherits

A bounded inspection of the installed 6.7.0 implementation found:

- `GhidraClient.js:512–570` allocates owned private runtime storage and snapshots target bytes.
- `GhidraLauncher.js:411–415` selects `rea-project -import <target>`; lines 465–466 add `-readOnly -deleteProject`. The argument builder at 383–523 has no existing-program `-process` selector or `-noanalysis` switch.
- POSIX launch invokes the inspected JVM/headless class directly. The repository's analyzeHeadless wrapper would not automatically wrap that invocation.
- `REA_GHIDRA_SEED_FILE` admits **function/code/label** seeds, a partial transfer mechanism. It is not a complete type/comment/database import.

Thus standard REA native opening must not be described as attaching our existing `.gpr`, preserving its full annotations, or reusing its completed analysis. This conclusion is scoped to the inspected installed version; source digests and exact ranges are recorded in the JSON. No REA native session or Ghidra engine was opened to test it.

## Asset ownership and version boundary

The saved identity record binds project directory `GhidraProjects/logicctl`, project `logicctl`, program `Logic.arm64`, language `AARCH64:LE:64:AppleSilicon`, compiler `swift`, base zero to **12.3.1 / 6682**. Its saved executable hash identifies the original import, not all subsequent database annotations. The earlier 12.4 manifest records a preserved copy and `ghidra_current_program: null`; that historical record is not a fresh inventory of every project now on disk.

Historical target/readback work is reusable evidence, but its addresses are not automatically current-version addresses. Six `WrappedAssign` getters were independently rebound on 12.4 through copied-byte inspection. That does not establish current assignment-to-backend dispatch or plug-in-instance identity.

## Adopted workflow and first bounded questions

1. Start from the existing identity manifests, named functions, signatures, cross-references, decompilation exports and experiment records. Keep old interpretation, current byte checks and runtime observations distinct.
2. For a needed existing-database query, retain the repository route: identity guard, `Tools/ghidra/with-project-lock.py`, absolute shared lock `/Users/nagataharuto/logicpro cli/Research/raw/ghidra/logicctl-project.lock`, and `-process … -noanalysis -readOnly`. Do not delete/bypass either coordination or Ghidra locks. No database job ran in this pass.
3. Connect new REA Evidence by exact artifact digest and version. Ordinary Ghidra exports remain their original evidence; do not relabel them as REA-produced Evidence or assume `evidence-import` accepts arbitrary research JSON.
4. Use fresh REA native import only for a concrete unresolved gap, with its separate project and analysis cost explicitly announced. A copied binary or a few seeds do not transfer all existing database work. `--snapshot` caches exact completed results; it does not retain the Ghidra database. A new, uncached function query can therefore cause a fresh import even with the same snapshot. Use one persistent native session for multiple new bounded queries, and replay already-recorded results without invoking the provider. Persistent-session reuse was not exercised in this pass.

Codex's first question is the **assignment-to-target resolver**: which consumer of the current learned assignment selects the concrete plug-in backend/parameter, and which fields can reject replacement or stale targets? Current anchors are `assignmentClass` `0x69a1a4`, `befehl` `0x699554`, `valueMode` `0x69a600`, `multiply` `0x69a6f0`, `valueChangeHasLo7` `0x69a460`, `valueChangeHasHi7` `0x69a4ac`. These are image addresses in the recorded **12.4 copied artifact**, not live pointers or proof of the consumer path.

Installed-source trace: `domain/analysisSnapshot.js:132–138,331–360` stores results/evidence, not a project; `AnalysisSnapshotCache.js:161–185` returns exact cached results; `DirectAnalysis.js:128–168` checks replay before provider use. On a miss the Ghidra client starts a new private import; one-shot CLI cleanup closes it. The initial overview does not precompute every function body.

Claude reported one already-running private 12.4 overview job in CLDE094, writing a local snapshot. Codex acknowledged it as the sole heavy job and did not interrupt or duplicate it. The job completion and snapshot contents were **not inspected or validated** here; snapshot reuse must be checked per query before further calls.

Claude was assigned the independent **Pickup consumer** question, starting from saved exports/metadata and reporting the precise missing function before a heavy import. RDCO retains independent provenance and target-rejection review. The previous EQ named-selector/MIDI before-after gate remains incomplete; this static pass changed no Logic state and supplies no new `verified: true` capability.
