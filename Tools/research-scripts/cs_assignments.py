#!/usr/bin/env python3
"""Read-only, bounded inspection of *copied* Logic CS snapshots.

The observed format is MROF / little-endian length / FCSS, followed by flat,
unpadded FourCC + little-endian length + payload records. Only chunk boundaries
are parsed: an RDAF substring inside a payload is never treated as a record.
RDAF is a raw record type, not proof of an assignment. The small optional
candidate decoder recognizes the mode-2 CC families observed in EXP-CS-001;
target fingerprints are static hypotheses, never current target/value proof.

Examples:
  python3 Tools/research-scripts/cs_assignments.py list copied-snapshot.bin
  python3 Tools/research-scripts/cs_assignments.py diff before.bin after.bin
  python3 Tools/research-scripts/cs_assignments.py diff before.bin after.bin \
      --allow-length-mismatch

JSON goes to stdout; errors go to stderr. There are no write/restore operations
and no default preferences path. Names, identifiers and raw payloads are omitted.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import sys


MAX_FILE_BYTES = 16 * 1024 * 1024
MAX_PAYLOAD_BYTES = 1024 * 1024
MAX_RECORDS = 10_000
EVIDENCE = "Research/static-analysis/SA-CS-PREFS-001.en.md"
LIMITATIONS = [
    "Only the observed flat, unpadded MROF/FCSS record layout is supported; no nested records are inferred.",
    "RDAF is a raw type; neither every RDAF nor a shape match is a confirmed assignment.",
    "Candidate field roles are hypotheses; class, parameter, target and value semantics are unproved.",
    "Target fingerprints use the 12.4/6707 static list-6 mapping; hashes/ordinals do not establish an active target or verify a value.",
    "Variable fields require bounded canonical lengths, unique tags and an exact terminator; this is stricter than Logic's inspected scan.",
    "EXP-CS-001 observed Logic 12.4 (6707); its command-number comparison used a 12.3.1 catalog, not a cross-version guarantee.",
    "Diff uses a payload-hash multiset with duplicate counts; a changed payload appears as a removal and addition.",
    "Names, identifiers and raw payloads are omitted; the tool reads explicit copied snapshots and writes nothing.",
]


class SnapshotError(ValueError):
    """A snapshot is outside the supported structure or configured bounds."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class Record:
    offset: int
    type_bytes: bytes
    payload: bytes

    @property
    def length(self) -> int:
        return len(self.payload)

    @property
    def end(self) -> int:
        return self.offset + 8 + self.length

    @property
    def payload_sha256(self) -> str:
        return digest(self.payload)

    @property
    def identity(self) -> tuple[bytes, int, str]:
        return self.type_bytes, self.length, self.payload_sha256


@dataclass(frozen=True)
class Snapshot:
    size_bytes: int
    sha256: str
    declared_body_length: int
    records: tuple[Record, ...]
    warnings: tuple[str, ...] = ()

    @property
    def snapshot_valid(self) -> bool:
        return not self.warnings


