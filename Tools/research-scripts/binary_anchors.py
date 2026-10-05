#!/usr/bin/env python3
"""Check a table of evidence anchors against a Mach-O image, without Ghidra.

A static-analysis note says things like "this `cmp` tests 0x44" or "this slot holds
_BgTrackInfoTypeKey". The Ghidra listing is the first witness for such a claim. This script is a
second, independent one: it reads the claimed bytes straight out of the image file and compares
the text printed by Apple's tools. Nothing is executed and the image is only read.

Anchor table (tab separated, `#` starts a comment; see Research/protocol/logic-remote-trackcolor-anchors.tsv):

    id  kind  address  bytes  text  claim

    insn    4 bytes at the address, in memory order, and the llvm-objdump text of the instruction
    data    the bytes at the address
    bind    the symbol `dyld_info -fixups` reports for the pointer slot at the address
    selref  the selector string reached through the slot's rebase target (an Objective-C selref)

The header must carry `Image: <name>  sha256=<64 hex>`; a different image is refused, because the
addresses belong to exactly one build.

  binary_anchors.py check TABLE [--image PATH] [--require-tools]

Exit status: 0 all anchors hold, 1 a mismatch, 2 the image is missing or is not the recorded one.
"""
import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional, Tuple

KINDS = ("insn", "data", "bind", "selref")
DEFAULT_IMAGE = Path(os.environ.get("LOGICCTL_LOGIC_ARM64",
                                    Path.home() / "GhidraProjects" / "logicctl" / "bin" / "Logic.arm64"))
LC_SEGMENT_64 = 0x19
MH_MAGIC_64 = 0xFEEDFACF
CLUSTER_GAP = 0x400  # one llvm-objdump run per group of nearby anchors


class Anchor(NamedTuple):
    id: str
    kind: str
    address: int
    data: bytes
    text: str
    claim: str


class ToolMissing(RuntimeError):
    pass


def parse_anchors(path) -> Tuple[Optional[str], List[Anchor]]:
    """Return (image sha256 from the header, rows). Raise ValueError for a malformed table."""
    sha = None
    rows: List[Anchor] = []
    seen = set()
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("#"):
            match = re.search(r"Image:.*sha256=([0-9a-fA-F]{64})", line)
            if match:
                sha = match.group(1).lower()
            continue
        if not line.strip():
            continue
        cells = line.split("\t")
        if len(cells) != 6:
            raise ValueError(f"line {number}: expected 6 columns, got {len(cells)}")
        ident, kind, address, hexbytes, text, claim = cells
        if ident in seen:
            raise ValueError(f"line {number}: duplicate id {ident}")
        seen.add(ident)
        if kind not in KINDS:
            raise ValueError(f"line {number}: unknown kind {kind!r}")
        if not re.fullmatch(r"0x[0-9a-fA-F]{1,16}", address):
            raise ValueError(f"line {number}: bad address {address!r}")
        if not re.fullmatch(r"([0-9a-fA-F]{2})*", hexbytes):
            raise ValueError(f"line {number}: bad bytes {hexbytes!r}")
        data = bytes.fromhex(hexbytes)
        if kind == "insn" and len(data) != 4:
            raise ValueError(f"line {number}: an instruction is 4 bytes")
        if kind == "data" and not data:
            raise ValueError(f"line {number}: data needs bytes")
        if kind in ("insn", "bind", "selref") and not text:
            raise ValueError(f"line {number}: {kind} needs text")
        if not claim:
            raise ValueError(f"line {number}: every anchor needs a claim")
        rows.append(Anchor(ident, kind, int(address, 16), data, text, claim))
    return sha, rows


class Image:
    """The segments of a thin 64-bit Mach-O file, enough to read bytes by virtual address."""

    def __init__(self, content: bytes):
        if len(content) < 32 or struct.unpack_from("<I", content, 0)[0] != MH_MAGIC_64:
            raise ValueError("not a thin 64-bit little-endian Mach-O image")
        self.content = content
        ncmds = struct.unpack_from("<I", content, 16)[0]
        offset = 32
        self.segments = []
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<2I", content, offset)
            if cmd == LC_SEGMENT_64:
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<4Q", content, offset + 24)
                self.segments.append((vmaddr, vmsize, fileoff, filesize))
            offset += size

    def read(self, address: int, count: int) -> bytes:
        for vmaddr, vmsize, fileoff, filesize in self.segments:
            if vmaddr <= address and address + count <= vmaddr + min(vmsize, filesize):
                start = fileoff + address - vmaddr
                return self.content[start:start + count]
        raise ValueError(f"address {address:#x}+{count} is not backed by the file")

    def cstring(self, address: int, limit: int = 256) -> str:
        out = bytearray()
        while len(out) < limit:
            byte = self.read(address + len(out), 1)
            if byte == b"\0":
                break
            out += byte
        return out.decode("utf-8", "replace")


def normalize_objdump_text(text: str) -> str:
    """`ldr x1, [x1, #0x4d0]  ; =1232` -> `ldr x1, [x1, #0x4d0]`; symbols, comments and spacing removed."""
    text = re.sub(r"<[^>]*>", "", text).split(";")[0]
    text = re.sub(r"\s+", " ", text.replace("\t", " ")).strip()
    return text.replace(", ", ",").replace(",", ", ")


def find_tool(name: str) -> List[str]:
    if shutil.which("xcrun"):
        found = subprocess.run(["xcrun", "--find", name], capture_output=True, text=True, check=False)
        if found.returncode == 0 and found.stdout.strip():
            return [found.stdout.strip()]
    path = shutil.which(name)
    if path:
        return [path]
    raise ToolMissing(f"{name} is not available")


