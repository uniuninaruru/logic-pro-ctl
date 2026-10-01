#!/usr/bin/env python3
"""Rebuild DDESCR_LC::GetSwitchInfo's table from Ghidra's decompiled C.

Each entry is 0x18 bytes: name (char*), then fields Ghidra shows as
DAT_x+8 (u32), DAT_x+0xc (8 bytes, often a copied constant DAT_y). Constants
are read from the thinned binary (vmaddr == file offset for __TEXT here).

  switch_table.py <decompiled.c> <thin-binary>
"""
import re
import struct
import sys

src, binpath = sys.argv[1], sys.argv[2]
data = open(binpath, "rb").read()
text = open(src, encoding="utf-8").read()
body = text[text.index("// ==== DDESCR_LC::GetSwitchInfo "):]
body = body[:body.index("\n// ==== ", 10)]

entries = {}
for addr, val in re.findall(r"DAT_([0-9a-f]+) = ([^;]+);", body):
    entries[int(addr, 16)] = val.strip()
names = {a: v for a, v in entries.items() if v.startswith('"')}


def const(v):
    m = re.fullmatch(r"DAT_([0-9a-f]+)", v)
    if m:
        off = int(m.group(1), 16)  # __TEXT: vmaddr == file offset
        return struct.unpack_from("<Q", data, off)[0]
    return int(v, 0)


print("index\tname\tw8_hex\tb8\tb9\tkind_c\tparam_10")
for i, base in enumerate(sorted(names)):
    w8 = const(entries.get(base + 8, "0"))
    q = const(entries.get(base + 0xC, "0"))
    kind, param = q & 0xFFFFFFFF, q >> 32
    print(f"{i}\t{names[base].strip(chr(34))}\t{w8:#x}\t{w8 & 0xff}\t{(w8 >> 8) & 0xff}\t{kind}\t{param}")
