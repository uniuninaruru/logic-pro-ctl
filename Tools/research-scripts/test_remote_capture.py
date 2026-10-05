"""Checks for remote_capture.py.

The first groups build synthetic captures (nothing here was captured). The last group reads the newest real
capture under Research/raw/remote-recv/ when there is one (it is not tracked by Git) and is skipped otherwise.
"""

import json
import plistlib
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import remote_capture as rc

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "Research" / "raw" / "remote-recv"


def mazp(data: bytes) -> bytes:
    return b"MAZP" + struct.pack(">HI", 10, len(data)) + zlib.compress(data, 9)


def keyed_archive(root: dict) -> bytes:
    """A minimal NSKeyedArchiver archive of a dictionary whose keys may be numbers."""
    objects = ["$null"]

    def add(value):
        if isinstance(value, dict):
            index = len(objects)
            objects.append(None)
            keys = [add(k) for k in value]
            values = [add(v) for v in value.values()]
            objects[index] = {"NS.keys": keys, "NS.objects": values, "$class": plistlib.UID(class_index)}
            return plistlib.UID(index)
        objects.append(value)
        return plistlib.UID(len(objects) - 1)

    class_index = 1
    objects.append({"$classname": "NSDictionary", "$classes": ["NSDictionary", "NSObject"]})
    top = add(root)
    return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": top},
                           "$objects": objects}, fmt=plistlib.FMT_BINARY)


def ati(names, gindex):
    rows = len(names)
    colour = {k: bytes([0x36, 0x6E, 0xAA, 0xFF]) for k in ("nc", "sc", "tnc", "tsc")}
    return {
        "c": [dict(colour) for _ in range(rows)], "n": [{"name": n, "gindex": g} for n, g in zip(names, gindex)],
        "t": [1] * rows, "nc": [1] * rows, "p": [0] * rows, "tn": list(range(1, rows + 1)),
        "BgTrackInfoTrackIDKey": [(4 << 16) | (i + 1) for i in range(rows)],
        "BgTrackInfoTrackUUIDKey": [f"UUID-{i}" for i in range(rows)], "BgTrackInfoIconIDKey": [0] * rows,
        "BgTrackInfoHasArrangeKey": [True] * rows, "BgTrackInfoArrangeHiddenKey": [False] * rows,
        "BgTrackInfoCollapsibleInfoKey": [0] * rows, "BgTrackInfoMetaInfoFlagsKey": [0] * rows,
    }


def plist_frame(message: dict, compress=False) -> bytes:
    body = plistlib.dumps(message, fmt=plistlib.FMT_BINARY)
    return bytes([0x81]) + mazp(body) if compress else bytes([0x01]) + body


def json_frame(message: dict) -> bytes:
    return bytes([0x04]) + json.dumps(message).encode()


def capture(frames):
    directory = Path(tempfile.mkdtemp())
    (directory / "frames").mkdir()
    events = [{"event": "state", "state": "connected", "t_ms": 0.0},
              {"event": "sent", "address": "/protocolVersion", "argument": 10, "t_ms": 0.1}]
    for number, frame in enumerate(frames, 1):
        (directory / "frames" / f"{number:04d}.bin").write_bytes(frame)
        events.append({"event": "frame", "n": number, "t_ms": float(number), "bytes": len(frame), "tag": frame[0]})
    (directory / "events.jsonl").write_text("\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8")
    return directory


class DecodeTests(unittest.TestCase):
    def test_each_format_decodes(self):
        self.assertEqual(rc.decode_frame(plist_frame({"/docOpen": True}))[0], "plist")
        self.assertEqual(rc.decode_frame(json_frame({"/trackCount": 12}))[2], [[("/trackCount", 12)]])
        name, compressed, groups = rc.decode_frame(plist_frame({"/ati": ati(["A"], [80])}, compress=True))
        self.assertEqual((name, compressed), ("plist", True))
        archive = bytes([0x82]) + mazp(keyed_archive({"/gtFaderData": {"g": {80: {"vL": 0x5A000000, "s": 0, "m": 0}}}}))
        name, compressed, groups = rc.decode_frame(archive)
        self.assertEqual(name, "archive")
        self.assertEqual(groups[0][0][1]["g"][80]["vL"], 0x5A000000)   # numeric keys survive

    def test_an_ordered_batch_keeps_its_groups(self):
        groups = rc.decode_frame(json_frame([{"/a": 1}, {"/b": 2}]))[2]
        self.assertEqual(groups, [[("/a", 1)], [("/b", 2)]])

    def test_broken_containers_are_errors(self):
        body = plistlib.dumps({"/x": 1}, fmt=plistlib.FMT_BINARY)
        wrong_size = b"MAZP" + struct.pack(">HI", 10, len(body) + 1) + zlib.compress(body)
        with self.assertRaises(rc.CaptureError):
            rc.decode_frame(bytes([0x81]) + wrong_size)
        with self.assertRaises(rc.CaptureError):
            rc.decode_frame(b"")
        with self.assertRaises(rc.CaptureError):
            rc.decode_frame(json_frame(["not a dictionary"]))

    def test_a_frame_archive_with_an_unexpected_class_is_refused_but_an_argument_archive_is_not(self):
        archive = plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": plistlib.UID(1)},
                                  "$objects": ["$null", {"$class": plistlib.UID(2)},
                                               {"$classname": "NSValue", "$classes": ["NSValue"]}]}, fmt=plistlib.FMT_BINARY)
        with self.assertRaises(rc.CaptureError):
            rc.unarchive(archive)
        self.assertEqual(rc.unarchive(archive, strict=False), {"$class": "NSValue"})

    def test_an_argument_that_is_a_compressed_archive_is_opened(self):
        value, how = rc.expand_argument(mazp(keyed_archive({"n": "Trk08", "t": 1})))
        self.assertEqual((value, how), ({"n": "Trk08", "t": 1}, "mazp-archive"))