def parse_snapshot(
    data: bytes, *, allow_length_mismatch: bool = False,
    max_file_bytes: int = MAX_FILE_BYTES,
    max_payload_bytes: int = MAX_PAYLOAD_BYTES,
    max_records: int = MAX_RECORDS,
) -> Snapshot:
    """Parse bytes without recursion, tag searches or writes.

    Strict mode requires the declared MROF length to equal len(data)-8. The
    explicit forensic mode uses the actual file boundary, reports the mismatch,
    and still rejects every truncated/oversized chunk. It never repairs bytes.
    """
    if max_file_bytes < 12 or max_payload_bytes < 0 or max_records < 0:
        raise SnapshotError("invalid parser bounds")
    if len(data) > max_file_bytes:
        raise SnapshotError(f"file exceeds {max_file_bytes}-byte bound")
    if len(data) < 12:
        raise SnapshotError("truncated MROF/FCSS header (need 12 bytes)")
    if data[:4] != b"MROF":
        raise SnapshotError("expected MROF signature at offset 0")
    if data[8:12] != b"FCSS":
        raise SnapshotError("unsupported MROF form type (expected FCSS)")
    declared = struct.unpack_from("<I", data, 4)[0]
    warnings = ()
    if declared != len(data) - 8:
        warning = f"MROF length mismatch: declared {declared}, actual {len(data) - 8}"
        if not allow_length_mismatch:
            raise SnapshotError(warning)
        warnings = (warning + "; explicit forensic mode used actual EOF; snapshot is invalid",)

    records = []
    offset = 12
    while offset < len(data):
        if len(records) >= max_records:
            raise SnapshotError(f"record count exceeds {max_records}-record bound")
        if len(data) - offset < 8:
            raise SnapshotError(f"truncated record header at offset {offset}")
        size = struct.unpack_from("<I", data, offset + 4)[0]
        if size > max_payload_bytes:
            raise SnapshotError(f"record payload at offset {offset} exceeds {max_payload_bytes}-byte bound")
        end = offset + 8 + size
        if end > len(data):
            raise SnapshotError(f"truncated record payload at offset {offset}: declared {size}, available {len(data) - offset - 8}")
        records.append(Record(offset, data[offset:offset + 4], data[offset + 8:end]))
        offset = end
    return Snapshot(len(data), digest(data), declared, tuple(records), warnings)


