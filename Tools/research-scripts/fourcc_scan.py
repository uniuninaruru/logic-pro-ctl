#!/usr/bin/env python3
"""Read-only Mach-O FourCC scan, including adjacent arm64 MOVZ/MOVK pairs.

Raw byte hits are observations, not evidence that a constant is an AppleEvent
handler. Absence of raw hits is not evidence of absence of a handler: compilers
often materialize OSType values in two instructions. The optional instruction
scan covers adjacent MOVZ then MOVK instructions only; it is not a disassembler
or a complete constant-propagation analysis.

Examples:
  python3 Tools/research-scripts/fourcc_scan.py --bundle /path/to/Logic.app
  python3 Tools/research-scripts/fourcc_scan.py --bundle /path/to/Logic.app \
      --all-native --mov-wide --output /tmp/fourcc-scan.json

JSON goes to stdout unless --output is supplied. Diagnostics go to stderr.
The app's executable is discovered through Info.plist, not its display name.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys


DEFAULT_CODES = ("aUeV", "Spt2", "sPmo", "sPkc")
THIN = {
    bytes.fromhex("cefaedfe"): ("<", False),
    bytes.fromhex("cffaedfe"): ("<", True),
    bytes.fromhex("feedface"): (">", False),
    bytes.fromhex("feedfacf"): (">", True),
}
FAT = {
    bytes.fromhex("cafebabe"): (">", False),
    bytes.fromhex("bebafeca"): ("<", False),
    bytes.fromhex("cafebabf"): (">", True),
    bytes.fromhex("bfbafeca"): ("<", True),
}
CPU_NAMES = {
    7: "i386", 12: "arm", 0x01000007: "x86_64", 0x0100000C: "arm64",
}


def fixed_name(value: bytes) -> str:
    return value.split(b"\0", 1)[0].decode("ascii", errors="replace")


def unpack_at(data: bytes, fmt: str, offset: int, limit: int):
    if offset < 0 or offset + struct.calcsize(fmt) > limit:
        raise ValueError(f"truncated Mach-O structure at 0x{offset:x}")
    return struct.unpack_from(fmt, data, offset)


def parse_thin(data: bytes, base: int, size: int) -> dict:
    if base < 0 or size < 4 or base + size > len(data):
        raise ValueError("invalid Mach-O slice range")
    magic = data[base:base + 4]
    if magic not in THIN:
        raise ValueError(f"unknown thin Mach-O magic at 0x{base:x}")
    endian, is64 = THIN[magic]
    limit = base + size
    header = unpack_at(data, endian + ("8I" if is64 else "7I"), base, limit)
    cpu, subtype, ncmds, sizeofcmds = header[1], header[2], header[4], header[5]
    command_start = base + (32 if is64 else 28)
    command_limit = command_start + sizeofcmds
    if command_limit > limit:
        raise ValueError("load commands extend outside Mach-O slice")
    arch = CPU_NAMES.get(cpu, f"cpu-0x{cpu:x}")
    if cpu == 0x0100000C and subtype & 0x00FFFFFF == 2:
        arch = "arm64e"
    result = {
        "architecture": arch, "cpu_type": cpu, "cpu_subtype": subtype,
        "endianness": "little" if endian == "<" else "big",
        "file_offset": base, "size_bytes": size, "segments": [],
    }
    cursor = command_start
    for _ in range(ncmds):
        cmd, cmdsize = unpack_at(data, endian + "II", cursor, command_limit)
        if cmdsize < 8 or cursor + cmdsize > command_limit:
            raise ValueError(f"invalid load command size at 0x{cursor:x}")
        if cmd in (1, 0x19):  # LC_SEGMENT / LC_SEGMENT_64
            seg64 = cmd == 0x19
            fmt = endian + ("II16sQQQQiiII" if seg64 else "II16sIIIIiiII")
            fields = unpack_at(data, fmt, cursor, cursor + cmdsize)
            _, _, name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, _ = fields
            if filesize and fileoff + filesize > size:
                raise ValueError(f"segment {fixed_name(name)} extends outside slice")
            seg = {
                "name": fixed_name(name), "virtual_address": vmaddr,
                "virtual_size": vmsize, "slice_file_offset": fileoff,
                "file_offset": base + fileoff, "file_size": filesize,
                "max_protection": maxprot, "initial_protection": initprot,
                "sections": [],
            }
            section_start = cursor + struct.calcsize(fmt)
            sectfmt = endian + ("16s16sQQ8I" if seg64 else "16s16s9I")
            for idx in range(nsects):
                section = unpack_at(data, sectfmt, section_start + idx * struct.calcsize(sectfmt), cursor + cmdsize)
                sectname, segname, addr, sectsize, sectoff = section[:5]
                flags = section[8]
                seg["sections"].append({
                    "name": fixed_name(sectname), "segment": fixed_name(segname),
                    "virtual_address": addr, "size_bytes": sectsize,
                    "slice_file_offset": sectoff, "file_offset": base + sectoff,
                    "flags": flags,
                    "instructions": bool(flags & (0x80000000 | 0x00000400)),
                })
            result["segments"].append(seg)
        cursor += cmdsize
    return result


def parse_macho(data: bytes) -> list[dict]:
    magic = data[:4]
    if magic in THIN:
        return [parse_thin(data, 0, len(data))]
    if magic not in FAT:
        raise ValueError("not a Mach-O file")
    endian, fat64 = FAT[magic]
    count = unpack_at(data, endian + "I", 4, len(data))[0]
    fmt = endian + ("IIQQII" if fat64 else "IIIII")
    entry_size = struct.calcsize(fmt)
    slices = []
    for idx in range(count):
        entry = unpack_at(data, fmt, 8 + idx * entry_size, len(data))
        slices.append(parse_thin(data, entry[2], entry[3]))
    return slices


def location(slices: list[dict], offset: int, length: int = 4) -> dict:
    result = {"file_offset": offset, "file_offset_hex": f"0x{offset:x}"}
    for sl in slices:
        if not sl["file_offset"] <= offset < sl["file_offset"] + sl["size_bytes"]:
            continue
        result.update({"architecture": sl["architecture"], "slice_file_offset": offset - sl["file_offset"]})
        for seg in sl["segments"]:
            start = seg["file_offset"]
            if start <= offset and offset + length <= start + seg["file_size"]:
                va = seg["virtual_address"] + offset - start
                result.update({"segment": seg["name"], "virtual_address": va, "virtual_address_hex": f"0x{va:x}"})
                for sec in seg["sections"]:
                    # Zero-fill sections have no file bytes even if offset is 0.
                    if sec["flags"] & 0xFF in (1, 0x0C, 0x12):
                        continue
                    if sec["file_offset"] <= offset and offset + length <= sec["file_offset"] + sec["size_bytes"]:
                        result["section"] = sec["name"]
                        break
                break
        break
    return result


def context(data: bytes, offset: int, length: int, radius: int) -> dict:
    start, end = max(0, offset - radius), min(len(data), offset + length + radius)
    raw = data[start:end]
    result = {
        "context_file_offset": start, "context_file_offset_hex": f"0x{start:x}",
        "context_hex": raw.hex(" "),
        "context_ascii": "".join(chr(b) if 32 <= b < 127 else "." for b in raw),
        "match_offset_in_context": offset - start, "match_length": length,
    }
    # Preserve a whole short printable C string when a raw match is merely a
    # substring (e.g. a Swift symbol name in __LINKEDIT).
    previous_null = data.rfind(b"\0", max(0, offset - 512), offset)
    string_start = previous_null + 1
    string_end = data.find(b"\0", offset + length, min(len(data), offset + 512))
    if string_end >= 0 and string_start <= offset and (previous_null >= 0 or offset < 512):
        string_bytes = data[string_start:string_end]
        if string_bytes and all(32 <= byte < 127 for byte in string_bytes):
            result["enclosing_nul_terminated_ascii"] = string_bytes.decode("ascii")
            result["enclosing_ascii_file_offset"] = string_start
    return result


def raw_hits(data: bytes, slices: list[dict], codes: tuple[str, ...], radius: int) -> list[dict]:
    result = []
    for code in codes:
        ascii_bytes = code.encode("ascii")
        for order, needle in (("big", ascii_bytes), ("little", ascii_bytes[::-1])):
            offset = 0
            while True:
                offset = data.find(needle, offset)
                if offset < 0:
                    break
                result.append({"fourcc": code, "encoding": f"raw-{order}-endian-u32", "matched_hex": needle.hex(" "), **location(slices, offset), **context(data, offset, 4, radius)})
                offset += 1
    return sorted(result, key=lambda hit: (hit["file_offset"], hit["fourcc"], hit["encoding"]))


def mov_wide(word: int):
    tag = word & 0x7F800000
    if tag not in (0x52800000, 0x72800000):
        return None
    width, shift = (64 if word & 0x80000000 else 32), ((word >> 21) & 3) * 16
    if width == 32 and shift > 16:
        return None  # Reserved encoding, not an instruction.
    return ("MOVZ" if tag == 0x52800000 else "MOVK", width, word & 31, (word >> 5) & 0xFFFF, shift)


def mov_pair_hits(data: bytes, slices: list[dict], codes: tuple[str, ...], radius: int) -> list[dict]:
    targets = {}
    for code in codes:
        for order in ("big", "little"):
            targets.setdefault(int.from_bytes(code.encode("ascii"), order), []).append((code, order))
    halves = {value & 0xFFFF for value in targets} | {value >> 16 for value in targets}
    result = []
    seen = set()
    for sl in slices:
        if sl["architecture"] not in ("arm64", "arm64e") or sl["endianness"] != "little":
            continue
        for seg in sl["segments"]:
            for sec in seg["sections"]:
                if not sec["instructions"] or sec["flags"] & 0xFF in (1, 0x0C, 0x12):
                    continue
                start, end = sec["file_offset"], sec["file_offset"] + sec["size_bytes"]
                if start % 4 or end > len(data):
                    raise ValueError("invalid arm64 instruction section range")
                for offset in range(start, end - 7, 4):
                    word = struct.unpack_from("<I", data, offset)[0]
                    if word & 0x7F800000 != 0x52800000 or (word >> 5) & 0xFFFF not in halves:
                        continue
                    first = mov_wide(word)
                    second_word = struct.unpack_from("<I", data, offset + 4)[0]
                    second = mov_wide(second_word)
                    if first is None or second is None or second[0] != "MOVK" or first[1:3] != second[1:3]:
                        continue
                    _, width, register, immediate, shift = first
                    value = immediate << shift
                    value = (value & ~(0xFFFF << second[4])) | (second[3] << second[4])
                    if value not in targets or offset in seen:
                        continue
                    seen.add(offset)
                    instructions = [
                        {"mnemonic": item[0], "register": f"{'x' if width == 64 else 'w'}{register}", "immediate": item[3], "immediate_hex": f"0x{item[3]:x}", "shift": item[4], "word_hex": f"0x{value_word:08x}"}
                        for item, value_word in ((first, word), (second, second_word))
                    ]
                    for code, order in targets[value]:
                        result.append({"fourcc": code, "encoding": f"arm64-adjacent-MOVZ-MOVK-{order}-endian-value", "constant": value, "constant_hex": f"0x{value:08x}", "instructions": instructions, **location(slices, offset, 8), **context(data, offset, 8, radius)})
    return sorted(result, key=lambda hit: (hit["file_offset"], hit["fourcc"], hit["encoding"]))


def primary_paths(bundle: Path, info: dict) -> list[Path]:
    return [bundle / "Contents/MacOS" / info["CFBundleExecutable"]] + [
        bundle / "Contents/Frameworks" / f"{name}.framework" / name
        for name in ("LogicAppFramework", "Logic", "MACore")
    ]


def native_paths(bundle: Path) -> list[Path]:
    found, seen = [], set()
    for path in sorted(bundle.rglob("*")):
        if not path.is_file() or path.resolve() in seen:
            continue
        with path.open("rb") as handle:
            magic = handle.read(4)
        if magic in THIN or magic in FAT:
            found.append(path)
            seen.add(path.resolve())
    return found


def scan_file(path: Path, codes: tuple[str, ...], radius: int, scan_mov: bool) -> dict:
    data = path.read_bytes()
    slices = parse_macho(data)
    return {
        "path": str(path), "resolved_path": str(path.resolve()),
        "size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "slices": slices, "raw_hits": raw_hits(data, slices, codes, radius),
        "mov_pair_hits": mov_pair_hits(data, slices, codes, radius) if scan_mov else [],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--all-native", action="store_true", help="scan all unique Mach-O files in the bundle")
    parser.add_argument("--mov-wide", action="store_true", help="also reconstruct adjacent arm64 MOVZ/MOVK pairs in instruction sections")
    parser.add_argument("--fourcc", action="append", help="four ASCII characters; repeat to override defaults")
    parser.add_argument("--context-bytes", type=int, default=16)
    parser.add_argument("--output", type=Path, help="write JSON here instead of stdout")
    args = parser.parse_args()
    codes = tuple(args.fourcc or DEFAULT_CODES)
    if args.context_bytes < 0:
        parser.error("--context-bytes must be nonnegative")
    for code in codes:
        if len(code) != 4 or not code.isascii():
            parser.error("--fourcc must contain exactly four ASCII characters")
    bundle = args.bundle.expanduser().resolve()
    plist_path = bundle / "Contents/Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    initial = primary_paths(bundle, info)
    paths = native_paths(bundle) if args.all_native else initial
    files, errors = [], []
    for path in paths:
        try:
            files.append(scan_file(path, codes, args.context_bytes, args.mov_wide))
        except (OSError, ValueError, struct.error) as exc:
            errors.append({"path": str(path), "error": str(exc)})
            print(f"{path}: {exc}", file=sys.stderr)
    result = {
        "schema_version": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "bundle": {"path": str(bundle), "bundle_identifier": info.get("CFBundleIdentifier"), "short_version": info.get("CFBundleShortVersionString"), "build_version": info.get("CFBundleVersion"), "executable_name": info.get("CFBundleExecutable"), "info_plist_sha256": hashlib.sha256(plist_path.read_bytes()).hexdigest()},
        "scope": "all-native" if args.all_native else "primary-four",
        "primary_paths": [str(path) for path in initial], "fourcc": list(codes),
        "methods": {"raw_bytes": "both endian byte orders, every file byte", "arm64_constants": "adjacent MOVZ then MOVK, same register and width, instruction sections only" if args.mov_wide else "disabled", "context_radius_bytes": args.context_bytes},
        "summary": {
            "files_scanned": len(files), "errors": len(errors),
            "raw_hit_count": sum(len(item["raw_hits"]) for item in files),
            "mov_pair_hit_count": sum(len(item["mov_pair_hits"]) for item in files),
            "by_fourcc": {code: {"raw": sum(hit["fourcc"] == code for item in files for hit in item["raw_hits"]), "arm64_mov_pair": sum(hit["fourcc"] == code for item in files for hit in item["mov_pair_hits"])} for code in codes},
        },
        "limitations": ["A raw byte hit can be unrelated code or data; no handler semantics are inferred.", "The instruction scan covers adjacent MOVZ/MOVK pairs only; absence of a hit does not exclude other constant synthesis.", "Addresses are unslid Mach-O virtual addresses, not runtime process addresses.", "No AppleEvents were sent and no app files were modified."],
        "files": files, "errors": errors,
    }
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
        print(f"Saved {args.output}; {len(files)} files, {result['summary']['raw_hit_count']} raw hits, {result['summary']['mov_pair_hit_count']} MOV pairs", file=sys.stderr)
    else:
        sys.stdout.write(encoded)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
