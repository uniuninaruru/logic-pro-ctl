# SA-IDENTITY-001: Binary input identity — source files, arm64 slices, and Ghidra imports

[日本語](SA-IDENTITY-001-binary-inputs.md) · [English](SA-IDENTITY-001-binary-inputs.en.md) · [Identity manifest](binary-identity-12.3.1-6682.json) · [Development plan](../plans/agent-ready-roadmap.en.md)

**The SHA-256 of MACore's entire universal source file differs from that of the thin arm64 image imported into Ghidra.** The check on 2026-10-02 found that the source file's arm64 slice, analysis copy, and Ghidra's stored Executable SHA-256 match. Logic's source file is already thin arm64, so its entire source-file hash also matches.

This record covers **only the binary identity subset of PLAN-01**. It does not complete the full evidence index, protocol analysis, peer connections, live gates, or product implementation. It does not mark the whole of PLAN-01 complete.

## Target and evidence

| Field | Observed value |
|---|---|
| Recheck date | 2026-10-02, Asia/Tokyo |
| Manifest capture time | `2026-10-02T00:09:36.849240+00:00` |
| Application | Logic Pro Creator Studio 12.3.1 / build 6682, `com.apple.mobilelogic` |
| Environment | macOS 27.0 / build 26A5416b, arm64 |
| Installed source files | `/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/{Logic,MACore}.framework/Versions/A/{Logic,MACore}` |
| Analysis copies | `/Users/nagataharuto/GhidraProjects/logicctl/bin/{Logic,MACore}.arm64` |
| Ghidra project | Directory `/Users/nagataharuto/GhidraProjects/logicctl`, project name `logicctl` |
| Ghidra metadata | Version `12.1.4`, language `AARCH64:LE:64:AppleSilicon`, compiler spec `swift`, image base `00000000` |
| Read-only report | [ProgramIdentityReport.java](../../Tools/ghidra/ProgramIdentityReport.java) |
| Versioned record | [binary-identity-12.3.1-6682.json](binary-identity-12.3.1-6682.json) |

Paths, application names, and environment details are observations from this check. They are not constants for other environments or a general guarantee of build support.

## What must match

1. Identify the original installed thin/universal file with the hash of the **entire source file**.
2. Identify the **selected architecture slice** within it, recording bytes, offset, size, UUID, and hash.
3. Compare that slice with the **analysis copy**, checking bytes, architecture, UUID, and hash.
4. Read the corresponding Ghidra program's **stored Executable SHA-256** directly and compare it with the slice/copy hash. Also record the program name and language.

The required match in this check is `selected_slice.sha256 == analysis_copy.sha256 == ghidra_program.imported_executable_sha256`. Do not substitute the entire universal source-file hash into this equality.

| Target | Entire source-file SHA-256 | arm64 slice SHA-256 | Analysis-copy SHA-256 | Ghidra's stored Executable SHA-256 |
|---|---|---|---|---|
| Logic | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` | `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| MACore | `76ab2a5f50b3ef120786369b5bf8b53dfc87a3b4107438e0894ab5f9b8095c52` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` | `99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076` |

The manifest records slice locations within the source files and UUIDs separately.

| Source file | Architecture | Slice offset (bytes from source-file start) | Slice size (bytes) | Mach-O UUID |
|---|---|---:|---:|---|
| Logic: thin | arm64 | 0 | 40710736 | `641ea797-e5a3-3ff1-8188-b36067cf8361` |
| MACore: universal | x86_64 | 16384 | 2346464 | `0d8a684c-1991-3699-8602-70e453626582` |
| MACore: universal | arm64 | 2375680 | 2248544 | `c225c0d6-7d88-3bcc-a570-ebae658e1a6a` |

The entire MACore source file is 4624224 bytes. Its x86_64 slice SHA-256 is `ed6674bc1e19bc64b53a23bd8a53d097248e3664db16b184342f3897f10edb05`. This identifies a different architecture; it is not the expected hash for the `MACore.arm64` import checked here. The analysis-copy UUIDs match those of the respective selected arm64 slices.

## Direct Ghidra metadata checks and limits

The reports opened the existing `Logic.arm64` program, then `MACore.arm64`, with `-noanalysis -readOnly`, **one process at a time**. `ProgramIdentityReport.java` reads `currentProgram.getExecutableSHA256()` and writes no report unless the specified program name and expected **slice hash** match. Source-file/copy comparisons and this direct Ghidra metadata read are separate pieces of evidence.

The direct JSON results and headless logs are local files listed below. The versioned manifest records each file's SHA-256.

- [Logic identity JSON](../raw/20261002T000630Z-binary-profile/Logic.arm64.identity.json) · [Logic headless log](../raw/20261002T000630Z-binary-profile/Logic.arm64.headless.log)
- [MACore identity JSON](../raw/20261002T000630Z-binary-profile/MACore.arm64.identity.json) · [MACore headless log](../raw/20261002T000630Z-binary-profile/MACore.arm64.headless.log)

The stored Executable SHA-256 is **metadata for the original import input**. It is not a checksum of the Ghidra database and does not guarantee that types, labels, or analysis annotations have remained unchanged. The match supports import-input identity; it does not guarantee the integrity or semantic correctness of all analysis results.

## Recheck example

This example uses an existing Ghidra project. Run it from the repository root with `GHIDRA_HEADLESS` set to the absolute path of an existing `analyzeHeadless` and `JAVA_HOME` set to the Java environment in use. It supplies MACore's **arm64 slice hash** as the expected value, rather than the universal file's `76ab2a5f…` hash.

```sh
mkdir -p "$PWD/Research/raw"
identity_run=$(mktemp -d "$PWD/Research/raw/identity-recheck.XXXXXX")
"$GHIDRA_HEADLESS" "$HOME/GhidraProjects/logicctl" logicctl \
  -process MACore.arm64 -noanalysis -readOnly \
  -scriptPath "$PWD/Tools/ghidra" \
  -postScript ProgramIdentityReport.java \
  "$identity_run/MACore.arm64.identity.json" \
  MACore.arm64 \
  99a4a9adbf79c92046682eb821d8ef35145f4915a29b88839c4f026ae63cd076 \
  > "$identity_run/MACore.arm64.headless.log" 2>&1
```

Treat a missing program, a name/hash mismatch, or a missing report as unverified. A successful report alone does not establish that the current source file/copy also match; compare them separately. The general `query.sh` has no hash guard, so perform this check before queries that use fixed addresses as well.

Do not run queries, reports, imports, or updates concurrently in the same Ghidra project. Run read-only operations sequentially too. Recreate the source-file and slice profile for another build. Keep raw binaries, decompilations, Ghidra databases, and raw logs local; only add curated records, manifests, and report source to Git.

## Scope of this check

This check did not modify installed binaries, save Ghidra database changes, attach to a target process, connect a peer, or send AppleEvents/MIDI or other application operations. It does not change the overall plan for existing AE/MCU paths.

New peer connections in PLAN-05 require explicit approval after describing the target and messages to be sent/received, as directed by the user on 2026-10-02. Static analysis and offline preparation can proceed first. This identity check establishes neither approval nor successful connection.