def load_snapshot(path: str | Path, **options) -> Snapshot:
    """Read an explicit regular copied file, with a bounded read.

    Reject the live preferences path, symlinks resolving there, and hard links
    to it. A copied backup with the original basename is permitted elsewhere.
    """
    copied = Path(path).expanduser().resolve()
    live = (Path.home() / "Library/Preferences/com.apple.logic.pro.cs").resolve()
    if copied == live or (live.exists() and copied.exists() and os.path.samefile(copied, live)):
        raise SnapshotError("live preferences are not accepted; supply an explicit copied snapshot")
    max_file_bytes = options.get("max_file_bytes", MAX_FILE_BYTES)
    if not isinstance(max_file_bytes, int) or max_file_bytes < 12:
        raise SnapshotError("invalid file-size bound")
    # Nonblocking open avoids hanging on a FIFO/device supplied as a snapshot.
    # Resolving a copied path does not prove that it remained a regular file.
    descriptor = os.open(copied, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as handle:
        before = os.fstat(handle.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise SnapshotError("snapshot must be a regular file")
        if before.st_size > max_file_bytes:
            raise SnapshotError(f"file exceeds {max_file_bytes}-byte bound")
        data = handle.read(max_file_bytes + 1)
        after = os.fstat(handle.fileno())
    if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
        raise SnapshotError("snapshot changed while being read; copy it again")
    if len(data) != before.st_size:
        raise SnapshotError("snapshot read length differs from file size")
    return parse_snapshot(data, **options)


def _bounded_variable_fields(payload: bytes, start: int) -> list[tuple[int, int, int]] | None:
    """Return (tag, content offset, length) under conservative inventory bounds.

    The native helper uses MSB-first base-128 groups (ASSIGN-FIELDS-007).
    Unlike that scan, this rejects duplicates, noncanonical lengths, overflow,
    truncation and trailing bytes; it never emulates native malformed inputs.
    """
    cursor = start
    fields = []
    seen = set()
    while cursor < len(payload):
        tag = payload[cursor]
        cursor += 1
        if tag == 0:
            return fields if cursor == len(payload) else None
        if tag in seen or len(fields) >= 64:
            return None
        seen.add(tag)
        length = 0
        for group in range(5):
            if cursor == len(payload):
                return None
            byte = payload[cursor]
            cursor += 1
            if group == 0 and byte == 0x80:  # An unnecessary leading zero group.
                return None
            length = (length << 7) | (byte & 0x7f)
            if length > 0xffffffff:
                return None
            if byte < 0x80:
                break
        else:
            return None
        if length > len(payload) - cursor:
            return None
        fields.append((tag, cursor, length))
        cursor += length
    return None


def observed_candidates(record: Record) -> dict | None:
    """Return hypotheses only for the narrowly observed mode-2 CC shapes.

    The fixed prefix and variable tag sequence must match; the UTF-8/NUL name
    and every field must be bounded. No strings, IDs or UUID bytes are returned.
    """
    p = record.payload
    if record.type_bytes != b"RDAF" or len(p) < 73:
        return None
    family = struct.unpack_from("<I", p, 2)[0]
    flags = p[1] & 0x7f
    if p[0] != 0 or not ((family == 9 and flags == 1) or (family == 5 and flags in (3, 17, 25))):
        return None
    if p[10:15] != b"\0" * 5 or p[15] != 2 or p[16:19] != b"\0\0\x7f":
        return None
    if p[19] not in (2, 4) or p[40] != 0x80:
        return None
    fields = _bounded_variable_fields(p, 46)
    if fields is None or [f[0] for f in fields] not in ([1, 3, 16], [1, 3, 6, 16]):
        return None
    _, message_start, message_length = fields[0]
    if message_length != 3:
        return None
    message = p[message_start:message_start + message_length]
    if not (0xb0 <= message[0] <= 0xbf and message[1] < 0x80 and (message[2] < 0x80 or message[2] in (0xf4, 0xf5))):
        return None
    _, name_start, name_length = fields[1]
    if not name_length or fields[-1][2] != 16:
        return None
    name_end = name_start + name_length
    if p[name_end - 1] != 0 or b"\0" in p[name_start:name_end - 1]:
        return None
    try:
        p[name_start:name_end - 1].decode("utf-8")
    except UnicodeDecodeError:
        return None
    raw = {
        "u32le_payload_2": family,
        "u32le_payload_6": struct.unpack_from("<I", p, 6)[0],
        # Retain raw probes; the static 12.4 mapping is not runtime confirmation.
        "u16le_payload_6": struct.unpack_from("<H", p, 6)[0],
        "u32le_payload_8": struct.unpack_from("<I", p, 8)[0],
        "byte_payload_15": p[15],
        "u32le_payload_42": struct.unpack_from("<I", p, 42)[0],
    }
    result = {
        "status": "hypothesis",
        "shape": f"observed_mode2_cc_family_{family}",
        "evidence": EVIDENCE,
        "raw_fields": raw,
        "message_candidate": {
            "payload_offset": message_start, "length": 3, "hex": message.hex(),
            "contains_f4_f5": any(value in (0xf4, 0xf5) for value in message),
        },
        "name_field_length": name_length,
        "variable_field_lengths": [{"tag": tag, "length": length} for tag, _, length in fields],
        "semantics_confirmed": False,
    }
    if family == 9:
        result["command_int_candidate"] = {
            "payload_offset": 6, "encoding": "little-endian-u32",
            "value": raw["u32le_payload_6"],
        }
    elif len(fields) == 4 and fields[2][2] == 32 and (raw["u32le_payload_8"] & 0xffffc000) == 0x4000:
        _, identity_start, _ = fields[2]
        identity = p[identity_start:identity_start + 32]
        result["stored_plugin_target_candidate"] = {
            "status": "hypothesis",
            "evidence": "Research/notes/assignment-fields-007.en.md; Research/notes/assignment-identity-audit-008.en.md",
            "static_version_scope": "Logic 12.4 / 6707",
            "payload_offset": identity_start, "field_tag": 6, "length": 32,
            "descriptor_sha256": digest(identity[:12]),
            "ordinal_raw": struct.unpack_from("<I", identity, 12)[0],
            "instance_token_sha256": digest(identity[16:]),
            "selector_raw": raw["u16le_payload_6"],
            "parameter_code_raw": raw["u32le_payload_8"],
            "active_target_confirmed": False, "value_verified": False,
        }
    return result


def record_json(record: Record) -> dict:
    tag = record.type_bytes
    type_label = tag.decode("ascii") if all(32 <= byte < 127 for byte in tag) else "hex:" + tag.hex()
    result = {
        "type": type_label,
        "span": [record.offset, record.end],  # End exclusive, including the eight-byte header.
        "payload_span": [record.offset + 8, record.end],
        "length": record.length,
        "payload_sha256": record.payload_sha256,
    }
    candidates = observed_candidates(record)
    if candidates is not None:
        result["candidates"] = candidates
    return result


def selected_records(snapshot: Snapshot, *, all_records: bool = False) -> tuple[Record, ...]:
    return tuple(record for record in snapshot.records if all_records or record.type_bytes == b"RDAF")


def snapshot_metadata(snapshot: Snapshot) -> dict:
    return {
        "size_bytes": snapshot.size_bytes, "sha256": snapshot.sha256,
        "declared_body_length": snapshot.declared_body_length,
        "actual_body_length": snapshot.size_bytes - 8,
        "snapshot_valid": snapshot.snapshot_valid, "warnings": list(snapshot.warnings),
        "record_count": len(snapshot.records),
        "rdaf_count": sum(record.type_bytes == b"RDAF" for record in snapshot.records),
    }


def list_snapshot(snapshot: Snapshot, *, all_records: bool = False) -> dict:
    records = selected_records(snapshot, all_records=all_records)
    return {
        "schema_version": 1, "operation": "list",
        "scope": "all_flat_records" if all_records else "raw_RDAF_records",
        "snapshot": snapshot_metadata(snapshot), "record_count": len(records),
        "candidate_count": sum(observed_candidates(record) is not None for record in records),
        "span_convention": "zero-based byte offsets; end exclusive",
        "records": [record_json(record) for record in records],
        "limitations": LIMITATIONS,
    }


def diff_snapshots(before: Snapshot, after: Snapshot, *, all_records: bool = False) -> dict:
    """Compare hash multisets, preserving duplicate multiplicities and spans."""
    old = selected_records(before, all_records=all_records)
    new = selected_records(after, all_records=all_records)
    old_count = Counter(record.identity for record in old)
    new_count = Counter(record.identity for record in new)
    added_budget, removed_budget = new_count - old_count, old_count - new_count
    added, removed = [], []
    for record in new:
        if added_budget[record.identity]:
            added.append(record_json(record))
            added_budget[record.identity] -= 1
    for record in old:
        if removed_budget[record.identity]:
            removed.append(record_json(record))
            removed_budget[record.identity] -= 1
    return {
        "schema_version": 1, "operation": "diff",
        "scope": "all_flat_records" if all_records else "raw_RDAF_records",
        "before": snapshot_metadata(before), "after": snapshot_metadata(after),
        "snapshot_valid": before.snapshot_valid and after.snapshot_valid,
        "added_count": len(added), "removed_count": len(removed),
        "unchanged_count": sum((old_count & new_count).values()),
        "same_record_multiset": old_count == new_count,
        "record_sequence_equal": [record.identity for record in old] == [record.identity for record in new],
        "span_convention": "zero-based byte offsets; end exclusive",
        "added": added, "removed": removed, "limitations": LIMITATIONS,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="list structurally parsed raw records, with hashes")
    listing.add_argument("snapshot", type=Path, help="explicit copied snapshot path")
    comparison = commands.add_parser("diff", help="compare raw record hash multisets")
    comparison.add_argument("before", type=Path, help="explicit copied before snapshot")
    comparison.add_argument("after", type=Path, help="explicit copied after snapshot")
    for command in (listing, comparison):
        command.add_argument("--all-records", action="store_true", help="include non-RDAF flat records")
        command.add_argument("--allow-length-mismatch", action="store_true", help="forensic only: use actual EOF, retain invalid snapshot warning; never repair")
    args = parser.parse_args(argv)
    try:
        options = {"allow_length_mismatch": args.allow_length_mismatch}
        if args.command == "list":
            result = list_snapshot(load_snapshot(args.snapshot, **options), all_records=args.all_records)
        else:
            result = diff_snapshots(load_snapshot(args.before, **options), load_snapshot(args.after, **options), all_records=args.all_records)
    except (OSError, ValueError) as error:
        print(f"cs_assignments: {error}", file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, indent=2, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
