"""The state schema accepts its own examples and rejects the mistakes it is meant to catch.

All messages here are synthetic; none was captured from a real Logic Remote connection.
"""

import base64
import copy
import unittest

import state_schema_check as check

DATA = base64.b64encode(b"\xff\x10\x20\x30").decode()


def ati(rows=2):
    color = {"nc": DATA, "sc": DATA, "tnc": DATA, "tsc": DATA}
    return {
        "c": [dict(color) for _ in range(rows)],
        "n": [{"name": f"Track {i + 1}", "gindex": 100 + i} for i in range(rows)],
        "t": [3] * rows,
        "nc": [2] * rows,
        "p": [-1] * rows,
        "tn": list(range(1, rows + 1)),
        "BgTrackInfoTrackIDKey": [(0 << 16) | (i + 1) for i in range(rows)],
        "BgTrackInfoTrackUUIDKey": [f"UUID-{i}" for i in range(rows)],
        "BgTrackInfoIconIDKey": [0] * rows,
        "BgTrackInfoHasArrangeKey": [True] * rows,
        "BgTrackInfoArrangeHiddenKey": [False] * rows,
        "BgTrackInfoCollapsibleInfoKey": [0] * rows,
        "BgTrackInfoMetaInfoFlagsKey": [0] * rows,
    }


class StateSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = check.load_schema()

    def errors(self, message):
        return check.check_message(message, self.schema)

    def test_the_schema_s_own_examples_are_accepted(self):
        for example in self.schema["x-examples"]:
            self.assertEqual(self.errors(example), [], example)

    def test_a_complete_ati_is_accepted(self):
        self.assertEqual(self.errors({"/ati": ati(3)}), [])

    def test_an_empty_project_is_a_valid_ati(self):
        self.assertEqual(self.errors({"/ati": ati(0)}), [])

    def test_arrays_of_different_length_are_rejected(self):
        broken = ati(3)
        broken["tn"] = [1, 2]
        self.assertTrue(any("differ in length" in e for e in self.errors({"/ati": broken})))

    def test_a_missing_ati_column_is_rejected(self):
        broken = ati()
        del broken["BgTrackInfoTrackIDKey"]
        self.assertTrue(any("missing required 'BgTrackInfoTrackIDKey'" in e for e in self.errors({"/ati": broken})))

    def test_an_unknown_ati_column_is_rejected(self):
        broken = ati()
        broken["extra"] = [0, 0]
        self.assertTrue(any("unexpected key 'extra'" in e for e in self.errors({"/ati": broken})))

    def test_a_track_kind_outside_the_range_the_code_can_return_is_rejected(self):
        broken = ati()
        broken["t"] = [11, 3]
        self.assertTrue(self.errors({"/ati": broken}))

    def test_a_flag_that_is_a_number_is_not_a_boolean(self):
        broken = ati()
        broken["BgTrackInfoHasArrangeKey"] = [1, 1]
        self.assertTrue(self.errors({"/ati": broken}))

    def test_partial_fader_entries_are_valid_because_a_delta_carries_only_changed_fields(self):
        self.assertEqual(self.errors({"/gtFaderData": {"g": {"5": {"s": 1}}}}), [])
        self.assertEqual(self.errors({"/gtFaderData": {"t": {"65538": {"ip": 3}}}}), [])

    def test_fader_entries_reject_unknown_fields_and_bad_keys(self):
        self.assertTrue(self.errors({"/gtFaderData": {"g": {"5": {"x": 1}}}}))
        self.assertTrue(self.errors({"/gtFaderData": {"g": {"five": {"m": 0}}}}))

    def test_record_enable_only_takes_the_values_the_code_can_assign(self):
        for good in (0, 1, 3, 64, 128):
            self.assertEqual(self.errors({"/gtFaderData": {"t": {"1": {"r": good}}}}), [], good)
        self.assertTrue(self.errors({"/gtFaderData": {"t": {"1": {"r": 2}}}}))

    def test_independent_pan_is_a_twelve_bit_mask(self):
        self.assertEqual(self.errors({"/gtFaderData": {"t": {"1": {"ip": 4095}}}}), [])
        self.assertTrue(self.errors({"/gtFaderData": {"t": {"1": {"ip": 4096}}}}))

    def test_a_selected_track_dictionary(self):
        selected = {"n": "Track 1", "t": 3, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": 1,
                    "BgTrackInfoShowArpeggiatorButtonKey": False, "BgTrackInfoIndexKey": 0}
        self.assertEqual(self.errors({"/sti": selected}), [])
        nothing = {"n": "NoTrackSelected", "t": 0, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": 0,
                   "BgTrackInfoIndexKey": 2**63 - 1}
        self.assertEqual(self.errors({"/sti": nothing}), [])

    def test_the_selection_dictionary_needs_both_booleans(self):
        self.assertTrue(self.errors({"/trackSelectionStates": {"NextTrackKey": True}}))

    def test_doc_open_is_a_boolean(self):
        self.assertEqual(self.errors({"/docOpen": True}), [])
        self.assertTrue(self.errors({"/docOpen": 1}))

    def test_other_addresses_are_not_rejected(self):
        self.assertEqual(self.errors({"/protocolVersion": 10, "/jsonSupport": 0}), [])

    def test_the_checker_refuses_keywords_it_does_not_understand(self):
        schema = copy.deepcopy(self.schema)
        schema["$defs"]["trackSelectionStates"]["oneOf"] = []
        errors = check.validate({"/trackSelectionStates": {"PreviousTrackKey": True, "NextTrackKey": True}}, schema)
        self.assertTrue(any("does not know" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
