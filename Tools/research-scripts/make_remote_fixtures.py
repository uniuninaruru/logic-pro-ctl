#!/usr/bin/env python3
"""Builds SYNTHETIC Logic Remote frame fixtures into Tests/Fixtures/logic-remote/.

These are NOT captures from Logic. They are built from the wire format read in
Research/static-analysis/SA-REMOTE-FRAME-001.md (MAPeerRouter.processReceivedData:,
the serializer at MACore 0x000f98c8, NSData maUncompressedData / maCompressedData…):

    frame      = format_byte payload
    format_byte: bit 7 = payload is a MAZP container; low 7 bits: 1 plist, 4 JSON, other = keyed archive (2)
    MAZP       = "MAZP" u16be header_len(=10) u32be uncompressed_len zlib_stream

Replace or add real captures when PLAN-05 produces them; keep the synthetic ones
labelled as such. Deterministic: no timestamps, fixed compression level 9.

    python3 Tools/research-scripts/make_remote_fixtures.py
"""
import json
import plistlib
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "Tests" / "Fixtures" / "logic-remote"
OUT.mkdir(parents=True, exist_ok=True)


def mazp(payload: bytes, level: int = 9) -> bytes:
    return b"MAZP" + struct.pack(">HI", 10, len(payload)) + zlib.compress(payload, level)


def frame(fmt: int, payload: bytes, compressed: bool = False) -> bytes:
    return bytes([fmt | (0x80 if compressed else 0)]) + (mazp(payload) if compressed else payload)


def keyed_archive(root) -> bytes:
    """A minimal NSKeyedArchiver archive (what NSKeyedArchiver writes for Foundation
    containers) for dict / list / str / int / float / bool / bytes, so the Swift test
    can check it against the real NSKeyedUnarchiver."""
    objects = ["$null"]
    class_index = {}

    def cls(name: str) -> int:
        # class descriptors are shared and are plain dictionaries, not archived values
        if name not in class_index:
            objects.append({"$classname": name, "$classes": [name, "NSObject"]})
            class_index[name] = len(objects) - 1
        return class_index[name]

    def add(value) -> int:
        objects.append(None)
        index = len(objects) - 1
        if isinstance(value, dict):
            keys = [add(k) for k in value]
            vals = [add(v) for v in value.values()]
            objects[index] = {"NS.keys": [plistlib.UID(k) for k in keys],
                              "NS.objects": [plistlib.UID(v) for v in vals],
                              "$class": plistlib.UID(cls("NSDictionary"))}
        elif isinstance(value, list):
            items = [add(v) for v in value]
            objects[index] = {"NS.objects": [plistlib.UID(v) for v in items],
                              "$class": plistlib.UID(cls("NSArray"))}
        elif isinstance(value, bytes):
            objects[index] = {"NS.data": value, "$class": plistlib.UID(cls("NSData"))}
        elif isinstance(value, (str, int, float, bool)):
            objects[index] = value
        else:
            raise TypeError(type(value))
        return index

    root_index = add(root)
    return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver",
                           "$top": {"root": plistlib.UID(root_index)}, "$objects": objects},
                          fmt=plistlib.FMT_BINARY)


def write(name: str, data: bytes, note: str):
    (OUT / name).write_bytes(data)
    print(f"{name:42s} {len(data):6d} bytes  {note}")


# 1. plist, single message with a number argument (format 1)
write("plist_single.bin", frame(1, plistlib.dumps({"/transport/headerState": 5}, fmt=plistlib.FMT_BINARY)),
      "format 1, {address: int}")

# 2. JSON, single message (format 4)
write("json_single.bin", frame(4, json.dumps({"/keyCommand/actionNum": 3}, separators=(",", ":")).encode()),
      "format 4, {address: int}")

# 3. JSON with no-argument style message and strings
write("json_two_messages.bin",
      frame(4, json.dumps({"/protocolVersion": 10, "/hostLocaleIdentifier": "ja_JP"}, separators=(",", ":"), sort_keys=True).encode()),
      "format 4, two addresses in one dictionary")

# 4. ordered batch: an ARRAY of dictionaries, order matters (plist)
write("plist_ordered_batch.bin",
      frame(1, plistlib.dumps([{"/a/first": 1}, {"/a/second": 2}, {"/a/third": 3}], fmt=plistlib.FMT_BINARY)),
      "format 1, array of dictionaries (ordered)")

# 5. keyed archive with NUMERIC dictionary keys (the /gtFaderData shape: {g: {instID: {m,s,vL}}, t: {...}})
gt = {"/gtFaderData": {"g": {7: {"vL": 12441, "m": 2, "s": 0}, 12: {"vL": 0, "m": 3, "s": 1}}, "t": {1: {"r": 1}}}}
write("archive_numeric_keys.bin", frame(2, keyed_archive(gt)), "format 2, NSNumber dictionary keys")

# 6. large JSON payload, compressed (bit 7) in a MAZP container
big = {"/ati": {"tracks": [{"n": f"Track {i:03d}", "tn": i, "t": 0, "c": {"nc": [i % 255, 40, 90]}} for i in range(60)]}}
big_json = json.dumps(big, separators=(",", ":")).encode()
assert len(big_json) > 1024
write("json_compressed_mazp.bin", frame(4, big_json, compressed=True), f"format 4 | 0x80, MAZP, {len(big_json)} bytes uncompressed")

# 7. compressed plist
big_plist = plistlib.dumps({"/ati": big["/ati"]}, fmt=plistlib.FMT_BINARY)
write("plist_compressed_mazp.bin", frame(1, big_plist, compressed=True), f"format 1 | 0x80, MAZP, {len(big_plist)} bytes uncompressed")

# 8. bit 7 set but NO MAZP header: Logic's maUncompressedData returns the data unchanged
write("compressed_flag_without_header.bin",
      bytes([0x84]) + json.dumps({"/x": 1}, separators=(",", ":")).encode() + b" " * 4,
      "format 4 | 0x80 but payload is plain (passthrough)")

# 9. unknown format byte 0x03 (Logic would hand it to the keyed unarchiver)
write("unknown_format_3.bin", bytes([3]) + b"\x00\x01\x02", "format 3 (unknown)")

print("done ->", OUT)
