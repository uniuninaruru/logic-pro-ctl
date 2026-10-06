"""Checks for mcu_trace.py on synthetic trace lines (none of them captured)."""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import mcu_trace as mt


def lcd(names, offset=0, whole=True):
    text = "".join(n.ljust(7) for n in names).ljust(56)
    if whole:
        text += "0".ljust(55)
    return "F0 00 00 66 14 12 %02X " % offset + " ".join("%02X" % b for b in text.encode()) + " F7"


def line(time, hexbytes):
    return f"2026-10-07T{time}Z logicd mcu RX {hexbytes}"


class MessageTests(unittest.TestCase):
    def test_a_packet_is_split_into_sysex_and_channel_messages_with_running_status(self):
        data = bytes.fromhex("F0 00 00 66 14 00 F7 D0 00 90 56 7F 59 00 F0 00 00 66 14 21 01 F7")
        self.assertEqual([m.hex(" ").upper() for m in mt.messages(data)],
                         ["F0 00 00 66 14 00 F7", "D0 00", "90 56 7F", "90 59 00", "F0 00 00 66 14 21 01 F7"])


class DumpTests(unittest.TestCase):
    def run_dumps(self, lines, *extra):
        path = Path(tempfile.mkdtemp()) / "logicd.log"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            status = mt.main(["dumps", str(path), *extra])
        return status, out.getvalue()

    def test_one_unit_writes_the_same_display_twice(self):
        status, out = self.run_dumps([line("00:00:00.100", lcd(["Piano", "Synth"])),
                                      line("00:00:00.150", lcd(["Piano", "Synth"]))])
        self.assertEqual(status, 0)
        self.assertIn("\t2\t1\t0\tone unit", out)
        self.assertNotIn("Piano", out)                                  # names only with --names

    def test_two_different_displays_in_one_dump_are_two_units(self):
        status, out = self.run_dumps([line("00:00:00.100", lcd(["Piano", "Synth"])),
                                      line("00:00:00.140", lcd(["Trk07", "Master"])),
                                      line("00:00:00.200", lcd(["Piano", "Synth"]))], "--names")
        self.assertEqual(status, 1)
        self.assertIn("\t3\t2\t2\t2 units suspected", out)
        self.assertIn("Trk07", out)

    def test_navigation_rows_and_other_lines_are_ignored_and_dumps_apart_are_separate(self):
        status, out = self.run_dumps([line("00:00:00.100", lcd(["Piano"])),
                                      line("00:00:00.300", lcd(["Synth"], whole=False)),   # a 56-character row
                                      "2026-10-07T00:00:01.000Z logicd id=x cmd=status",
                                      line("00:00:05.000", lcd(["Synth"]))])
        self.assertEqual(status, 0)
        self.assertEqual(out.count("one unit"), 2)

    def test_a_reconnect_with_renamed_names_is_one_unit(self):
        query = "F0 00 00 66 14 00 F7"
        status, out = self.run_dumps([line("00:00:00.000", query), line("00:00:00.100", lcd(["Piano", "Synth"])),
                                      line("00:00:00.200", query), line("00:00:00.300", lcd(["Lead", "Synth"]))])
        self.assertEqual(status, 0)
        self.assertIn("\t2\t2\t0\tone unit", out)

    def test_nothing_to_read(self):
        status, _ = self.run_dumps(["no trace here"])
        self.assertEqual(status, 2)


if __name__ == "__main__":
    unittest.main()
