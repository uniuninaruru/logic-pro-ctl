[日本語](SA-GUI-COMMAND-001.md) | [English](SA-GUI-COMMAND-001.en.md)

# SA-GUI-COMMAND-001: command payloads and Key Commands navigation

**The existing menu-related helper leads to Key Commands navigation. It does
not establish which right-click gesture selects that route.** Close this small
export before choosing new functions from actual GUI captures.

| Evidence | Scope |
|---|---|
| Build | Logic 12.3.1/6682, arm64 SHA-256 `2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998` |
| Existing bodies | `0x0086625c` / 328 B; `0x0086668c` / 392 B |
| Byte checks | All 720 B / 180 words and nine caller instructions match installed file, analysis copy and saved import identity; zero mismatches |
| Outputs | [Seven instruction-backed facts](../protocol/gui-command-navigation-boundaries.tsv), [manifest and caller anchors](gui-command-navigation-manifest.json) |
| Observation | Static only. No GUI gesture, command execution or MIDI assignment was tested for these routes |

The payload adapter `0x0086625c` resolves a SongID value through `0x019a0a90`.
Only a nonnull result with byte `+0x85c == 1` survives as context. The adapter
passes a signed 16-bit command, resolved context, an ignore-feature scalar,
KeyUp-dependent `w3` values 4/2 and the low 32 bits of TrackID to `0x008663d4`.
The exported `DontLearn` key accompanies counter increments/decrements on the
normal path; the counter's purpose and exceptional paths are unproven.

The navigation helper `0x0086668c` takes an **entry pointer**. Exported symbols
name its UI calls `show`, `KeyCommandsController::showAll:(0)` and
`scrollToBefGruppe:befehl:`. It searches 28 group descriptors and 40-byte entries
by pointer equality, then passes signed group/entry indices to the navigation
call. Exhaustion yields `(-1, 0)`. Passing a catalog command number as this
helper's input would confuse an ID with a pointer.

Feature predicates are real gates. The first uses cache and `0x27`; later checks
use descriptor `+0x28` and the actual result of `0x0169bb34(handler, arg, 0)`.
The decompiler drops these arguments/results, the resolver return and some
scalar types. The instruction-backed flow is required; apparent pointer casts
or a constant-one return in exported C do not establish the contract.

Nine existing direct caller sites reach the navigation helper: six `BL`, three
tail `B`. Named callers include `ContextMenuCreator::_popupMenuItemCall:` and
`ControllerAssignmentsController::click_assignKeyCommandShow:`. Their bodies
were not expanded. These edges support a GUI relationship **Hypothesis**, not
a proof of menu construction, modifier behavior or generic MIDI dispatch.
Fresh selector/class metadata and current Ghidra annotation state were not
independently queried; method names above come from the existing export.

Next, follow [PLAN-GUI-001](../plans/PLAN-GUI-001.en.md): capture the actual target,
selection, labels, enabled states and order; choose one visible action; use the
[offline matcher](../../Tools/research-scripts/gui_command_candidates.py) for
catalog candidates. Predicate effects, eligibility, MIDI class/source linkage
and runtime success remain unverified; this adds no product capability.
