#!/usr/bin/env python3
"""Rebuild an OSC control-surface plug-in's default-assignment table from
Ghidra's decompiled C (Logic Remote.bundle FUN_00000d7c, TouchOSC.bundle
FUN_00000d1c).

Entry layout inferred from _CSDefault: stride 0x40,
  +0x00 int kind (0 = end/none, 2 = group header)
  +0x04 int sub  -> AssignSerializedCore +0x3e
  +0x08 int param -> +0x40
  +0x10 char* OSC address (or group name)
  +0x18 flags
Constants written as DAT_x / _DAT_x copies are read from the thin binary.

  remote_table.py <decompiled.c> <thin-binary> [function, default FUN_00000d7c]
"""
import re
import struct
import sys

src, binpath = sys.argv[1], sys.argv[2]
func = sys.argv[3] if len(sys.argv) > 3 else "FUN_00000d7c"
data = open(binpath, "rb").read()
text = open(src, encoding="utf-8").read()
body = text[text.index(f"// ==== {func} "):]
body = body[:body.index("\n// ==== ", 10)]

model = None
mem = {}  # address -> (size, value-or-string)
for line in body.splitlines():
    m = re.match(r"\s+if \(param_1 == (\d+)\)", line) or re.match(r"\s+else if \(param_1 == (\d+)\)", line)
    if m:
        model = int(m.group(1))
    m = re.match(r"\s+(?:_?DAT|uRam0*)_?([0-9a-fA-F]+) = (.+);", line)
    if not m:
        continue
    addr, val = int(m.group(1), 16), m.group(2).strip()
    if val.startswith('"'):
        mem[addr] = ("str", val.strip('"'), model)
    elif re.fullmatch(r"_?DAT_([0-9a-f]+)", val):
        off = int(re.fullmatch(r"_?DAT_([0-9a-f]+)", val).group(1), 16)
        mem[addr] = ("u64", struct.unpack_from("<Q", data, off)[0], model)
    else:
        try:
            mem[addr] = ("int", int(val, 0), model)
        except ValueError:
            pass


def u32(a):
    for base, (t, v, _) in mem.items():
        if t in ("u64", "int") and base <= a < base + 8:
            return (v >> (8 * (a - base))) & 0xFFFFFFFF
    return 0


print("model\tkind\tsub\tparam\tflags\taddress")
for a in sorted(mem):
    t, v, model = mem[a]
    if t != "str":
        continue
    base = a - 0x10
    kind, sub, param, flags = u32(base), u32(base + 4), u32(base + 8), u32(base + 0x18)
    sub = sub - (1 << 32) if sub >= 1 << 31 else sub
    print(f"{model}\t{kind}\t{sub}\t{param}\t{flags & 0xff}\t{v}")
