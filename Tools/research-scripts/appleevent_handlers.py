#!/usr/bin/env python3
"""Read-only AppleEvent registration inventory for an explicitly supplied app.

Requires macOS /usr/bin/{nm,otool}; uses only Python's standard library.
Writes research evidence, never sends AppleEvents or changes the target app.

Example:
  python3 Tools/research-scripts/appleevent_handlers.py \
    '/Applications/Logic Pro Creator Studio.app' \
    --out Research/raw/2026-10-01-appleevent-registration

Optional --reuse-disassembly FILE avoids another full Logic disassembly.
The four known addresses in --handler/--table/--objc-stub are version-specific
investigation anchors, not a stable protocol API or a general decompiler.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import plistlib
import re
import struct
import subprocess


APPLE_IMPORT = re.compile(r"^_(?:AE[A-Z]\w*|.*AppleEvent.*|.*NSScript.*|NSAppleScript)$")
ADDRESS_LINE = re.compile(r"^([0-9a-f]{16})\s+(\w[^\t]*)\t?(.*)$")


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def bundle_binary(bundle: pathlib.Path) -> pathlib.Path | None:
    for plist in (bundle / "Contents/Info.plist", bundle / "Resources/Info.plist",
                  bundle / "Versions/Current/Resources/Info.plist", bundle / "Info.plist"):
        if not plist.exists():
            continue
        with plist.open("rb") as stream:
            executable = plistlib.load(stream).get("CFBundleExecutable")
        if executable:
            for candidate in (bundle / "Contents/MacOS" / executable,
                              bundle / executable, bundle / "Versions/Current" / executable):
                if candidate.is_file():
                    return candidate.resolve()
    candidate = bundle / bundle.stem
    return candidate.resolve() if candidate.is_file() else None


def inventory(app: pathlib.Path) -> list[dict]:
    paths = [bundle_binary(app)]
    paths += [bundle_binary(p) for p in (app / "Contents/Frameworks").glob("*.framework")]
    paths += list((app / "Contents/Frameworks").glob("*.dylib"))
    paths = sorted({p for p in paths if p is not None})

    def inspect(path: pathlib.Path) -> dict:
        process = subprocess.run(["/usr/bin/nm", "-arch", "arm64", "-u", str(path)],
                                 capture_output=True, text=True)
        imports = [line.strip() for line in process.stdout.splitlines()
                   if APPLE_IMPORT.search(line.strip())]
        return {"binary": str(path), "nm_status": process.returncode,
                "appleevent_imports": imports}

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(inspect, paths))


class MachO:
    """Minimal segment reader, including a fat Mach-O's arm64 slice."""

    def __init__(self, path: pathlib.Path):
        self.data = path.read_bytes()
        magic = struct.unpack_from(">I", self.data)[0]
        self.slice = 0
        if magic in (0xCAFEBABE, 0xCAFEBABF):
            count = struct.unpack_from(">I", self.data, 4)[0]
            stride = 20 if magic == 0xCAFEBABE else 32
            for index in range(count):
                offset = 8 + index * stride
                cpu = struct.unpack_from(">I", self.data, offset)[0]
                if cpu == 0x0100000C:
                    fmt = ">I" if stride == 20 else ">Q"
                    self.slice = struct.unpack_from(fmt, self.data, offset + 8)[0]
                    break
            else:
                raise ValueError("No arm64 slice")
        if struct.unpack_from("<I", self.data, self.slice)[0] != 0xFEEDFACF:
            raise ValueError("Expected little-endian 64-bit Mach-O")
        ncmds = struct.unpack_from("<I", self.data, self.slice + 16)[0]
        cursor = self.slice + 32
        self.segments = []
        self.uuid = None
        for _ in range(ncmds):
            command, size = struct.unpack_from("<II", self.data, cursor)
            if command == 0x19:
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", self.data, cursor + 24)
                self.segments.append((vmaddr, vmsize, self.slice + fileoff, filesize))
            elif command == 0x1B:
                self.uuid = self.data[cursor + 8:cursor + 24].hex()
            cursor += size

    def at(self, address: int, size: int) -> bytes:
        for vmaddr, _, offset, filesize in self.segments:
            delta = address - vmaddr
            if 0 <= delta and delta + size <= filesize:
                return self.data[offset + delta:offset + delta + size]
        raise ValueError(f"Unmapped/non-file-backed address {address:#x}")


def fourcc(value: int | None) -> str | None:
    if value is None:
        return None
    data = (value & 0xFFFFFFFF).to_bytes(4, "big")
    return data.decode("ascii") if all(32 <= byte < 127 for byte in data) else None


