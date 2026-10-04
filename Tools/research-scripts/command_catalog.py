#!/usr/bin/env python3
"""Build the table of Logic's registered commands from static evidence (PLAN-07).

Logic keeps its command table in `DAT_026883b0[4951]`; the command dispatcher indexes it by
command number (`befehl`). It is filled at start-up by FUN_00863ec4, which registers 28 groups
of 40-byte entries (SA-004, SA-COMMAND-CATALOG-001):

    entry: int16 befehl @0 | CFString* name @8 | CFString* table @0x10 | handler @0x18 | arg @0x20

A group's entries are either a static array in the binary (13 groups) or are written by a
constructor function onto the stack and copied (15 groups). The group list is read from the
decompiled FUN_008630b4. Nothing is executed: no command is sent to Logic.

Inputs (all local; the Ghidra files are produced by Tools/ghidra/*.sh, see the SA document):
  --binary   Logic.framework's thin arm64 executable (static arrays)
  --group-c  decompile of FUN_008630b4, only to see which constructor precedes which group
  --stores   Tools/ghidra/stackstores.sh output: the constants those functions copy to their stack
  --cfstrings Tools/ghidra/cfstrings.sh output  (label, address, flags, length, text)
  --functions Logic.arm64.functions.tsv          (entry, size, name, signature)
  --remote   Research/protocol/cs-assign-remote.tsv (class 9 rows: command ids Remote can send)

  command_catalog.py --out Research/protocol/operation-catalog.tsv
"""
import argparse
import collections
import csv
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "Research" / "raw" / "ghidra"
DEFAULT_BINARY = ("/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/"
                  "Logic.framework/Versions/A/Logic")
TABLE_SIZE = 4951          # bzero(&DAT_026883b0, 0x9ab8) / 8
ENTRY_SIZE = 0x28
GROUP_STRIDE = 0x30
GROUP_COUNT = 28           # loop in FUN_00863ec4: 0x540 / 0x30
GROUP_FRAME = 0x598        # stack offset of the first descriptor in FUN_008630b4
PTR36 = 0xFFFFFFFFF        # chained-fixup pointer target: low 36 bits
# LgLogicRemoteController keyCommands: (0x01683e10) skips the group whose array is this one (Tool Menu) and
# every id in the set that -init stores with setSuppressedKeyCommands: (an NSConstantArray of 100 numbers).
REMOTE_SKIPPED_GROUP_ARRAY = 0x022ef240
SUPPRESSED_ARRAY = 0x02438128
SUPPRESSED_COUNT = 100


class Image:
    """Read-only view of the thin arm64 Mach-O, addressed by virtual address."""

    def __init__(self, path):
        self.data = Path(path).read_bytes()
        text = subprocess.run(["otool", "-arch", "arm64", "-l", str(path)], capture_output=True, text=True,
                              check=True).stdout
        self.segs, cur = [], {}
        for line in text.split("\n"):
            t = line.split()
            if len(t) > 1 and t[0] in ("segname", "vmaddr", "fileoff", "filesize"):
                cur[t[0]] = t[1]
            if t and t[0] == "filesize":
                self.segs.append((int(cur["vmaddr"], 16), int(cur["fileoff"]), int(cur["filesize"])))
                cur = {}

    def offset(self, vm):
        for base, fileoff, size in self.segs:
            if base <= vm < base + size:
                return fileoff + vm - base
        return None

    def u16(self, vm):
        o = self.offset(vm)
        return None if o is None else struct.unpack_from("<H", self.data, o)[0]

    def u64(self, vm):
        o = self.offset(vm)
        return None if o is None else struct.unpack_from("<Q", self.data, o)[0]


def load_cfstrings(path):
    by_address, by_label = {}, collections.defaultdict(list)
    with open(path, encoding="utf-8", errors="replace") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 5 or row[0].startswith("#"):
                continue
            label, address, text = row[0], int(row[1], 16), row[4]
            by_address[address] = (label, text)
            by_label[label].append((address, text))
    return by_address, by_label


def load_functions(path):
    names = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) >= 3 and re.fullmatch(r"[0-9a-f]+", row[0]):
                names[int(row[0], 16)] = row[2]
    return names


def read_suppressed(image):
    """The command ids Logic Remote is never offered: NSConstantArray {isa, count, objects*} of
    NSConstantIntegerNumber {isa, type*, value}."""
    count = image.u64(SUPPRESSED_ARRAY + 8)
    if count != SUPPRESSED_COUNT:
        raise SystemExit(f"suppressed-command array has {count} elements, expected {SUPPRESSED_COUNT}: another build?")
    objects = image.u64(SUPPRESSED_ARRAY + 16) & PTR36
    values = set()
    for i in range(count):
        number = image.u64(objects + 8 * i) & PTR36
        value = image.u64(number + 0x10)
        values.add(value - (1 << 64) if value >= 1 << 63 else value)
    return values


