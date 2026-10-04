[日本語](README.md) | [English](README.en.md)

# Run Ghidra research jobs in sequence

Run headless jobs against the same Ghidra project **one at a time**, including jobs using `-readOnly`.
`with-project-lock.py` lets cooperating commands acquire a shared lock before execution and hold it until the command exits.

```text
Agent A ── acquire shared lock ── analyze ── exit and release
Agent B ── wait for same lock ────────────── acquire ── analyze
```

## One absolute lock path per project

`analyze.sh`, `appleevents.sh`, `query.sh`, `cfstrings.sh`, and `stackstores.sh` use this wrapper. Their default lock is `Research/raw/ghidra/logicctl-project.lock` in the current checkout.
**When different worktrees or checkouts use the same Ghidra project, set `GHIDRA_LOCK` to the same absolute path.** Otherwise each checkout's default creates a separate lock.

For example, place the lock in a common location. Every participant must use the same value.

```sh
export GHIDRA_LOCK="$HOME/GhidraProjects/logicctl/headless-coordination.lock"
Tools/ghidra/query.sh Logic.arm64 query-example 0x001a1dcc
```

Pass other scripts and direct `analyzeHeadless` calls through the same wrapper.

```sh
python3 Tools/ghidra/with-project-lock.py --lock "$GHIDRA_LOCK" -- \
  /path/to/analyzeHeadless /path/to/projects logicctl \
  -process Logic.arm64 -noanalysis -readOnly \
  -scriptPath "$PWD/Tools/ghidra" \
  -postScript XrefDecompile.java "$PWD/Research/raw/ghidra/query-example.c" 0x001a1dcc
```

Adjust paths and program names for your environment. This lock coordinates only commands that every participant passes through it. It does not control the Ghidra UI or commands that bypass the wrapper.

## Respect Ghidra's own locks

This coordination lock is additional to Ghidra's project locks. **Never remove, ignore, or bypass Ghidra's locks.** When a job waits, check the earlier job's log and process state. Do not delete the shared coordination lock file either: deleting it while in use can create separate locks and permit simultaneous jobs.

The wrapper's “Acquired” message means the command's turn has arrived. Check the latest Ghidra log and output to establish whether analysis succeeded. Put raw research output in `Research/raw/`, which is excluded from Git.

## Check the wrapper alone

```sh
python3 Tools/ghidra/test_project_lock.py
```

These tests use synthetic child commands to check serialization, exit codes, stdout, and a missing command. They also verify termination signals reaching the child process group and the child's lock remaining held after an abrupt wrapper exit. They do not start Ghidra or Logic Pro.

Lock inheritance depends on children and later descendants retaining the inherited file descriptor. A custom launcher that closes that descriptor does not provide the same guarantee.
