#!/usr/bin/env python3
"""Read logicd's MCU trace (LOGICD_TRACE=1) and say how many units wrote the display in each connection dump.

logicd logs every MIDI packet from Logic as `<time> logicd mcu RX <hex bytes>`. Logic writes the whole LCD in one
sysex (`F0 00 00 66 14 12 00 <111 characters> F7`) only in its dump after a connection. One Mackie Control unit
writes the same display; a second unit on the same port writes a different one (EXP-MCU-029). This tool groups the
whole-display writes into bursts (writes no more than --window seconds apart, as logicd does) and counts the
different name rows in each burst.

    mcu_trace.py dumps ~/Library/Logs/logicctl/logicd.log [--since 2026-10-07T00:00] [--window 1.0] [--names]

Without --names only counts are printed; with it, the name rows too (track names: local analysis, do not commit).
Exit status: 0 every burst had one display, 1 a burst had more than one, 2 nothing to read.
"""
import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

LINE = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?)Z logicd mcu RX ((?:[0-9A-F]{2} ?)+)$")
WHOLE_DISPLAY = 100          # bytes of text; Logic's dump writes 111, navigation replies about 55


def parse_time(text):
    return datetime.fromisoformat(text)


def messages(data):
    """Splits one packet into MIDI messages (sysex, and channel messages with running status)."""
    out, i, running = [], 0, None
    while i < len(data):
        b = data[i]
        if b == 0xF0:
            end = data.index(0xF7, i) if 0xF7 in data[i:] else len(data) - 1
            out.append(data[i:end + 1])
            i = end + 1
            continue
        if b >= 0xF8:
            i += 1
            continue
        if b & 0x80:
            running = b if b < 0xF0 else None
            status, i = b, i + 1
        elif running is not None:
            status = running
        else:
            i += 1
            continue
        length = 1 if (status & 0xF0) in (0xC0, 0xD0) else 2
        out.append(bytes([status]) + data[i:i + length])
        i += length
    return out


def display_writes(lines, since=None):
    """(time, name row) for every whole-display write from model 0x14."""
    for line in lines:
        m = LINE.match(line.rstrip("\n"))
        if not m:
            continue
        when = parse_time(m.group(1))
        if since and when < since:
            continue
        for msg in messages(bytes(int(x, 16) for x in m.group(2).split())):
            if len(msg) >= 8 and msg[:7] == bytes([0xF0, 0x00, 0x00, 0x66, 0x14, 0x12, 0x00]) and msg[-1] == 0xF7:
                text = msg[7:-1]
                if len(text) >= WHOLE_DISPLAY:
                    yield when, text[:56].decode("ascii", "replace")


def bursts(writes, window=1.0):
    groups = []
    for when, row in writes:
        if groups and (when - groups[-1][-1][0]).total_seconds() <= window:
            groups[-1].append((when, row))
        else:
            groups.append([(when, row)])
    return groups


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=["dumps"])
    parser.add_argument("log", type=Path)
    parser.add_argument("--since", type=parse_time)
    parser.add_argument("--window", type=float, default=1.0)
    parser.add_argument("--names", action="store_true")
    options = parser.parse_args(argv)
    try:
        lines = options.log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as problem:
        print(f"cannot read the log: {problem}", file=sys.stderr)
        return 2
    groups = bursts(display_writes(lines, options.since), options.window)
    if not groups:
        print("no whole-display writes (was logicd started with LOGICD_TRACE=1?)", file=sys.stderr)
        return 2
    worst = 0
    print("# start\twrites\tdifferent_name_rows\tverdict")
    for group in groups:
        rows = list(dict.fromkeys(row for _, row in group))
        worst = max(worst, len(rows))
        verdict = "one unit" if len(rows) == 1 else f"{len(rows)} units suspected"
        print(f"{group[0][0].isoformat()}Z\t{len(group)}\t{len(rows)}\t{verdict}")
        if options.names:
            for row in rows:
                print(f"\t\t{row.rstrip()}")
    return 0 if worst <= 1 else 1


if __name__ == "__main__":
    sys.exit(main())
