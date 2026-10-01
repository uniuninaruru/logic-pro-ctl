#!/usr/bin/env python3
"""Resolve MACore's exported `Bg*` string constants to their wire values.

Logic Remote messages use these constants as dictionary keys / addresses
(MAPeerRouter, LgLogicRemoteController). The symbols are exported as
`S _Bg…`; each points (through a chained fixup, low 36 bits) to a
CFString `{isa, flags, chars*, length}` in MACore's data.

  macore_wire_keys.py [path-to-MACore]  > keys.tsv      (name<TAB>wire value)

Read-only: works on a thinned arm64 copy in a temporary file. Symbols whose
target is not a constant CFString (flags 0x7c8) are skipped.
"""
import re
import struct
import subprocess
import sys
import tempfile

DEFAULT = ("/Applications/Logic Pro Creator Studio.app/Contents/Frameworks/"
           "MACore.framework/Versions/A/MACore")


def main(path):
    with tempfile.NamedTemporaryFile() as tmp:
        subprocess.run(["lipo", "-thin", "arm64", path, "-output", tmp.name], check=True)
        data = open(tmp.name, "rb").read()
        otool = subprocess.run(["otool", "-l", tmp.name], capture_output=True, text=True).stdout
    segs, cur = [], {}
    for line in otool.split("\n"):
        t = line.split()
        if len(t) > 1 and t[0] in ("segname", "vmaddr", "fileoff", "filesize"):
            cur[t[0]] = t[1]
        if t and t[0] == "filesize":
            segs.append((int(cur["vmaddr"], 16), int(cur["fileoff"]), int(cur["filesize"])))
            cur = {}

    def off(vm):
        for v, f, s in segs:
            if v <= vm < v + s:
                return f + vm - v
        return None

    symbols = subprocess.run(["nm", "-gU", "-arch", "arm64", path], capture_output=True, text=True).stdout
    rows = []
    for line in symbols.split("\n"):
        m = re.match(r"([0-9a-f]+) S _(Bg\w+)$", line)
        if not m:
            continue
        o = off(int(m.group(1), 16))
        target = struct.unpack_from("<Q", data, o)[0] & 0xFFFFFFFFF
        so = off(target)
        # Only genuine constant CFStrings (flags 0x7c8 on this build); other Bg*
        # symbols are unrelated data.
        if so is None or struct.unpack_from("<Q", data, so + 8)[0] != 0x7C8:
            continue
        chars = struct.unpack_from("<Q", data, so + 16)[0] & 0xFFFFFFFFF
        length = struct.unpack_from("<Q", data, so + 24)[0]
        co = off(chars)
        rows.append((m.group(2), data[co:co + length].decode("utf-8", "replace") if co is not None else "?"))
    for name, value in sorted(rows):
        print(f"{name}\t{value}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
