#!/usr/bin/env python3
"""Read-only MACore x86_64 AppleEvent reconnaissance.

Extracts a copy into an experiment directory, never into the application bundle.
Saves the complete tool outputs, bounded search contexts, and a JSON manifest.
No event is sent and no process is attached.
"""

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import struct
import subprocess


FOURCC = {code: int.from_bytes(code.encode("ascii"), "big")
          for code in ("aUeV", "Spt2", "sPmo", "sPkc")}
API = (
    "NSAppleEventManager", "NSAppleEventDescriptor",
    "setEventHandler:andSelector:forEventClass:andEventID:",
    "AEInstallEventHandler", "AERemoveEventHandler", "AEGetParamPtr",
    "AEGetParamDesc", "AEGetAttributePtr", "AESend", "AESendMessage",
    "AppleEvent", "appleEvent",
    "executeHandlerWithName:andArguments:error:",
    "executeHandlerWithName:inScriptAtURL:withArguments:error:",
    "initWithEventClass:eventID:targetDescriptor:returnID:transactionID:",
    "setParamDescriptor:forKeyword:",
)


def run(argv, output):
    with output.open("w") as stream:
        subprocess.run(argv, stdout=stream, stderr=subprocess.STDOUT, check=True)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def matches(lines, pattern, context=4):
    found = []
    for index, line in enumerate(lines):
        if pattern.search(line):
            found.append({"line": index + 1, "text": line,
                          "context": lines[max(0, index-context):index+context+1]})
    return found


