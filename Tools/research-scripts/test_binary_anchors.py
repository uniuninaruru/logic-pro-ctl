"""Checks for binary_anchors.py, remote_colour_model.py and the tables of SA-REMOTE-TRACKTYPE-001.

The first groups use a synthetic image and need nothing else. The last group reads the real
Logic image and the Apple tools; it is skipped when they are absent or the image is another build.
"""

import hashlib
import struct
import tempfile
import unittest
from pathlib import Path

import binary_anchors as ba
import remote_colour_model as model

ROOT = Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / "Research" / "protocol"
ANCHORS = PROTOCOL / "logic-remote-trackcolor-anchors.tsv"
TRACK_TYPES = PROTOCOL / "logic-remote-track-types.tsv"
COLOUR_BYTES = PROTOCOL / "logic-remote-colour-bytes.tsv"
WIRE_KEYS = PROTOCOL / "logic-remote-wire-keys.tsv"
SHA = "2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998"


def synthetic_image(payload: bytes, vmaddr: int = 0x4000) -> bytes:
    """A thin arm64 Mach-O with one segment: header, load command, then the payload at file offset 0x100."""
    segment = struct.pack("<II16sQQQQiiII", ba.LC_SEGMENT_64, 72, b"__TEXT", vmaddr, 0x1000, 0x100, len(payload), 5, 5, 0, 0)
    header = struct.pack("<8I", ba.MH_MAGIC_64, 0x0100000C, 0, 6, 1, len(segment), 0, 0)
    blob = header + segment
    return blob + b"\0" * (0x100 - len(blob)) + payload


def table_file(lines, sha=SHA):
    handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False, encoding="utf-8")
    handle.write(f"# Image: Synthetic  sha256={sha}\n")
    handle.write("\n".join(lines) + "\n")
    handle.close()
    return handle.name


class ImageTests(unittest.TestCase):
    def test_reads_bytes_by_virtual_address(self):
        image = ba.Image(synthetic_image(b"\x01\x02\x03\x04hello\0"))
        self.assertEqual(image.read(0x4000, 4), b"\x01\x02\x03\x04")
        self.assertEqual(image.cstring(0x4004), "hello")

    def test_an_address_outside_the_segment_is_an_error_not_zeroes(self):
        image = ba.Image(synthetic_image(b"\0" * 8))
        with self.assertRaises(ValueError):
            image.read(0x3FFF, 1)
        with self.assertRaises(ValueError):
            image.read(0x4004, 8)

    def test_a_fat_or_foreign_file_is_refused(self):
        with self.assertRaises(ValueError):
            ba.Image(b"\xca\xfe\xba\xbe" + b"\0" * 64)


class TableParsingTests(unittest.TestCase):
    def rows(self, *lines):
        return ba.parse_anchors(table_file(list(lines)))

    def test_a_good_table_is_read(self):
        sha, anchors = self.rows("a@0x4000\tdata\t0x4000\t01020304\t\tfour bytes")
        self.assertEqual(sha, SHA)
        self.assertEqual(anchors[0].data, b"\x01\x02\x03\x04")

    def test_malformed_rows_are_refused(self):
        bad = [
            "a\tdata\t0x4000\t0102\t",                      # five columns
            "a\tweird\t0x4000\t0102\t\tclaim",              # unknown kind
            "a\tdata\t4000\t0102\t\tclaim",                 # address without 0x
            "a\tdata\t0x4000\t010\t\tclaim",                # odd hex
            "a\tinsn\t0x4000\t0102\tmov x0, x1\tclaim",     # an instruction is 4 bytes
            "a\tbind\t0x4000\t\t\tclaim",                   # bind needs the symbol
            "a\tdata\t0x4000\t0102\t\t",                    # every anchor needs a claim
        ]
        for line in bad:
            with self.assertRaises(ValueError, msg=line):
                self.rows(line)

    def test_a_duplicate_id_is_refused(self):
        with self.assertRaises(ValueError):
            self.rows("a\tdata\t0x4000\t01\t\tc", "a\tdata\t0x4001\t02\t\tc")


