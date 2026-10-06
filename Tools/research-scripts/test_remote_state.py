"""Checks for remote_state.py: the contract of EXP-REMOTE-002 on synthetic message sequences.

None of the synthetic messages was captured. The last group replays only EXP-REMOTE-001's reference
recording, Research/raw/remote-recv/20261005-094234-e1/ (not tracked by Git), and is skipped when absent.
"""

import plistlib
import struct
import unittest
import zlib
from pathlib import Path

import remote_state as rs
from test_remote_capture import capture, json_frame

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "Research" / "raw" / "remote-recv"
COLOUR = bytes([0x36, 0x6E, 0xAA, 0xFF])


def ati(rows, gindex=None, track_id=None, uuid=None):
    """rows: list of names. Identifiers default to 100+i, 0x40001+i, U-i."""
    n = len(rows)
    gindex = gindex or [100 + i for i in range(n)]
    track_id = track_id or [(4 << 16) | (i + 1) for i in range(n)]
    uuid = uuid or [f"U-{g}" for g in gindex]
    return {
        "c": [{k: COLOUR for k in ("nc", "sc", "tnc", "tsc")} for _ in range(n)],
        "n": [{"name": name, "gindex": g} for name, g in zip(rows, gindex)],
        "t": [1] * n, "nc": [1] * n, "p": [0] * n, "tn": list(range(1, n + 1)),
        "BgTrackInfoTrackIDKey": track_id, "BgTrackInfoTrackUUIDKey": uuid,
        "BgTrackInfoIconIDKey": [0] * n, "BgTrackInfoHasArrangeKey": [True] * n,
        "BgTrackInfoArrangeHiddenKey": [False] * n, "BgTrackInfoCollapsibleInfoKey": [0] * n,
        "BgTrackInfoMetaInfoFlagsKey": [0] * n,
    }


def sti(name, index, tn):
    return {"n": name, "t": 1, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": tn, "BgTrackInfoIndexKey": index}


def kinds(builder):
    return [e["kind"] for e in builder.events]


def fader(builder, gindex):
    strip = next(s for s in builder.snapshot()["strips"] if s["gindex"] == gindex)
    return {f: (None if k is None else k["value"]) for f, k in strip["fader"].items()}


class ZeroAndMissingTests(unittest.TestCase):
    def test_an_absent_field_is_null_and_a_received_zero_is_zero(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 0x5A000000}}})
        b.apply(3, "/gtFaderData", {"g": {100: {"s": 0}}})
        self.assertEqual(fader(b, 100), {"vL": 0x5A000000, "s": 0, "m": None})   # m never sent: null, not 0
        self.assertEqual(fader(b, 101), {"vL": None, "s": None, "m": None})      # nothing sent for B
        strip = b.snapshot()["strips"][0]
        self.assertEqual(strip["fader"]["s"]["frame"], 3)                        # where the 0 came from

    def test_a_partial_delta_keeps_the_fields_it_does_not_carry(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 1, "s": 0, "m": 0}}})
        b.apply(3, "/gtFaderData", {"g": {100: {"m": 1}}})
        self.assertEqual(fader(b, 100), {"vL": 1, "s": 0, "m": 1})

    def test_an_equal_value_is_counted_as_unchanged(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"m": 0}}})
        b.apply(3, "/gtFaderData", {"g": {100: {"m": 0}}})
        last = [e for e in b.events if e["kind"] == "fader_applied"][-1]
        self.assertEqual((last["changed"], last["unchanged"]), (0, 1))
        self.assertEqual(b.snapshot()["strips"][0]["fader"]["m"]["frame"], 2)   # the first sighting stays

    def test_track_fields_are_null_until_sent(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"t": {0x40001: {"r": 0}}})
        track = b.snapshot()["strips"][0]["track_fader"]
        self.assertEqual(track["r"]["value"], 0)
        self.assertIsNone(track["ip"])