def load_remote_commands(path):
    """Command ids that Logic Remote's default assignments can send (assignment class 9)."""
    found = collections.defaultdict(set)
    with open(path, encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) >= 6 and row[0] != "model" and not row[0].startswith("#") and row[1] == "9":
                found[int(row[2])].add(row[5])
    return found


_ASSIGN = re.compile(r"^\s*(?:\w+\s+)?\w*?(?:local|Stack)_([0-9a-f]+)(?:\[\d+\])?\s*=\s*(.+?);\s*$")
_CTOR = re.compile(r"^\s*(FUN_[0-9a-f]+)\(\);\s*$")


def load_stores(path):
    """{function entry: {stack offset (signed): value}} from StackStoreReport."""
    stores = collections.defaultdict(dict)
    with open(path, encoding="utf-8", errors="replace") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 4 or row[0].startswith("#"):
                continue
            offset = int(row[1], 16)
            offset -= 1 << 64 if offset >= 1 << 63 else 0
            stores[row[0]][offset] = (int(row[3], 16), int(row[2]))
    return stores


def constructor_order(group_c):
    """Which constructor FUN_008630b4 calls just before it fills each group descriptor (decompiled C)."""
    lines = Path(group_c).read_text(encoding="utf-8", errors="replace").splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("// ==== FUN_008630b4"))
    end = next(i for i, l in enumerate(lines) if l.startswith("// ==== FUN_00864230"))
    ctors, pending = {}, None
    for line in lines[start:end]:
        m = _CTOR.match(line)
        if m:
            pending = m.group(1)
            continue
        m = _ASSIGN.match(line)
        if m and pending:
            n = int(m.group(1), 16)
            if GROUP_FRAME - GROUP_STRIDE * GROUP_COUNT < n <= GROUP_FRAME and (GROUP_FRAME - n) % GROUP_STRIDE == 0:
                ctors[(GROUP_FRAME - n) // GROUP_STRIDE] = pending
                pending = None
    return ctors


def parse_groups(stores, ctors, by_address):
    """The 28 group descriptors: {entries*, count, feature, name*, +0x20, +0x28}, 48 bytes each, on
    FUN_008630b4's stack starting at -0x598."""
    frame = stores["008630b4"]
    result = []
    for g in range(GROUP_COUNT):
        base = -GROUP_FRAME + GROUP_STRIDE * g
        field = lambda w: frame.get(base + w, (None, 0))[0]
        name = by_address.get(field(0x18), ("", ""))[1]
        result.append({"index": g, "name": name, "array": field(0), "count": field(8), "feature": field(0x10),
                       "param": field(0x28), "ctor": ctors.get(g)})
    return result


def parse_constructor(stores, ctor):
    """Entries a constructor writes on its stack: id (2 bytes) at O, name* O+8, table* O+0x10,
    handler O+0x18, arg O+0x20."""
    frame = stores[ctor.removeprefix("FUN_")]
    entries = []
    for offset in sorted(o for o, (_, size) in frame.items() if size == 2):
        entries.append({k: frame.get(offset + d, (None, 0))[0]
                        for k, d in (("id", 0), ("name", 8), ("table", 0x10), ("handler", 0x18), ("arg", 0x20))})
    return entries


def text_at(address, by_address):
    if not address:
        return "", ""
    if address not in by_address:
        return "", "not a known CFString"
    return by_address[address][1], ""


def handler_of(address, symbols):
    if not address:
        return "", ""
    return f"0x{address:08x}", symbols.get(address, f"FUN_{address:08x}")


def build(args):
    image = Image(args.binary)
    by_address, _ = load_cfstrings(args.cfstrings)
    symbols = load_functions(args.functions)
    remote = load_remote_commands(args.remote)
    stores = load_stores(args.stores)
    suppressed = read_suppressed(image)
    groups = parse_groups(stores, constructor_order(args.group_c), by_address)
    rows, problems = [], []
    for group in groups:
        if group["ctor"]:
            source, evidence = "constructor", group["ctor"]
            entries = parse_constructor(stores, group["ctor"])
            if len(entries) != group["count"]:
                problems.append(f"{group['name']}: constructor gives {len(entries)} entries, descriptor says {group['count']}")
            records = []
            for e in entries:
                name, note1 = text_at(e["name"], by_address)
                table, note2 = text_at(e["table"], by_address)
                hva, hsym = handler_of(e["handler"], symbols)
                records.append((e["id"], name, table, hva, hsym, hex(e["arg"]) if e["arg"] is not None else "",
                                "; ".join(x for x in (note1, note2) if x)))
        else:
            source, evidence = "static array", f"0x{group['array']:08x}"
            records = []
            for i in range(group["count"]):
                at = group["array"] + ENTRY_SIZE * i
                bef, nm, tb, hd, ar = (image.u16(at), image.u64(at + 8), image.u64(at + 0x10),
                                       image.u64(at + 0x18), image.u64(at + 0x20))
                if None in (bef, nm, tb, hd, ar):
                    problems.append(f"{group['name']}[{i}]: unreadable at 0x{at:08x}")
                    continue
                name, note1 = text_at(nm & PTR36, by_address)
                table, note2 = text_at(tb & PTR36, by_address)
                hva, hsym = handler_of(hd & PTR36, symbols)
                records.append((bef, name, table, hva, hsym, hex(ar), "; ".join(x for x in (note1, note2) if x)))
        for index, (cid, name, table, hva, hsym, arg, note) in enumerate(records):
            rows.append({
                "command_id": cid, "name": name, "table": table, "group": group["name"],
                "group_index": group["index"], "entry_index": index, "feature": hex(group["feature"]),
                "handler": hva, "handler_symbol": hsym, "arg": arg, "source": source, "evidence": evidence,
                "remote_assignments": " ".join(sorted(remote.get(cid, []))) if cid is not None else "",
                "remote_offered": remote_offered(group, cid, suppressed),
                "twin_of": "", "same_handler": "", "note": note,
            })
    add_relations(rows)
    return rows, problems, groups


def remote_offered(group, command_id, suppressed):
    """Whether Logic Remote's key-command list can contain the command (before the per-build feature check)."""
    if group["array"] == REMOTE_SKIPPED_GROUP_ARRAY:
        return "no: group skipped"
    return "no: suppressed" if command_id in suppressed else "yes"


def add_relations(rows):
    """same_handler: how many entries share the handler (the argument then selects the variant).
    twin_of: a Tool Menu entry and the 'Set <name>' entry that has the same tool number and the same
    name are the same operation reached two ways."""
    sharing = collections.Counter(r["handler"] for r in rows)
    for r in rows:
        r["same_handler"] = sharing[r["handler"]]
    setters = collections.defaultdict(list)
    for r in rows:
        if r["group"] != "Tool Menu" and r["name"].startswith("Set ") and r["name"].endswith(" Tool"):
            setters[(r["handler"], r["arg"])].append(r)
    for r in rows:
        if r["group"] != "Tool Menu":
            continue
        twins = [t for key, found in setters.items() if key[1] == r["arg"] for t in found
                 if t["name"] == f"Set {r['name']}"]
        if len(twins) == 1:
            r["twin_of"] = twins[0]["command_id"]


COLUMNS = ["command_id", "name", "table", "group", "group_index", "entry_index", "feature", "handler",
           "handler_symbol", "arg", "same_handler", "twin_of", "remote_offered", "remote_assignments", "source",
           "evidence", "note"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--binary", default=DEFAULT_BINARY)
    parser.add_argument("--group-c", default=str(RAW / "q-p7-table.c"))
    parser.add_argument("--stores", default=str(RAW / "p7-stackstores.tsv"))
    parser.add_argument("--cfstrings", default=str(RAW / "logic-cfstrings.tsv"))
    parser.add_argument("--functions", default=str(RAW / "Logic.arm64.functions.tsv"))
    parser.add_argument("--remote", default=str(ROOT / "Research" / "protocol" / "cs-assign-remote.tsv"))
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    rows, problems, groups = build(args)
    with open(args.out, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Registered Logic commands (12.3.1/6682, arm64), from static analysis only; see "
                     "Research/static-analysis/SA-COMMAND-CATALOG-001.md. Nothing was executed.\n")
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    ids = [r["command_id"] for r in rows if r["command_id"] is not None]
    duplicates = [i for i, n in collections.Counter(ids).items() if n > 1]
    print(f"entries {len(rows)}, distinct ids {len(set(ids))}, duplicate ids {len(duplicates)}, "
          f"max id {max(ids)}, out of table range {sum(1 for i in ids if i >= TABLE_SIZE)}", file=sys.stderr)
    for p in problems:
        print("PROBLEM:", p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
