"""Synthetic-only tests for the read-only CS copied-snapshot parser."""

import contextlib
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Tools/research-scripts"))
import cs_assignments as cs


def chunk(tag, payload):
    return tag + struct.pack("<I", len(payload)) + payload


def snapshot(*records):
    body = b"FCSS" + b"".join(records)
    return b"MROF" + struct.pack("<I", len(body)) + body


def cc_payload(*, family=9, message=b"\xb0\x19\xf5", name=b"Example\0", extra=b"", flags=None):
    prefix = bytearray(53)
    prefix[1] = (0x81 if family == 9 else 0x19) if flags is None else flags
    struct.pack_into("<I", prefix, 2, family)
    struct.pack_into("<I", prefix, 6, 748 if family == 9 else 0x71000)
    prefix[15:20] = b"\x02\0\0\x7f\x02"
    prefix[40] = 0x80
    prefix[46:48] = b"\x01\x03"
    prefix[48:51] = message
    prefix[51:53] = bytes((3, len(name)))
    return bytes(prefix) + name + extra + b"\x10\x10" + b"I" * 16 + b"\0"


class ParseTests(unittest.TestCase):
    def test_flat_records_and_end_exclusive_spans(self):
        data = snapshot(chunk(b"DATA", b"abc"), chunk(b"RDAF", b"opaque"))
        parsed = cs.parse_snapshot(data)
        self.assertTrue(parsed.snapshot_valid)
        self.assertEqual([record.offset for record in parsed.records], [12, 23])
        row = cs.list_snapshot(parsed)["records"][0]
        self.assertEqual(row["span"], [23, 37])
        self.assertEqual(row["payload_span"], [31, 37])
        self.assertEqual(row["length"], 6)
        self.assertEqual(row["payload_sha256"], cs.digest(b"opaque"))
        self.assertNotIn("candidates", row)

    def test_substrings_are_not_nested_records(self):
        inner = chunk(b"RDAF", cc_payload())
        parsed = cs.parse_snapshot(snapshot(chunk(b"DATA", inner), chunk(b"RDAF", inner)))
        self.assertEqual(len(parsed.records), 2)
        self.assertEqual(cs.list_snapshot(parsed)["record_count"], 1)
        self.assertEqual(cs.list_snapshot(parsed)["candidate_count"], 0)

    def test_truncated_headers(self):
        for data in (b"", b"MROF", b"MROF\0\0\0\0", snapshot() + b"RDAF"):
            with self.subTest(data=data), self.assertRaises(cs.SnapshotError):
                cs.parse_snapshot(data, allow_length_mismatch=True)

    def test_truncated_payload_and_oversized_declared_chunk(self):
        for size in (4, 0xffffffff):
            data = snapshot(b"RDAF" + struct.pack("<I", size) + b"abc")
            with self.subTest(size=size), self.assertRaises(cs.SnapshotError):
                cs.parse_snapshot(data)

    def test_bounds_file_payload_and_record_count(self):
        data = snapshot(chunk(b"RDAF", b"abcd"), chunk(b"RDAF", b"efgh"))
        for bounds in ({"max_file_bytes": 12}, {"max_payload_bytes": 3}, {"max_records": 1}):
            with self.subTest(bounds=bounds), self.assertRaises(cs.SnapshotError):
                cs.parse_snapshot(data, **bounds)

    def test_bad_form_magic_and_length(self):
        data = snapshot(chunk(b"RDAF", b"abc"))
        for corrupted in (b"FORM" + data[4:], data[:8] + b"OTHER" + data[13:], data[:4] + struct.pack("<I", 4) + data[8:]):
            with self.subTest(data=corrupted), self.assertRaises(cs.SnapshotError):
                cs.parse_snapshot(corrupted)

    def test_forensic_mismatch_is_explicitly_invalid(self):
        data = snapshot(chunk(b"RDAF", b"abc"))
        mismatch = data[:4] + struct.pack("<I", 4) + data[8:]
        parsed = cs.parse_snapshot(mismatch, allow_length_mismatch=True)
        self.assertFalse(parsed.snapshot_valid)
        self.assertIn("declared 4", parsed.warnings[0])
        self.assertEqual(len(parsed.records), 1)
        self.assertEqual(cs.digest(mismatch), parsed.sha256)
        output = cs.diff_snapshots(cs.parse_snapshot(data), parsed)
        self.assertFalse(output["snapshot_valid"])
        self.assertEqual((output["added_count"], output["removed_count"]), (0, 0))
        # Forensic mode never forgives a malformed chunk.
        with self.assertRaises(cs.SnapshotError):
            cs.parse_snapshot(mismatch[:-1], allow_length_mismatch=True)

    def test_zero_length_unknown_record_still_advances(self):
        parsed = cs.parse_snapshot(snapshot(chunk(b"RDAF", b""), chunk(b"NEXT", b"")))
        self.assertEqual(len(parsed.records), 2)
        self.assertIsNone(cs.observed_candidates(parsed.records[0]))