class AtiTests(unittest.TestCase):
    def test_columns_of_different_length_are_rejected_and_the_old_state_kept(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        broken = ati(["A", "B", "C"])
        broken["tn"] = [1, 2]
        b.apply(2, "/ati", broken)
        self.assertIn("ati_rejected", kinds(b))
        self.assertEqual([s["name"] for s in b.snapshot()["strips"]], ["A", "B"])
        self.assertEqual(b.snapshot()["observation"]["ati_frame"], 1)

    def test_a_broken_first_ati_leaves_no_strips(self):
        b = rs.StateBuilder()
        broken = ati(["A"])
        del broken["BgTrackInfoTrackIDKey"]
        b.apply(1, "/ati", broken)
        self.assertEqual(b.snapshot()["strips"], [])
        self.assertTrue(b.issues)

    def test_a_duplicate_identifier_inside_one_ati_is_rejected(self):
        for kwargs in ({"gindex": [7, 7]}, {"track_id": [5, 5]}, {"uuid": ["X", "X"]}):
            b = rs.StateBuilder()
            b.apply(1, "/ati", ati(["A", "B"], **kwargs))
            self.assertEqual(b.issues[0]["kind"], "ati_rejected", kwargs)
            self.assertIn("duplicate", b.issues[0]["reason"])
            self.assertEqual(b.snapshot()["strips"], [])

    def test_an_identical_repeat_is_a_duplicate_not_a_change(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 9}}})
        b.apply(3, "/ati", ati(["A"]))
        self.assertEqual(kinds(b)[-1], "ati_duplicate")
        self.assertEqual(fader(b, 100)["vL"], 9)
        self.assertEqual(b.snapshot()["observation"]["ati_frame"], 1)

    def test_values_follow_gindex_through_a_reorder_not_the_position(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"], gindex=[100, 104]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 1}, 104: {"vL": 2}}})
        b.apply(3, "/ati", ati(["B", "A"], gindex=[104, 100], uuid=["U-104", "U-100"]))
        strips = b.snapshot()["strips"]
        self.assertEqual([(s["name"], s["position"], s["fader"]["vL"]["value"]) for s in strips], [("B", 1, 2), ("A", 2, 1)])
        self.assertIn("strip_moved", kinds(b))

    def test_track_values_do_not_follow_a_track_id_that_now_names_another_strip(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"], gindex=[100, 104]))
        b.apply(2, "/gtFaderData", {"t": {0x40001: {"r": 64}}})                  # A's track ID
        b.apply(3, "/ati", ati(["B", "A"], gindex=[104, 100], uuid=["U-104", "U-100"]))   # 0x40001 is now B
        self.assertIsNone(b.snapshot()["strips"][0]["track_fader"]["r"])

    def test_a_new_uuid_under_the_same_gindex_is_another_strip(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 1, "s": 0, "m": 0}}})
        b.apply(3, "/ati", ati(["A2"], uuid=["OTHER"]))
        self.assertIn("identity_changed", [e["kind"] for e in b.issues])
        self.assertEqual(fader(b, 100), {"vL": None, "s": None, "m": None})

    def test_a_strip_that_leaves_and_returns_starts_unknown(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/gtFaderData", {"g": {101: {"vL": 3}}, "t": {0x40002: {"r": 64}}})
        b.apply(3, "/ati", ati(["A"]))
        b.apply(4, "/ati", ati(["A", "B"]))
        self.assertIn("strip_removed", kinds(b))
        self.assertEqual(fader(b, 101), {"vL": None, "s": None, "m": None})
        self.assertIsNone(b.snapshot()["strips"][1]["track_fader"]["r"])


class IdentifierMismatchTests(unittest.TestCase):
    def test_fader_data_for_an_unknown_gindex_is_an_orphan_until_listed(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {999: {"vL": 5}}})
        self.assertEqual(b.issues[-1]["kind"], "orphan_gindex")
        self.assertIn("999", b.snapshot()["orphans"]["gindex"])
        b.apply(3, "/ati", ati(["A", "Z"], gindex=[100, 999]))
        self.assertIn("orphan_attached", kinds(b))
        self.assertEqual(fader(b, 999)["vL"], 5)
        self.assertEqual(b.snapshot()["orphans"]["gindex"], {})

    def test_fader_data_before_any_ati_is_held_not_dropped(self):
        b = rs.StateBuilder()
        b.apply(1, "/gtFaderData", {"g": {100: {"m": 0}}, "t": {0x40001: {"ip": 0}}})
        self.assertEqual({e["kind"] for e in b.issues}, {"orphan_gindex", "orphan_track_id"})
        b.apply(2, "/ati", ati(["A"]))
        snap = b.snapshot()
        self.assertEqual(snap["strips"][0]["fader"]["m"]["value"], 0)
        self.assertEqual(snap["strips"][0]["track_fader"]["ip"]["value"], 0)

    def test_an_unknown_track_id_is_reported(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"t": {0x99999: {"r": 0}}})
        self.assertEqual(b.issues[-1]["kind"], "orphan_track_id")

    def test_a_key_that_is_not_a_number_is_reported(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b._fader(2, {"g": {"x": {"vL": 1}}})       # the schema already refuses this; the builder must not crash
        self.assertEqual(b.issues[-1]["kind"], "bad_key")

    def test_a_schema_invalid_fader_message_changes_nothing(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 1, "volume": 3}}})
        self.assertEqual(b.issues[-1]["kind"], "fader_rejected")
        self.assertIsNone(fader(b, 100)["vL"])


