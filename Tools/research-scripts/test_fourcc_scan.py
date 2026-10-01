"""Synthetic fixtures for offset mapping and instruction reconstruction."""

import struct
import unittest

import fourcc_scan as scan


def movz(value, register=0, shift=0, width=32):
    return (0xD2800000 if width == 64 else 0x52800000) | ((shift // 16) << 21) | (value << 5) | register


def movk(value, register=0, shift=16, width=32):
    return (0xF2800000 if width == 64 else 0x72800000) | ((shift // 16) << 21) | (value << 5) | register


def thin(payload):
    # One arm64 instruction section, file offset 0x100 and VA 0x100001000.
    size = 0x100 + len(payload)
    header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 152, 0, 0)
    segment = struct.pack("<II16sQQQQiiII", 0x19, 152, b"__TEXT", 0x100000F00, size, 0, size, 7, 5, 1, 0)
    section = struct.pack("<16s16sQQ8I", b"__text", b"__TEXT", 0x100001000, len(payload), 0x100, 2, 0, 0, 0x80000400, 0, 0, 0)
    return (header + segment + section).ljust(0x100, b"\0") + payload


class FourCCScanTests(unittest.TestCase):
    def test_raw_orders_and_offset_mapping(self):
        data = thin(b"aUeVVeUa")
        hits = scan.raw_hits(data, scan.parse_macho(data), ("aUeV",), 4)
        self.assertEqual([hit["file_offset"] for hit in hits], [0x100, 0x104])
        self.assertEqual([hit["virtual_address"] for hit in hits], [0x100001000, 0x100001004])
        self.assertEqual(hits[0]["architecture"], "arm64")
        self.assertEqual(hits[0]["section"], "__text")
        self.assertEqual(hits[1]["encoding"], "raw-little-endian-u32")

    def test_fat_slice_offsets_are_absolute(self):
        child = thin(b"aUeV")
        data = (struct.pack(">II", 0xCAFEBABE, 1) + struct.pack(">IIIII", 0x0100000C, 0, 0x1000, len(child), 12)).ljust(0x1000, b"\0") + child
        hit = scan.raw_hits(data, scan.parse_macho(data), ("aUeV",), 0)[0]
        self.assertEqual(hit["file_offset"], 0x1100)
        self.assertEqual(hit["slice_file_offset"], 0x100)
        self.assertEqual(hit["virtual_address"], 0x100001000)

    def test_adjacent_w_mov_pair(self):
        data = thin(struct.pack("<II", movz(0x6556), movk(0x6155)))
        hits = scan.mov_pair_hits(data, scan.parse_macho(data), ("aUeV",), 0)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0]["constant"], 0x61556556)
        self.assertEqual(hits[0]["instructions"][1]["register"], "w0")

    def test_x_pair_with_high_half_first(self):
        data = thin(struct.pack("<II", movz(0x5370, register=1, shift=16, width=64), movk(0x7432, register=1, shift=0, width=64)))
        hits = scan.mov_pair_hits(data, scan.parse_macho(data), ("Spt2",), 0)
        self.assertEqual(hits[0]["constant"], 0x53707432)
        self.assertEqual(hits[0]["instructions"][0]["register"], "x1")

    def test_reject_mismatched_register_and_width(self):
        for final in (movk(0x6155, register=1), movk(0x6155, width=64)):
            data = thin(struct.pack("<II", movz(0x6556), final))
            self.assertEqual(scan.mov_pair_hits(data, scan.parse_macho(data), ("aUeV",), 0), [])

    def test_little_endian_constant(self):
        value = int.from_bytes(b"sPmo", "little")
        data = thin(struct.pack("<II", movz(value & 0xFFFF), movk(value >> 16)))
        hit = scan.mov_pair_hits(data, scan.parse_macho(data), ("sPmo",), 0)[0]
        self.assertEqual(hit["encoding"], "arm64-adjacent-MOVZ-MOVK-little-endian-value")

    def test_malformed_macho_fails_instead_of_mapping_invented_addresses(self):
        with self.assertRaises(ValueError):
            scan.parse_macho(bytes.fromhex("cffaedfe"))

    def test_raw_substring_preserves_enclosing_symbol(self):
        symbol = b"_$ss5ClockPss010ContinuousA0VRszrlE10continuousADvgZ"
        data = thin(b"\0" + symbol + b"\0")
        hit = scan.raw_hits(data, scan.parse_macho(data), ("sPkc",), 4)[0]
        self.assertEqual(hit["enclosing_nul_terminated_ascii"], symbol.decode("ascii"))
        self.assertEqual(hit["enclosing_ascii_file_offset"], 0x101)


if __name__ == "__main__":
    unittest.main()