class CandidateTests(unittest.TestCase):
    def candidate(self, payload):
        return cs.observed_candidates(cs.Record(12, b"RDAF", payload))

    def test_bounded_key_shape_emits_candidate_not_semantics(self):
        output = self.candidate(cc_payload())
        self.assertEqual(output["command_int_candidate"]["value"], 748)
        self.assertEqual(output["command_int_candidate"]["payload_offset"], 6)
        self.assertEqual(output["message_candidate"]["hex"], "b019f5")
        self.assertFalse(output["semantics_confirmed"])
        serialized = json.dumps(output)
        self.assertNotIn("Example", serialized)
        self.assertNotIn("IIIIIIII", serialized)

    def test_family5_u32_is_raw_not_command(self):
        output = self.candidate(cc_payload(family=5, extra=b"\x06\x03xyz"))
        self.assertEqual(output["raw_fields"]["u32le_payload_6"], 0x71000)
        self.assertNotIn("command_int_candidate", output)

    def test_f4_and_literal_value_shapes(self):
        for message in (b"\xb0\x17\xf4", b"\xb0\x14\x40"):
            with self.subTest(message=message):
                output = self.candidate(cc_payload(family=5, message=message))
                self.assertEqual(output["message_candidate"]["hex"], message.hex())

    def test_unknown_family_and_short_payload_do_not_emit_candidate(self):
        self.assertIsNone(self.candidate(cc_payload(family=7)))
        self.assertIsNone(self.candidate(b"RDAF\0\0\0\0"))
        self.assertIsNone(cs.observed_candidates(cs.Record(12, b"DATA", cc_payload())))

    def test_malformed_field_lengths_utf8_suffix_and_markers(self):
        cases = []
        for offset, value in ((47, 250), (52, 255), (51, 2), (15, 1), (50, 0xf6), (48, 0x90)):
            corrupted = bytearray(cc_payload())
            corrupted[offset] = value
            cases.append(bytes(corrupted))
        cases.extend([cc_payload(name=b"bad\xff\0"), cc_payload(name=b"noNUL"), cc_payload(name=b"x\0y\0"), cc_payload()[:-1], cc_payload() + b"x", cc_payload(extra=b"\x06\xffx")])
        for payload in cases:
            with self.subTest(payload_length=len(payload)):
                self.assertIsNone(self.candidate(payload))