class SelectionAndCountTests(unittest.TestCase):
    def test_a_consistent_selection_is_tied_to_the_strip(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/sti", sti("B", 1, 2))
        selection = b.snapshot()["selection"]
        self.assertEqual((selection["gindex"], selection["position"]), (101, 2))
        self.assertEqual(b.issues, [])

    def test_a_selection_that_disagrees_with_ati_is_reported(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/sti", sti("A", 1, 2))
        self.assertEqual(b.issues[-1]["kind"], "selection_mismatch")
        self.assertIn("name", b.issues[-1]["problems"])
        self.assertIsNone(b.snapshot()["selection"]["gindex"])

    def test_no_track_selected_is_no_selection_not_unknown(self):
        b = rs.StateBuilder()
        self.assertIsNone(b.snapshot()["selection"])               # nothing received yet: unknown
        b.apply(1, "/sti", {"n": "NoTrackSelected", "t": 0, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": 0,
                            "BgTrackInfoIndexKey": 2**63 - 1})
        self.assertFalse(b.snapshot()["selection"]["selected"])    # received: no selection

    def test_an_sti_that_arrives_before_the_first_ati_is_resolved_later(self):
        b = rs.StateBuilder()
        b.apply(1, "/sti", sti("B", 1, 2))
        self.assertIsNone(b.snapshot()["selection"]["gindex"])
        b.apply(2, "/ati", ati(["A", "B"]))
        self.assertEqual(b.snapshot()["selection"]["gindex"], 101)
        self.assertEqual(b.issues, [])

    def test_a_reorder_after_the_sti_makes_a_stale_selection_visible(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/sti", sti("B", 1, 2))
        b.apply(3, "/ati", ati(["B", "A"], gindex=[101, 100], uuid=["U-101", "U-100"]))
        self.assertEqual(b.issues[-1]["kind"], "selection_mismatch")       # index 1 is now A, not B
        self.assertIsNone(b.snapshot()["selection"]["gindex"])            # unresolved, not guessed

    def test_a_repeated_sti_is_a_duplicate(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/sti", sti("A", 0, 1))
        b.apply(3, "/sti", sti("A", 0, 1))
        self.assertEqual(kinds(b)[-1], "sti_duplicate")

    def test_an_empty_ati_unresolves_selection_without_inventing_no_selection(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/sti", sti("A", 0, 1))
        self.assertEqual(b.snapshot()["selection"]["gindex"], 100)
        b.apply(3, "/ati", ati([]))
        self.assertEqual(b.snapshot()["strips"], [])
        selection = b.snapshot()["selection"]
        self.assertTrue(selection["selected"])  # no NoTrackSelected message arrived
        self.assertIsNone(selection["gindex"])
        self.assertIsNone(selection["position"])
        self.assertEqual(selection["resolved_with_ati_frame"], 3)
        self.assertEqual(b.issues[-1]["kind"], "selection_mismatch")

        pending = rs.StateBuilder()
        pending.apply(1, "/sti", sti("A", 0, 1))
        self.assertEqual(pending.issues, [])
        pending.apply(2, "/ati", ati([]))
        self.assertEqual(pending.issues[-1]["kind"], "selection_mismatch")
        pending.apply(3, "/ati", ati(["A"]))
        self.assertEqual(pending.snapshot()["selection"]["gindex"], 100)

    def test_a_count_that_disagrees_with_ati_is_reported(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A", "B"]))
        b.apply(2, "/allTrackCount", 3)
        self.assertEqual(b.issues[-1]["kind"], "count_mismatch")
        b2 = rs.StateBuilder()
        b2.apply(1, "/allTrackCount", 2)
        b2.apply(2, "/ati", ati(["A", "B"]))
        self.assertEqual(b2.issues, [])


class CompletenessAndOrderTests(unittest.TestCase):
    def test_complete_is_never_true_even_when_every_field_is_known(self):
        b = rs.StateBuilder()
        b.apply(1, "/ati", ati(["A"]))
        b.apply(2, "/gtFaderData", {"g": {100: {"vL": 1, "s": 0, "m": 0}}, "t": {0x40001: {"r": 0, "ip": 0}}})
        b.apply(3, "/sti", sti("A", 0, 1))
        b.apply(4, "/allTrackCount", 1)
        b.apply(5, "/trackCount", 1)
        snap = b.snapshot()
        self.assertEqual(snap["coverage"]["fader_fields_known"], snap["coverage"]["fader_fields_total"])
        self.assertIsNone(snap["observation"]["complete"])

    def test_ati_is_applied_first_within_one_group(self):
        b = rs.StateBuilder()
        b.apply_group(1, [("/gtFaderData", {"g": {100: {"vL": 7}}}), ("/ati", ati(["A"]))])
        self.assertEqual(b.issues, [])
        self.assertEqual(fader(b, 100)["vL"], 7)

    def test_addresses_outside_the_state_are_ignored(self):
        b = rs.StateBuilder()
        b.apply(1, "/mixerLevels", [0, 0])
        self.assertEqual(b.events, [])


class CsTableTests(unittest.TestCase):
    ASSIGN = [
        {"model": "1", "kind": "5", "sub": "0", "param": "7", "flags": "2", "address": "/cs/mixer/volume/volume"},
        {"model": "1", "kind": "5", "sub": "4096", "param": "7", "flags": "2", "address": "/cs/mixer/volume/volume1"},
        {"model": "1", "kind": "9", "sub": "0", "param": "0", "flags": "3", "address": "/cs/mixer/mutereset"},
        {"model": "1", "kind": "2", "sub": "0", "param": "0", "flags": "0", "address": "Transport"},
    ]

    def test_instances_fold_into_the_table_template_and_gaps_are_named(self):
        frames = [json_frame({"/cs/mixer/volume/volume1": 90 / 127}), json_frame({"/cs/mixer/volume/volume2": 90 / 127}),
                  json_frame({"/cs/mixer/unknown3": 1})]
        rows = {r[0]: r for r in rs.cs_rows(capture(frames), self.ASSIGN)}
        self.assertEqual(rows["/cs/mixer/volume/volume"][1], "both")
        self.assertEqual(rows["/cs/mixer/volume/volume"][3:5], ["2", "2"])
        self.assertIn("(= 90/127)", rows["/cs/mixer/volume/volume"][6])
        self.assertEqual(rows["/cs/mixer/mutereset"][1], "static only (not received)")
        self.assertEqual(rows["/cs/mixer/unknown"][1], "received only (not in the table)")
        self.assertNotIn("Transport", rows)                                   # only /cs/ rows

    def test_the_real_table_is_readable(self):
        rows = rs.read_assign_table()
        self.assertTrue(any(r["address"] == "/cs/mixer/volume/volume" for r in rows))


class TimelineTests(unittest.TestCase):
    FRAMES = [json_frame({"/mixerLevels": [0.1]}), json_frame({"/cs/mixer/record/3": 0}), json_frame({"/sti": {"n": "Piano"}}),
              json_frame({"/bankNavigator/trackLevels": [0.2]}), json_frame({"/cs/mixer/select/1": 1})]

    def test_meters_are_left_out_and_order_and_time_are_kept(self):
        rows = rs.timeline_rows(capture(self.FRAMES))
        self.assertEqual([r[2] for r in rows], ["/cs/mixer/record/3", "/sti", "/cs/mixer/select/1"])
        self.assertEqual([r[0] for r in rows], ["2", "3", "5"])
        self.assertEqual(rows[1][1], "3.0")
        self.assertEqual(rows[1][3], '{"n": "Piano"}')

    def test_a_frame_range_and_an_include_pattern_narrow_it(self):
        self.assertEqual([r[0] for r in rs.timeline_rows(capture(self.FRAMES), start=3, end=4)], ["3"])
        rows = rs.timeline_rows(capture(self.FRAMES), include=r"Levels$")
        self.assertEqual([r[2] for r in rows], ["/mixerLevels", "/bankNavigator/trackLevels"])   # include decides alone


class TableTests(unittest.TestCase):
    def test_floats_are_listed_with_their_127ths(self):
        self.assertEqual(rs._summary([90 / 127, 90 / 127]), "0.70866 (= 90/127)")
        self.assertEqual(rs._summary([0.123]), "0.12300")

    def test_the_summary_never_lists_a_string(self):
        self.assertEqual(rs._summary(["Piano ", "secret-uuid"]), "2 distinct strings (not listed)")
        self.assertEqual(rs._summary([b"\x01", b"\x01"]), "1 distinct byte strings (not listed)")
        self.assertEqual(rs._summary([0, 64, 0]), "0, 64")
        self.assertEqual(rs._summary(list(range(10))), "0..9 (10 distinct)")
        self.assertEqual(rs._summary([True, True]), "true")


def exp001_reference_capture():
    capture = RAW / "20261005-094234-e1"
    return capture if (capture / "frames").is_dir() and (capture / "events.jsonl").is_file() else None


class EXP001ReferenceCaptureTests(unittest.TestCase):
    """EXP-REMOTE-002's fixed results, using only EXP-REMOTE-001's reference recording when present."""

    @classmethod
    def setUpClass(cls):
        cls.capture = exp001_reference_capture()
        if cls.capture is None:
            raise unittest.SkipTest("EXP-REMOTE-001 reference recording 20261005-094234-e1 is absent")
        cls.builder = rs.replay(cls.capture)
        cls.snap = cls.builder.snapshot()

    def test_the_capture_rebuilds_without_issues(self):
        self.assertEqual(self.builder.issues, [])
        self.assertEqual(self.snap["coverage"]["strips"], 12)
        self.assertEqual(self.snap["coverage"]["fader_fields_known"], 36)
        self.assertEqual(self.snap["coverage"]["track_fields_known"], 24)
        self.assertIsNone(self.snap["observation"]["complete"])

    def test_the_second_ati_is_a_duplicate(self):
        self.assertEqual([e["kind"] for e in self.builder.events if e["address"] == "/ati"].count("ati_duplicate"), 1)

    def test_identifiers_are_kept_apart(self):
        strips = self.snap["strips"]
        positions = [s["position"] for s in strips]
        self.assertEqual(positions, list(range(1, 13)))
        self.assertNotEqual([s["gindex"] for s in strips], sorted(s["gindex"] for s in strips))   # gindex is not position order
        self.assertEqual(len({s["uuid"] for s in strips}), 12)

    def test_the_selection_points_at_a_strip_of_the_snapshot(self):
        selection = self.snap["selection"]
        self.assertTrue(selection["selected"])
        strip = next(s for s in self.snap["strips"] if s["gindex"] == selection["gindex"])
        self.assertEqual((strip["name"], strip["position"]), (selection["name"], selection["index"] + 1))

    def test_replaying_up_to_the_first_ati_has_no_fader_values_yet(self):
        first_ati = next(e["frame"] for e in self.builder.events if e["kind"] == "ati_applied")
        early = rs.replay(self.capture, until=first_ati).snapshot()
        self.assertEqual(early["coverage"]["fader_fields_known"], 0)        # unknown, not zero
        self.assertTrue(all(s["fader"]["vL"] is None for s in early["strips"]))


if __name__ == "__main__":
    unittest.main()