class ReportTests(unittest.TestCase):
    def test_a_small_capture_is_reported(self):
        names, gindex = ["Piano ", "Audio"], [88, 92]
        frames = [
            plist_frame({"/protocolVersion": 10}), plist_frame({"/jsonSupport": 0}),
            json_frame({"/cs/mixer/mute/1": 0}), json_frame({"/cs/mixer/mute/2": 0}),
            json_frame({"/mixerLevels": [0, 0]}),
            plist_frame({"/ati": ati(names, gindex)}, compress=True),
            bytes([0x82]) + mazp(keyed_archive({"/gtFaderData": {"g": {88: {"vL": 1, "s": 0, "m": 0}, 92: {"vL": 1, "s": 0, "m": 0}}}})),
            plist_frame({"/ati": ati(names, gindex)}, compress=True),
            plist_frame({"/sti": mazp(keyed_archive({"n": "Audio", "t": 1, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": 2,
                                                     "BgTrackInfoIndexKey": 1}))}),
        ]
        report = rc.report(capture(frames))
        self.assertEqual(report["frames"], 9)
        self.assertEqual(report["first_messages"][:2], ["/protocolVersion", "/jsonSupport"])
        self.assertEqual([o["address"] for o in report["initial_order"]][:3], ["/protocolVersion", "/jsonSupport", "/cs/*"])
        self.assertEqual(report["initial_order"][2]["count"], 2)          # the /cs/ run is folded
        self.assertNotIn("/mixerLevels", [o["address"] for o in report["initial_order"]])
        self.assertTrue(report["ati_copies_equal"])
        self.assertEqual([row["name"] for row in report["ati"]], names)    # trailing space kept
        self.assertTrue(report["fader_keys_equal_gindex"])
        self.assertEqual(report["sti"][0]["t"], 1)
        self.assertEqual(report["schema_errors"], [])

    def test_a_schema_violation_is_reported_not_hidden(self):
        bad = ati(["A", "B"], [80, 84])
        bad["tn"] = [1]
        report = rc.report(capture([plist_frame({"/ati": bad})]))
        self.assertTrue(any("differ in length" in e["error"] for e in report["schema_errors"]))

    def test_fader_keys_that_differ_from_gindex_are_noticed(self):
        frames = [plist_frame({"/ati": ati(["A"], [80])}),
                  bytes([0x82]) + mazp(keyed_archive({"/gtFaderData": {"g": {81: {"vL": 1}}}}))]
        self.assertFalse(rc.report(capture(frames))["fader_keys_equal_gindex"])


class RealCaptureTests(unittest.TestCase):
    """EXP-REMOTE-001's facts, re-derived from the raw capture when it is on this machine."""

    @classmethod
    def setUpClass(cls):
        captures = sorted(RAW.glob("*-e1")) if RAW.is_dir() else []
        captures = [c for c in captures if (c / "frames").is_dir() and (c / "events.jsonl").is_file()]
        if not captures:
            raise unittest.SkipTest("no capture under Research/raw/remote-recv/")
        cls.report = rc.report(captures[-1])

    def test_every_frame_decodes_and_every_state_message_fits_the_schema(self):
        self.assertGreater(self.report["frames"], 100)
        self.assertEqual(self.report["schema_errors"], [])

    def test_the_peer_sent_only_the_two_allowed_messages(self):
        self.assertEqual([m["address"] for m in self.report["sent_by_peer"]], ["/protocolVersion", "/jsonSupport"])

    def test_session_start_and_fader_keys(self):
        self.assertEqual(self.report["first_messages"][:2], ["/protocolVersion", "/jsonSupport"])
        self.assertEqual(self.report["protocol"]["/protocolVersion"][0], 10)
        self.assertTrue(self.report["fader_keys_equal_gindex"])
        self.assertTrue(self.report["ati_copies_equal"])

    def test_colours_are_four_bytes_with_alpha_last(self):
        for row in self.report["ati"]:
            for colour in row["c"].values():
                self.assertEqual(len(colour), 8)
                self.assertEqual(colour[6:], "ff")


if __name__ == "__main__":
    unittest.main()
