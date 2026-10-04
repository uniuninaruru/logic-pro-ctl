"""Synthetic checks for command_catalog.py: no Logic binary or Ghidra output is needed."""

import tempfile
import unittest
from pathlib import Path

import command_catalog as cc


class FakeImage:
    """u64/u16 over a dict of {virtual address: value}."""

    def __init__(self, words):
        self.words = words

    def u64(self, vm):
        return self.words.get(vm)

    def u16(self, vm):
        return self.words.get(vm)


def stores_file(rows):
    handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False, encoding="utf-8")
    handle.write("# function\tstack_offset\tsize\tvalue\tsource\n")
    for function, offset, size, value in rows:
        unsigned = offset & (1 << 64) - 1
        handle.write(f"{function}\t0x{unsigned:x}\t{size}\t0x{value:x}\tCOPY:const\n")
    handle.close()
    return handle.name


class StoresTests(unittest.TestCase):
    def test_stack_offsets_are_read_as_negative_numbers(self):
        path = stores_file([("00ab8d10", -0x168, 2, 0xBE2), ("00ab8d10", -0x160, 8, 0x23815C8)])
        stores = cc.load_stores(path)
        self.assertEqual(stores["00ab8d10"][-0x168], (0xBE2, 2))
        self.assertEqual(stores["00ab8d10"][-0x160], (0x23815C8, 8))

    def test_a_constructor_yields_entries_in_address_order(self):
        # id (2 bytes) at O, name O+8, table O+0x10, handler O+0x18, arg O+0x20; addresses rise as offsets rise.
        rows = []
        for n, (cid, name, handler, arg) in enumerate([(0xBE2, 0x1000, 0x2000, 10), (0xBE8, 0x1020, 0x2000, 0x11)]):
            base = -0x168 + 0x28 * n
            rows += [("f", base, 2, cid), ("f", base + 8, 8, name), ("f", base + 0x10, 8, 0),
                     ("f", base + 0x18, 8, handler), ("f", base + 0x20, 8, arg)]
        entries = cc.parse_constructor(cc.load_stores(stores_file(rows)), "FUN_f")
        self.assertEqual([e["id"] for e in entries], [0xBE2, 0xBE8])
        self.assertEqual([e["name"] for e in entries], [0x1000, 0x1020])
        self.assertEqual([e["arg"] for e in entries], [10, 0x11])
        self.assertEqual(entries[0]["table"], 0)


class GroupTests(unittest.TestCase):
    def test_group_descriptors_are_read_from_the_frame_and_the_constructor_is_attached(self):
        rows = []
        for g in range(cc.GROUP_COUNT):
            base = -cc.GROUP_FRAME + cc.GROUP_STRIDE * g
            rows += [("008630b4", base, 8, 0x5000 + g), ("008630b4", base + 8, 8, g + 1),
                     ("008630b4", base + 0x10, 8, 0x7F), ("008630b4", base + 0x18, 8, 0x9000 + g),
                     ("008630b4", base + 0x28, 8, 0)]
        names = {0x9000 + g: (f"cf_{g}", f"Group {g}") for g in range(cc.GROUP_COUNT)}
        groups = cc.parse_groups(cc.load_stores(stores_file(rows)), {3: "FUN_00aa"}, names)
        self.assertEqual(len(groups), cc.GROUP_COUNT)
        self.assertEqual((groups[3]["name"], groups[3]["array"], groups[3]["count"], groups[3]["ctor"]),
                         ("Group 3", 0x5003, 4, "FUN_00aa"))
        self.assertIsNone(groups[4]["ctor"])

    def test_the_constructor_called_before_a_group_is_matched_to_that_group(self):
        lines = ["// ==== FUN_008630b4 @ 008630b4", "  FUN_00f59df0();", f"  local_{cc.GROUP_FRAME:x} = &DAT_026eb7e0;",
                 f"  local_{cc.GROUP_FRAME - cc.GROUP_STRIDE:x} = &DAT_022ebb18;", "// ==== FUN_00864230 @ 00864230"]
        with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        self.assertEqual(cc.constructor_order(handle.name), {0: "FUN_00f59df0"})


class TextAndHandlerTests(unittest.TestCase):
    def test_text_at_reports_an_address_that_is_not_a_cfstring(self):
        by_address = {0x10: ("cf_A", "Open Setup")}
        self.assertEqual(cc.text_at(0x10, by_address), ("Open Setup", ""))
        self.assertEqual(cc.text_at(0, by_address), ("", ""))
        self.assertEqual(cc.text_at(0x99, by_address)[1], "not a known CFString")

    def test_handler_names_come_from_the_function_list_or_default_to_the_address(self):
        self.assertEqual(cc.handler_of(0xAD9400, {0xAD9400: "Foo::bar:"}), ("0x00ad9400", "Foo::bar:"))
        self.assertEqual(cc.handler_of(0x1234, {}), ("0x00001234", "FUN_00001234"))
        self.assertEqual(cc.handler_of(0, {}), ("", ""))


class RemoteTests(unittest.TestCase):
    def test_suppressed_ids_are_read_from_the_constant_array(self):
        words = {cc.SUPPRESSED_ARRAY + 8: cc.SUPPRESSED_COUNT, cc.SUPPRESSED_ARRAY + 16: 0x10000003000}
        for i in range(cc.SUPPRESSED_COUNT):
            words[0x3000 + 8 * i] = 0x10000004000 + 0x20 * i      # pointer with the fixup bits set
            words[0x4000 + 0x20 * i + 0x10] = 100 + i
        self.assertEqual(cc.read_suppressed(FakeImage(words)), set(range(100, 200)))

    def test_a_different_count_stops_the_run_instead_of_guessing(self):
        with self.assertRaises(SystemExit):
            cc.read_suppressed(FakeImage({cc.SUPPRESSED_ARRAY + 8: 99}))

    def test_offering_rules(self):
        normal = {"array": 0x1}
        self.assertEqual(cc.remote_offered(normal, 5, {7}), "yes")
        self.assertEqual(cc.remote_offered(normal, 7, {7}), "no: suppressed")
        self.assertEqual(cc.remote_offered({"array": cc.REMOTE_SKIPPED_GROUP_ARRAY}, 5, {7}), "no: group skipped")


class RelationTests(unittest.TestCase):
    def row(self, cid, name, group, handler, arg):
        return {"command_id": cid, "name": name, "group": group, "handler": handler, "arg": arg,
                "twin_of": "", "same_handler": ""}

    def test_tool_menu_entries_pair_with_the_set_tool_entry_of_the_same_name_and_tool_number(self):
        rows = [self.row(851, "Set Scissors Tool", "Various Windows", "0xA", "0x1"),
                self.row(850, "Set Pointer Tool", "Various Windows", "0xA", "0x0"),
                self.row(2318, "Scissors Tool", "Tool Menu", "0xB", "0x1"),
                self.row(2999, "Scissors Tool", "Tool Menu", "0xB", "0x5")]   # same name, other tool: no twin
        cc.add_relations(rows)
        by_id = {r["command_id"]: r for r in rows}
        self.assertEqual(by_id[2318]["twin_of"], 851)
        self.assertEqual(by_id[2999]["twin_of"], "")
        self.assertEqual(by_id[851]["same_handler"], 2)
        self.assertEqual(by_id[2318]["same_handler"], 2)


if __name__ == "__main__":
    unittest.main()