class CheckTests(unittest.TestCase):
    def check(self, line, payload=b"\x01\x02\x03\x04"):
        _, anchors = ba.parse_anchors(table_file([line]))
        return ba.check(anchors, ba.Image(synthetic_image(payload)), tools=False)

    def test_matching_bytes_pass(self):
        errors, _ = self.check("a\tdata\t0x4000\t01020304\t\tclaim")
        self.assertEqual(errors, [])

    def test_a_changed_byte_is_a_mismatch(self):
        errors, _ = self.check("a\tdata\t0x4000\t01020305\t\tclaim")
        self.assertEqual(len(errors), 1)
        self.assertIn("01020304", errors[0])

    def test_an_unbacked_address_is_a_mismatch(self):
        errors, _ = self.check("a\tdata\t0x9000\t01\t\tclaim")
        self.assertEqual(len(errors), 1)

    def test_objdump_text_is_normalised(self):
        self.assertEqual(ba.normalize_objdump_text("ldr\tx1, [x1, #0x4d0]            ; =1232"), "ldr x1, [x1, #0x4d0]")
        self.assertEqual(ba.normalize_objdump_text("adrp\tx1, 0x2571000 <_write+0x2571000>"), "adrp x1, 0x2571000")
        self.assertEqual(ba.normalize_objdump_text("stp x8,x9,[sp, #0x60]"), "stp x8, x9, [sp, #0x60]")

    def test_nearby_addresses_share_one_disassembly_run(self):
        self.assertEqual(ba.clusters([0x1000, 0x1004, 0x1100, 0x9000]), [(0x1000, 0x1104), (0x9000, 0x9004)])


class ColourModelTests(unittest.TestCase):
    TABLE = [1.0] * model.HUES

    def test_the_four_bytes_are_ordered_r_g_b_a_and_truncated(self):
        self.assertEqual(model.pack_rgba((1.0, 0.5, 0.25, 0.0)), bytes([255, 127, 63, 0]))

    def test_a_component_above_one_wraps_in_its_low_byte(self):
        self.assertEqual(model.pack_rgba((1.004, 0, 0, 1.0))[0], 256 & 0xFF)

    def test_zero_saturation_is_grey_and_keeps_alpha(self):
        rgba = model.hsv_to_rgba(120, 0, 100, 0.5, self.TABLE, self.TABLE)
        self.assertEqual(rgba, (1.0, 1.0, 1.0, 0.5))

    def test_primary_hues_land_in_the_expected_channels(self):
        red = model.hsv_to_rgba(0, 100, 100, 1.0, self.TABLE, self.TABLE)
        self.assertEqual(model.pack_rgba(red), bytes([255, 0, 0, 255]))
        green = model.hsv_to_rgba(120, 100, 100, 1.0, self.TABLE, self.TABLE)   # 120/359*6 = 2.0056: sector 2
        self.assertEqual(green[1], 1.0)
        blue = model.hsv_to_rgba(240, 100, 100, 1.0, self.TABLE, self.TABLE)    # sector 4
        self.assertEqual(blue[2], 1.0)

    def test_hue_359_wraps_to_red_like_hue_0(self):
        self.assertEqual(model.hsv_to_rgba(359, 100, 100, 1.0, self.TABLE, self.TABLE),
                         model.hsv_to_rgba(0, 100, 100, 1.0, self.TABLE, self.TABLE))

    def test_a_hue_out_of_range_counts_as_zero(self):
        self.assertEqual(model.hsv_to_rgba(500, 100, 100, 1.0, self.TABLE, self.TABLE),
                         model.hsv_to_rgba(0, 100, 100, 1.0, self.TABLE, self.TABLE))


def read_tsv(path, columns):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        cells = line.split("\t")
        assert len(cells) == columns, (path.name, len(cells), line[:80])
        rows.append(cells)
    return rows


class CommittedTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sha, cls.anchors = ba.parse_anchors(ANCHORS)
        cls.by_id = {a.id: a for a in cls.anchors}
        cls.groups = {a.id.split("@")[0] for a in cls.anchors}

    def test_the_anchor_table_names_the_image_it_belongs_to(self):
        self.assertEqual(self.sha, SHA)
        self.assertGreater(len(self.anchors), 100)

    def referenced_groups(self, cell):
        return [g for g in cell.split(",") if g]

    def test_every_track_type_row_points_at_existing_anchors(self):
        for row in read_tsv(TRACK_TYPES, 8):
            for group in self.referenced_groups(row[4]):
                self.assertIn(group, self.groups, row[:3])

    def test_the_t_values_cover_exactly_zero_to_ten(self):
        values = {int(row[2]) for row in read_tsv(TRACK_TYPES, 8) if row[0] == "ati.t"}
        self.assertEqual(values, set(range(11)))

    def test_the_rules_are_numbered_in_order_and_no_value_is_called_a_fact_without_evidence(self):
        rules = [row[1] for row in read_tsv(TRACK_TYPES, 8) if row[0] == "ati.t"]
        self.assertEqual(sorted(set(rules)), [f"R{i}" for i in range(1, 9)])
        for row in read_tsv(TRACK_TYPES, 8):
            self.assertEqual(row[7], "unconfirmed", row[:3])           # nothing was captured from a live Remote
            self.assertIn(row[6], ("high", "medium", "low"), row[:3])
            self.assertTrue(row[4], row[:3])

    def test_only_the_master_meaning_is_called_high_confidence_among_the_kinds_with_a_hypothesis(self):
        high = [row[2] for row in read_tsv(TRACK_TYPES, 8) if row[0] == "ati.t" and row[6] == "high"]
        self.assertEqual(sorted(high), ["0", "5"])

    def test_the_default_colour_indices_agree_with_the_constants_in_the_binary(self):
        expected = {0: 9, 1: 16, 2: 9, 3: 76, 4: 9}
        rows = {int(row[2]): int(row[3].split()[-1]) for row in read_tsv(TRACK_TYPES, 8) if row[0] == "default_colour_index"}
        self.assertEqual(rows, expected)

        def value(prefix):
            data = next(a.data for a in self.anchors if a.id.startswith(prefix + "@"))
            return struct.unpack("<q", data)[0]

        self.assertEqual({k: value(f"DC-key{k}") for k in range(5)}, {k: k for k in range(5)})
        self.assertEqual((value("DC-idx9"), value("DC-idx16"), value("DC-idx76")), (9, 16, 76))

    def test_the_colour_table_covers_the_four_keys_in_rgba_order(self):
        rows = read_tsv(COLOUR_BYTES, 9)
        self.assertEqual([row[0] for row in rows], ["nc", "sc", "tnc", "tsc"])
        wire = {line.split("\t")[0]: line.split("\t")[1] for line in WIRE_KEYS.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("#")}
        binds = {a.address: a.text for a in self.anchors if a.kind == "bind"}
        for row in rows:
            self.assertEqual(row[5], "R,G,B,A")
            self.assertEqual(wire[row[1]], row[0])                      # the constant's wire value is the key
            self.assertEqual(binds[int(row[2], 16)], f"MACore/_{row[1]}")  # the slot imports that constant
            for group in self.referenced_groups(row[8]):
                self.assertIn(group, self.groups, row[:2])

    def test_the_computed_default_tint_follows_from_the_table_values_in_the_anchors(self):
        table1 = [1.0] * model.HUES
        table2 = [1.0] * model.HUES
        table1[212] = struct.unpack("<d", self.by_id["CB-T1-212@0x1d43b98"].data)[0]
        table2[212] = struct.unpack("<d", self.by_id["CB-T2-212@0x1d446d8"].data)[0]
        computed = model.default_icon_tint(table1, table2).hex()
        for row in read_tsv(COLOUR_BYTES, 9):
            if row[0] in ("tnc", "tsc"):
                self.assertTrue(row[7].startswith(computed), (computed, row[7]))


class RealImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = ba.DEFAULT_IMAGE
        if not path.is_file():
            raise unittest.SkipTest(f"{path} not found")
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != SHA:
            raise unittest.SkipTest("the image is another build")
        try:
            ba.find_tool("llvm-objdump")
            ba.find_tool("dyld_info")
        except ba.ToolMissing as missing:
            raise unittest.SkipTest(str(missing))
        cls.path, cls.image = path, ba.Image(content)

    def test_every_anchor_holds_in_the_real_image(self):
        _, anchors = ba.parse_anchors(ANCHORS)
        errors, notes = ba.check(anchors, self.image, self.path)
        self.assertEqual(notes, [])
        self.assertEqual(errors, [])

    def test_the_model_reproduces_the_table_value_from_the_tables_in_the_image(self):
        table1, table2 = model.load_tables(self.image)
        self.assertEqual(model.default_icon_tint(table1, table2).hex(), "8cc0ffff")


if __name__ == "__main__":
    unittest.main()