def objc_selector_references(data, disassembly):
    """Decode selrefs from this thin Mach-O rather than trust otool comments.

    Recent dyld chained pointers keep traversal metadata in the pointer's high
    bits; otool -tvV on this installation mislabels objc_msgSend comments.
    Only supported 64-bit rebase formats are decoded; binds are skipped.
    """
    if struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected a little-endian 64-bit Mach-O")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    cursor = 32
    sections = []
    segments = []
    fixups_offset = None
    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", data, cursor)
        if command == 0x19:  # LC_SEGMENT_64
            segment_name = data[cursor+8:cursor+24].split(b"\0")[0].decode()
            address, vm_size, file_offset, file_size = struct.unpack_from("<QQQQ", data, cursor+24)
            segments.append({"name": segment_name, "address": address, "vm_size": vm_size,
                             "file_offset": file_offset, "file_size": file_size})
            nsects = struct.unpack_from("<I", data, cursor+64)[0]
            for index in range(nsects):
                start = cursor + 72 + index * 80
                name = data[start:start+16].split(b"\0")[0].decode()
                section_address, section_size, section_offset = struct.unpack_from("<QQI", data, start+32)
                sections.append({"name": name, "segment": segment_name,
                                 "address": section_address, "size": section_size,
                                 "file_offset": section_offset})
        elif command == 0x80000034:  # LC_DYLD_CHAINED_FIXUPS
            fixups_offset = struct.unpack_from("<I", data, cursor+8)[0]
        cursor += size
    pointer_formats = {}
    if fixups_offset is not None:
        starts_offset = struct.unpack_from("<I", data, fixups_offset+4)[0]
        starts = fixups_offset + starts_offset
        count = struct.unpack_from("<I", data, starts)[0]
        for index in range(count):
            offset = struct.unpack_from("<I", data, starts+4+4*index)[0]
            if offset:
                pointer_formats[segments[index]["name"]] = struct.unpack_from("<H", data, starts+offset+6)[0]
    selrefs = next(x for x in sections if x["name"] == "__objc_selrefs")
    pointer_format = pointer_formats.get(selrefs["segment"])
    if pointer_format not in (None, 2, 6):
        raise ValueError(f"Unsupported chained pointer format: {pointer_format}")
    image_base = min(s["address"] for s in segments if s["file_size"])

    def offset_for(address):
        for segment in segments:
            if segment["address"] <= address < segment["address"] + segment["file_size"]:
                return segment["file_offset"] + address - segment["address"]
        raise ValueError(f"Address is not file-backed: 0x{address:x}")

    instructions = []
    for line_number, line in enumerate(disassembly, 1):
        match = re.match(r"([0-9a-f]{16})\s+(.*)", line)
        if match:
            instructions.append((int(match[1], 16), line_number, match[2]))
    references = []
    for index, (address, line_number, text) in enumerate(instructions[:-1]):
        match = re.match(r"movq\s+(-?0x[0-9a-f]+)\(%rip\), (%[a-z0-9]+)\b", text)
        if not match:
            continue
        target = instructions[index+1][0] + int(match[1], 16)
        if not (selrefs["address"] <= target < selrefs["address"] + selrefs["size"]):
            continue
        encoded = struct.unpack_from("<Q", data, offset_for(target))[0]
        if pointer_format in (2, 6):
            if encoded >> 63:  # bind, not rebase
                continue
            pointer = encoded & ((1 << 36) - 1)
            if pointer_format == 2:
                pointer |= ((encoded >> 36) & 0xFF) << 56
            else:
                pointer += image_base
        else:
            pointer = encoded
        start = offset_for(pointer)
        selector = data[start:data.index(b"\0", start)].decode("utf-8")
        if any(term in selector for term in API):
            references.append({"instruction_address": f"0x{address:x}", "line": line_number,
                               "selref_address": f"0x{target:x}", "selector_address": f"0x{pointer:x}",
                               "selector": selector, "encoded_pointer": f"0x{encoded:x}",
                               "target_register": match[2],
                               "context": disassembly[max(0, line_number-5):line_number+4]})
    return {"pointer_formats": pointer_formats, "references": references}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=pathlib.Path,
                        help="Installed application path, discovered by the caller")
    parser.add_argument("--out", type=pathlib.Path,
                        help="New directory; defaults to Research/raw/<UTC timestamp>-macore")
    args = parser.parse_args()
    source = args.app / "Contents/Frameworks/MACore.framework/Versions/A/MACore"
    if not source.is_file():
        parser.error(f"Framework executable is missing: {source}")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    output = args.out or pathlib.Path("Research/raw") / f"{stamp}-macore"
    output.mkdir(parents=True, exist_ok=False)
    thin = output / "MACore.x86_64"
    commands = [
        (["lipo", str(source), "-thin", "x86_64", "-output", str(thin)], "extract.txt"),
        (["file", str(source), str(thin)], "file.txt"),
        (["lipo", "-info", str(thin)], "architectures.txt"),
        (["otool", "-tvV", str(thin)], "disassembly.txt"),
        (["otool", "-l", str(thin)], "load-commands.txt"),
        (["otool", "-ov", str(thin)], "objc-metadata.txt"),
        (["nm", "-m", str(thin)], "symbols.txt"),
        (["strings", "-a", str(thin)], "strings.txt"),
    ]
    for argv, name in commands:
        run(argv, output / name)
    data = thin.read_bytes()
    byte_hits = []
    for code, value in FOURCC.items():
        for endian in ("big", "little"):
            needle = value.to_bytes(4, endian)
            offset = 0
            while (offset := data.find(needle, offset)) != -1:
                byte_hits.append({"code": code, "value": f"0x{value:08x}",
                                  "endian": endian, "file_offset": f"0x{offset:x}",
                                  "context_hex": data[max(0, offset-16):offset+20].hex(" ")})
                offset += 1
    disassembly = (output / "disassembly.txt").read_text(errors="replace").splitlines()
    numeric_hits = {}
    for code, value in FOURCC.items():
        pattern = re.compile(rf"(?i)(?:\b0x0*{value:x}\b|\b{value}\b|{re.escape(code)})")
        numeric_hits[code] = matches(disassembly, pattern)
    api_pattern = re.compile("|".join(re.escape(x) for x in API))
    api_hits = {}
    for name in ("disassembly.txt", "symbols.txt", "strings.txt", "objc-metadata.txt"):
        lines = (output / name).read_text(errors="replace").splitlines()
        api_hits[name] = matches(lines, api_pattern)
    dispatch_pattern = re.compile(r"(?i)(befehl|command|dispatch)")
    symbols = (output / "symbols.txt").read_text(errors="replace").splitlines()
    command_hits = matches(symbols, dispatch_pattern, context=0)
    selector_references = objc_selector_references(data, disassembly)
    result = {
        "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": str(source.resolve()), "source_sha256": sha256(source),
        "thin": str(thin.resolve()), "thin_sha256": sha256(thin),
        "commands": [{"argv": argv, "output": name} for argv, name in commands],
        "fourcc": {k: f"0x{v:08x}" for k, v in FOURCC.items()},
        "byte_hits": byte_hits, "disassembly_fourcc_hits": numeric_hits,
        "appleevent_api_hits": api_hits, "command_symbol_hits": command_hits,
        "decoded_objc_selector_references": selector_references,
        "limitations": [
            "Absence in these static searches does not prove no interface exists.",
            "A split immediate, computed constant, other image, or indirect registration may evade these searches.",
            "Finding a symbol or selector alone does not establish registration or an exposed IPC interface.",
        ],
    }
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"raw_directory": str(output.resolve()),
                      "byte_hits": len(byte_hits),
                      "disassembly_fourcc_hits": {k: len(v) for k, v in numeric_hits.items()},
                      "api_hits": {k: len(v) for k, v in api_hits.items()},
                      "decoded_selector_references": len(selector_references["references"]),
                      "command_symbol_hits": len(command_hits)}, indent=2))


if __name__ == "__main__":
    main()