def register_constants(lines: list[str]) -> dict[str, int]:
    """Small local recognizer; only tracks obvious immediate register writes.

    This is not control-flow/data-flow analysis. A preceding unrelated function
    call clears volatile registers. Unrecognized writes invalidate that register.
    Inspect the emitted assembly before treating any result as proven.
    """
    values: dict[str, int] = {}
    for line in lines:
        match = ADDRESS_LINE.match(line)
        if not match:
            continue
        mnemonic, operands = match.group(2), match.group(3)
        operands = operands.split(";")[0].strip()
        parts = [p.strip() for p in operands.split(",")]
        if mnemonic in ("bl", "blr"):
            values = {reg: val for reg, val in values.items() if int(reg[1:]) >= 19}
            continue
        if not parts or not re.fullmatch(r"[wx]\d+", parts[0]):
            continue
        dest = "x" + parts[0][1:]
        old = values.pop(dest, None)
        if mnemonic in ("mov", "movz") and len(parts) == 2:
            if parts[1].startswith("#"):
                values[dest] = int(parts[1][1:], 0)
            elif parts[1] in ("xzr", "wzr"):
                values[dest] = 0
            elif "x" + parts[1][1:] in values:
                values[dest] = values["x" + parts[1][1:]]
        elif mnemonic == "movk" and old is not None:
            shift = int(parts[2].split("#")[1], 0) if len(parts) > 2 else 0
            immediate = int(parts[1][1:], 0)
            values[dest] = (old & ~(0xFFFF << shift)) | (immediate << shift)
        elif mnemonic == "adrp":
            comment = re.search(r";\s*(0x[0-9a-f]+)", match.group(3))
            if comment:
                values[dest] = int(comment.group(1), 16)
        elif mnemonic == "add" and len(parts) == 3 and parts[2].startswith("#"):
            source = "x" + parts[1][1:]
            base = old if source == dest else values.get(source)
            if base is not None:
                values[dest] = base + int(parts[2][1:], 0)
    return values


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--reuse-disassembly", type=pathlib.Path)
    parser.add_argument("--handler", type=lambda x: int(x, 0), default=0x590E30)
    parser.add_argument("--handler-size", type=lambda x: int(x, 0), default=3600)
    parser.add_argument("--table", type=lambda x: int(x, 0), default=0x1CBEB70)
    parser.add_argument("--objc-stub", type=lambda x: int(x, 0), default=0x1B8ED20)
    args = parser.parse_args()
    app = args.app.resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = args.out or pathlib.Path("Research/raw") / f"{stamp}-appleevent-registration"
    out.mkdir(parents=True, exist_ok=True)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    scans = inventory(app)
    (out / "import-inventory.json").write_text(json.dumps(scans, indent=2) + "\n")
    logic = bundle_binary(app / "Contents/Frameworks/Logic.framework")
    if logic is None:
        raise SystemExit("Supplied app has no Logic.framework executable")
    macho = MachO(logic)
    indirect = run("/usr/bin/otool", "-arch", "arm64", "-Iv", str(logic))
    (out / "Logic.arm64.indirect-symbols.txt").write_text(indirect)
    stubs = [int(m.group(1), 16) for m in re.finditer(
        r"^(0x[0-9a-f]+)\s+\d+\s+_AEInstallEventHandler$", indirect, re.M)]
    disassembly = args.reuse_disassembly or out / "Logic.arm64.disassembly.txt"
    if args.reuse_disassembly is None:
        with disassembly.open("w") as stream:
            subprocess.run(["/usr/bin/otool", "-arch", "arm64", "-tvV", str(logic)],
                           check=True, stdout=stream)
    registrations = []
    objc_calls = []
    handler_lines = []
    contexts = []
    window: list[str] = []
    with disassembly.open() as stream:
        for line in stream:
            match = ADDRESS_LINE.match(line)
            if not match:
                continue
            address = int(match.group(1), 16)
            if args.handler <= address < args.handler + args.handler_size:
                handler_lines.append(line)
            if "symbol stub for: _AEInstallEventHandler" in line:
                values = register_constants(window)
                registrations.append({"call_address": hex(address),
                                      "event_class": fourcc(values.get("x0")),
                                      "event_id": fourcc(values.get("x1")),
                                      "register_values": {k: hex(v) for k, v in values.items()
                                                          if int(k[1:]) <= 4}})
                contexts += [f"\n# AEInstallEventHandler call {address:#x}\n", *window, line]
            if match.group(2) in ("bl", "b") and re.match(rf"0x{args.objc_stub:x}\b", match.group(3)):
                values = register_constants(window)
                objc_calls.append({"call_address": hex(address),
                                   "event_class": fourcc(values.get("x4")),
                                   "event_id": fourcc(values.get("x5")),
                                   "note": "Confirm selector identity separately from ObjC metadata"})
                contexts += [f"\n# known ObjC handler-registration stub call {address:#x}\n", *window, line]
            window = (window + [line])[-32:]
    (out / "registration-contexts.asm").write_text("".join(contexts))
    (out / "spot-handler.asm").write_text("".join(handler_lines))
    table_bytes = macho.at(args.table, 30)
    table = struct.unpack("<15h", table_bytes)
    report = {
        "generated_utc": stamp, "app": str(app), "bundle_id": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
        "binary": str(logic), "arch": "arm64", "uuid_hex": macho.uuid,
        "sha256": hashlib.sha256(macho.data).hexdigest(), "inventory_binary_count": len(scans),
        "AEInstallEventHandler_indirect_symbol_addresses": [hex(s) for s in stubs],
        "direct_registration_calls": registrations, "known_objc_stub_calls": objc_calls,
        "spot_handler_anchor": hex(args.handler), "spot_handler_size": args.handler_size,
        "positive_sPkc_table": {"address": hex(args.table), "little_endian_bytes": table_bytes.hex(),
                                "signed_int16_values": list(table), "accepted_indices": list(range(1, 15))},
        "limitations": ["Inventory scope: app main executable, top-level bundled frameworks and dylibs",
                        "Only arm64 direct calls are inventoried; indirect registration is not ruled out",
                        "ObjC stub/handler/table anchors are specific to the examined build",
                        "Register recognizer is local, conservative, and requires assembly review",
                        "No runtime registration status or behavior is established by this script"],
    }
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"out": str(out.resolve()), "direct_registrations": registrations,
                      "objc_registrations": objc_calls, "positive_sPkc_table": list(table)}, indent=2))


if __name__ == "__main__":
    main()