def disassemble(image_path, low: int, high: int) -> Dict[int, Tuple[bytes, str]]:
    """{address: (4 bytes in memory order, normalized text)} for [low, high)."""
    command = find_tool("llvm-objdump") + ["-d", f"--start-address={low:#x}", f"--stop-address={high:#x}", str(image_path)]
    output = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120).stdout
    result = {}
    for line in output.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(.*)$", line)
        if match:
            word = int(match.group(2), 16)
            result[int(match.group(1), 16)] = (struct.pack("<I", word), normalize_objdump_text(match.group(3)))
    return result


def read_fixups(image_path) -> Tuple[Dict[int, str], Dict[int, int]]:
    """({slot: imported symbol}, {slot: rebase target}) from `dyld_info -fixups`."""
    command = find_tool("dyld_info") + ["-fixups", str(image_path)]
    output = subprocess.run(command, capture_output=True, text=True, check=True, timeout=300).stdout
    binds: Dict[int, str] = {}
    rebases: Dict[int, int] = {}
    for line in output.splitlines():
        match = re.search(r"(0x[0-9A-Fa-f]{8,16})\s+(bind|rebase)\s+(\S+)", line)
        if not match:
            continue
        slot = int(match.group(1), 16)
        if match.group(2) == "bind":
            binds[slot] = match.group(3)
        else:
            rebases[slot] = int(match.group(3), 16)
    return binds, rebases


def clusters(addresses: List[int]) -> List[Tuple[int, int]]:
    ranges: List[Tuple[int, int]] = []
    for address in sorted(set(addresses)):
        if ranges and address - ranges[-1][1] <= CLUSTER_GAP:
            ranges[-1] = (ranges[-1][0], address + 4)
        else:
            ranges.append((address, address + 4))
    return ranges


def check(anchors: List[Anchor], image: Image, image_path=None, tools: bool = True) -> Tuple[List[str], List[str]]:
    """Return (mismatches, notes). Without tools only the bytes are compared."""
    errors: List[str] = []
    notes: List[str] = []
    disassembly: Dict[int, Tuple[bytes, str]] = {}
    binds: Dict[int, str] = {}
    rebases: Dict[int, int] = {}
    if tools:
        try:
            insn = [a.address for a in anchors if a.kind == "insn"]
            for low, high in clusters(insn):
                disassembly.update(disassemble(image_path, low, high))
            if any(a.kind in ("bind", "selref") for a in anchors):
                binds, rebases = read_fixups(image_path)
        except ToolMissing as missing:
            notes.append(f"{missing}: instruction text, binds and selectors were not checked")
            tools = False
    for anchor in anchors:
        where = f"{anchor.id} ({anchor.address:#x})"
        try:
            if anchor.kind in ("insn", "data"):
                actual = image.read(anchor.address, len(anchor.data))
                if actual != anchor.data:
                    errors.append(f"{where}: bytes are {actual.hex()}, the table says {anchor.data.hex()}")
                    continue
            if anchor.kind == "insn" and tools:
                found = disassembly.get(anchor.address)
                if found is None:
                    errors.append(f"{where}: llvm-objdump printed nothing at this address")
                elif found[0] != anchor.data:
                    errors.append(f"{where}: llvm-objdump reads {found[0].hex()}, the table says {anchor.data.hex()}")
                elif found[1] != anchor.text:
                    errors.append(f"{where}: llvm-objdump prints '{found[1]}', the table says '{anchor.text}'")
            elif anchor.kind == "bind" and tools:
                if binds.get(anchor.address) != anchor.text:
                    errors.append(f"{where}: dyld_info binds '{binds.get(anchor.address)}', the table says '{anchor.text}'")
            elif anchor.kind == "selref" and tools:
                target = rebases.get(anchor.address)
                actual = image.cstring(target) if target is not None else None
                if actual != anchor.text:
                    errors.append(f"{where}: the selector is '{actual}', the table says '{anchor.text}'")
        except ValueError as problem:
            errors.append(f"{where}: {problem}")
    return errors, notes


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=["check"])
    parser.add_argument("table")
    parser.add_argument("--image", default=str(DEFAULT_IMAGE))
    parser.add_argument("--require-tools", action="store_true",
                        help="fail instead of skipping the text checks when llvm-objdump or dyld_info is missing")
    options = parser.parse_args(argv)
    try:
        sha, anchors = parse_anchors(options.table)
    except ValueError as problem:
        print(f"table: {problem}", file=sys.stderr)
        return 1
    if sha is None:
        print("table: the header has no 'Image: ... sha256=' line", file=sys.stderr)
        return 1
    path = Path(options.image)
    if not path.is_file():
        print(f"image not found: {path} (set --image or LOGICCTL_LOGIC_ARM64)", file=sys.stderr)
        return 2
    content = path.read_bytes()
    actual = hashlib.sha256(content).hexdigest()
    if actual != sha:
        print(f"image sha256 {actual} is not the one the table was made for ({sha})", file=sys.stderr)
        return 2
    errors, notes = check(anchors, Image(content), path)
    for note in notes:
        print(f"note: {note}", file=sys.stderr)
    if notes and options.require_tools:
        return 2
    for error in errors:
        print(f"MISMATCH {error}", file=sys.stderr)
    print(f"{len(anchors) - len(errors)} of {len(anchors)} anchors hold" + ("" if not errors else f"; {len(errors)} do not"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