class DiffTests(unittest.TestCase):
    def test_single_added_and_removed_record(self):
        old = cs.parse_snapshot(snapshot(chunk(b"RDAF", b"one")))
        new = cs.parse_snapshot(snapshot(chunk(b"RDAF", b"one"), chunk(b"RDAF", b"two")))
        forward, reverse = cs.diff_snapshots(old, new), cs.diff_snapshots(new, old)
        self.assertEqual((forward["added_count"], forward["removed_count"], forward["unchanged_count"]), (1, 0, 1))
        self.assertEqual((reverse["added_count"], reverse["removed_count"]), (0, 1))

    def test_duplicate_multiplicity_is_not_collapsed(self):
        one = chunk(b"RDAF", b"same")
        before = cs.parse_snapshot(snapshot(one, one, chunk(b"RDAF", b"other")))
        after = cs.parse_snapshot(snapshot(one, chunk(b"RDAF", b"other")))
        output = cs.diff_snapshots(before, after)
        self.assertEqual((output["added_count"], output["removed_count"], output["unchanged_count"]), (0, 1, 2))

    def test_reordering_changes_sequence_not_multiset(self):
        a, b = chunk(b"RDAF", b"a"), chunk(b"RDAF", b"b")
        output = cs.diff_snapshots(cs.parse_snapshot(snapshot(a, b, a)), cs.parse_snapshot(snapshot(a, a, b)))
        self.assertTrue(output["same_record_multiset"])
        self.assertFalse(output["record_sequence_equal"])
        self.assertEqual((output["added_count"], output["removed_count"]), (0, 0))

    def test_changed_payload_is_raw_remove_plus_add(self):
        output = cs.diff_snapshots(cs.parse_snapshot(snapshot(chunk(b"RDAF", b"old"))), cs.parse_snapshot(snapshot(chunk(b"RDAF", b"new"))))
        self.assertEqual((output["added_count"], output["removed_count"]), (1, 1))
        self.assertEqual(output["unchanged_count"], 0)


class FileAndCLITests(unittest.TestCase):
    def test_non_regular_file_is_rejected_without_blocking(self):
        with tempfile.TemporaryDirectory() as temporary:
            pipe = Path(temporary) / "snapshot.fifo"
            os.mkfifo(pipe)
            with self.assertRaises(cs.SnapshotError):
                cs.load_snapshot(pipe)

    def test_explicit_copy_required_live_and_aliases_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            live = home / "Library/Preferences/com.apple.logic.pro.cs"
            live.parent.mkdir(parents=True)
            live.write_bytes(snapshot())
            alias = home / "alias.bin"
            alias.symlink_to(live)
            hardlink = home / "hardlink.bin"
            hardlink.hardlink_to(live)
            with patch.object(cs.Path, "home", return_value=home):
                for path in (live, alias, hardlink):
                    with self.subTest(path=path), self.assertRaises(cs.SnapshotError):
                        cs.load_snapshot(path)
                copy = home / "copy/com.apple.logic.pro.cs"
                copy.parent.mkdir()
                copy.write_bytes(live.read_bytes())
                self.assertTrue(cs.load_snapshot(copy).snapshot_valid)

    def test_cli_json_stdout_error_stderr_and_no_snapshot_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            copied = Path(temporary) / "snapshot.bin"
            original = snapshot(chunk(b"RDAF", cc_payload()))
            copied.write_bytes(original)
            before = copied.stat()
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = cs.main(["list", str(copied)])
            self.assertEqual(code, 0)
            self.assertEqual(stderr.getvalue(), "")
            self.assertEqual(json.loads(stdout.getvalue())["candidate_count"], 1)
            after = copied.stat()
            self.assertEqual((before.st_size, before.st_mtime_ns), (after.st_size, after.st_mtime_ns))
            self.assertEqual(copied.read_bytes(), original)
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = cs.main(["list", str(copied.parent / "missing.bin")])
            self.assertEqual(code, 2)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("cs_assignments:", stderr.getvalue())

    def test_cli_forensic_flag_preserves_invalid_warning(self):
        with tempfile.TemporaryDirectory() as temporary:
            copied = Path(temporary) / "snapshot.bin"
            data = snapshot(chunk(b"RDAF", b"test"))
            copied.write_bytes(data[:4] + struct.pack("<I", 4) + data[8:])
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(cs.main(["list", str(copied)]), 2)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("length mismatch", stderr.getvalue())
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(cs.main(["list", str(copied), "--allow-length-mismatch"]), 0)
            self.assertFalse(json.loads(stdout.getvalue())["snapshot"]["snapshot_valid"])
            self.assertEqual(stderr.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
