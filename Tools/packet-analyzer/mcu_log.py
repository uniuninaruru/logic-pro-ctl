#!/usr/bin/env python3
"""Replay an mcu-probe log and reconstruct the Mackie Control surface state.

Usage:
  mcu_log.py LOG                  # print state after each "marker" line
  mcu_log.py LOG --sweep          # TSV of SWEEP markers: sent, echoed, strip-1 lower LCD

Logic sends LCD updates as diffs (offset + changed characters only), so the
LCD must be kept as a 2x56 buffer and patched. Field meanings come from the
public MCU spec and are verified only where Research/experiments says so.
"""
import re
import sys

LINE = re.compile(r"^(\S+) (?:dir=(RX|TX) bytes=((?:[0-9A-F]{2})(?: [0-9A-F]{2})*)\b.*|marker (.*))$")


class Surface:
    def __init__(self):
        self.lcd = [" "] * 112
        self.faders = {}  # channel (0-8) -> 14-bit value
        self.leds = {}  # note -> velocity

    def apply(self, b):
        s = b[0]
        if s & 0xF0 == 0xE0 and len(b) >= 3:
            self.faders[s & 0x0F] = b[1] | (b[2] << 7)
        elif s & 0xF0 == 0x90 and len(b) >= 3:
            self.leds[b[1]] = b[2]
        elif s == 0xF0 and b[1:4] == [0x00, 0x00, 0x66] and len(b) > 7 and b[5] == 0x12:
            off = b[6]
            for i, c in enumerate(b[7:-1]):
                if off + i < 112:
                    self.lcd[off + i] = chr(c)

    def row(self, r):
        return "".join(self.lcd[r * 56:(r + 1) * 56])

    def strip(self, r, n):
        return self.row(r)[n * 7:(n + 1) * 7]


def events(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = LINE.match(line.rstrip("\n"))
            if not m:
                continue
            ts, d, hx, marker = m.groups()
            if marker is not None:
                yield ts, "marker", marker
            else:
                yield ts, d, [int(x, 16) for x in hx.split()]


def main():
    path = sys.argv[1]
    sweep = "--sweep" in sys.argv
    rx = Surface()
    rows = []
    cur = None
    for ts, kind, data in events(path):
        if kind == "marker":
            if sweep:
                m = re.match(r"SWEEP v=(\d+)", data)
                if m:
                    cur = {"sent": int(m.group(1)), "echo": None}
                    rows.append(cur)
                continue
            print(f"--- {ts} {data}")
            print(f"  lcd0: |{rx.row(0)}|")
            print(f"  lcd1: |{rx.row(1)}|")
            print(f"  faders: {dict(sorted(rx.faders.items()))}")
            print(f"  leds on: {sorted(k for k, v in rx.leds.items() if v)}")
            continue
        if kind == "RX":
            rx.apply(data)
            if cur is not None:
                if data[0] == 0xE0 and cur["echo"] is None:
                    cur["echo"] = data[1] | (data[2] << 7)
                cur["lcd"] = rx.strip(1, 0).strip()
    if sweep:
        print("sent\techo\tstrip1_lower_lcd")
        for r in rows:
            echo = "" if r["echo"] is None else r["echo"]
            print(f"{r['sent']}\t{echo}\t{r.get('lcd', '')}")


if __name__ == "__main__":
    main()
