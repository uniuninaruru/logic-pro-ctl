#!/usr/bin/env python3
"""Read a capture of the receive-only research peer (Tools/remote-research-peer) and report on it.

A capture directory (Research/raw/remote-recv/<time>-e1/, not tracked by Git) holds events.jsonl and
frames/NNNN.bin, one file per MultipeerConnectivity data packet as Logic sent it. This script decodes the
frames itself (independently of the Swift RemoteFrameParser the peer used while recording):

    frame = tag payload;  tag bit 7: MAZP container;  low bits: 1 plist, 4 JSON, other keyed archive
    MAZP  = "MAZP" u16be header_length u32be size zlib(at header_length)

and prints a JSON report: frame formats, the order of the initial send, the /ati table, /sti, /gtFaderData,
the default colours, the schema check of every state message, and the meter rates.

  remote_capture.py report CAPTURE_DIR            # JSON on stdout
"""
import argparse
import base64
import collections
import json
import plistlib
import struct
import sys
import zlib
from pathlib import Path

import state_schema_check

METER_ADDRESSES = {"/mixerLevels", "/bankNavigator/trackLevels", "/mixer/gainReductionData"}


class CaptureError(ValueError):
    pass


def inflate_mazp(data: bytes) -> bytes:
    if len(data) < 10 or data[:4] != b"MAZP":
        raise CaptureError("not a MAZP container")
    header = struct.unpack(">H", data[4:6])[0]
    size = struct.unpack(">I", data[6:10])[0]
    if header < 10 or header > len(data):
        raise CaptureError("bad MAZP header length")
    out = zlib.decompress(data[header:])
    if len(out) != size:
        raise CaptureError(f"MAZP size {len(out)} != declared {size}")
    return out


def unarchive(data: bytes, strict: bool = True):
    """A keyed archive (NSKeyedArchiver, binary plist) to plain Python values. Other plists pass through.

    strict: refuse classes other than those Logic's frame decoder allows. Archives inside an argument
    (/mixer/eq/path, …) are application data and may hold others such as NSValue; those become {"$class": name}."""
    archive = plistlib.loads(data)
    if not (isinstance(archive, dict) and "$objects" in archive and "$top" in archive):
        return archive
    objects = archive["$objects"]

    def resolve(item):
        if isinstance(item, plistlib.UID):
            item = objects[item.data]
        if isinstance(item, dict) and "$class" in item:
            if "NS.keys" in item:
                return {resolve(k): resolve(v) for k, v in zip(item["NS.keys"], item["NS.objects"])}
            if "NS.objects" in item:
                return [resolve(v) for v in item["NS.objects"]]
            if "NS.string" in item:
                return item["NS.string"]
            if "NS.bytes" in item:
                return bytes(item["NS.bytes"])
            if "NS.relative" in item:
                return {"url": resolve(item["NS.relative"])}
            classname = objects[item["$class"].data].get("$classname")
            if strict:
                raise CaptureError(f"archived class {classname} is not handled")
            return {"$class": classname}
        if item == "$null":
            return None
        return item

    top = archive["$top"]
    return resolve(top.get("root", next(iter(top.values()))))


def decode_frame(frame: bytes):
    """Return (format name, compressed?, list of message groups). A group is a list of (address, argument)."""
    if not frame:
        raise CaptureError("empty frame")
    tag, payload = frame[0], frame[1:]
    compressed = bool(tag & 0x80)
    if compressed and payload[:4] == b"MAZP":
        payload = inflate_mazp(payload)
    kind = tag & 0x7F
    if kind == 1:
        name, top = "plist", plistlib.loads(payload)
    elif kind == 4:
        name, top = "json", json.loads(payload)
    else:
        name, top = "archive", unarchive(payload)
    groups = [top] if isinstance(top, dict) else top
    if not isinstance(groups, list) or not all(isinstance(g, dict) for g in groups):
        raise CaptureError("top level is neither a dictionary nor an array of dictionaries")
    return name, compressed, [[(str(a), v) for a, v in g.items()] for g in groups]


def expand_argument(value):
    """Arguments that are themselves a MAZP keyed archive (/sti, /signatureList, …) are opened."""
    if isinstance(value, bytes) and value[:4] == b"MAZP":
        return unarchive(inflate_mazp(value), strict=False), "mazp-archive"
    if isinstance(value, bytes) and value[:8] == b"bplist00":
        return unarchive(value, strict=False), "archive"
    return value, None


def jsonable(value):
    if isinstance(value, bytes):
        return {"base64": base64.b64encode(value).decode()}
    if isinstance(value, dict):
        return {str(k): jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [jsonable(v) for v in value]
    return value


def for_schema(value):
    """The schema describes NSData as base64 text."""
    if isinstance(value, bytes):
        return base64.b64encode(value).decode()
    if isinstance(value, dict):
        return {str(k): for_schema(v) for k, v in value.items()}
    if isinstance(value, list):
        return [for_schema(v) for v in value]
    return value


def load(capture: Path):
    events = [json.loads(line) for line in (capture / "events.jsonl").read_text(encoding="utf-8").splitlines() if line]
    # The recorder uses a minimum width of four digits; 10000.bin must follow 9999.bin.
    # Keep all duplicate numeric counters, with the same filename ordering for ties as before.
    frames = sorted((capture / "frames").glob("*.bin"), key=lambda path: (int(path.stem), path.name))
    times = {e["n"]: e["t_ms"] for e in events if e.get("event") == "frame"}
    decoded = []
    for path in frames:
        number = int(path.stem)
        data = path.read_bytes()
        name, compressed, groups = decode_frame(data)
        decoded.append({"n": number, "t_ms": times.get(number), "bytes": len(data), "tag": data[0],
                        "format": name, "compressed": compressed, "groups": groups})
    return events, decoded


def report(capture: Path) -> dict:
    events, frames = load(capture)
    connected = next((e["t_ms"] for e in events if e.get("event") == "state" and e.get("state") == "connected"), None)
    sent = [{"address": e["address"], "argument": e["argument"]} for e in events if e.get("event") == "sent"]
    messages = []
    for frame in frames:
        for group in frame["groups"]:
            for address, argument in group:
                messages.append((frame, address, argument))

    formats = collections.Counter((f["format"], f["compressed"]) for f in frames)
    uncompressed_over_1024 = [f["n"] for f in frames if not f["compressed"] and f["bytes"] - 1 > 1024]

    # The order of the initial send with the meter streams left out and each /cs/ run folded into one line.
    order = []
    for frame, address, _ in messages:
        if address in METER_ADDRESSES:
            continue
        label = "/cs/*" if address.startswith("/cs/") else address
        if order and order[-1]["address"] == label == "/cs/*":
            order[-1]["count"] += 1
            continue
        order.append({"n": frame["n"], "address": label, "count": 1, "format": frame["format"]})

    def all_of(address):
        return [argument for _, a, argument in messages if a == address]

    ati = all_of("/ati")
    table = []
    last = ati[-1] if ati else None
    lengths = {len(v) for v in last.values() if isinstance(v, list)} if isinstance(last, dict) else set()
    if len(lengths) == 1:   # a malformed /ati is left to the schema check below, not tabulated
        for i in range(lengths.pop()):
            table.append({
                "position": i + 1, "name": last["n"][i]["name"], "gindex": last["n"][i]["gindex"],
                "t": last["t"][i], "nc": last["nc"][i], "p": last["p"][i], "tn": last["tn"][i],
                "track_id": hex(last["BgTrackInfoTrackIDKey"][i]),
                "uuid_present": bool(last["BgTrackInfoTrackUUIDKey"][i]),
                "has_arrange": last["BgTrackInfoHasArrangeKey"][i], "arrange_hidden": last["BgTrackInfoArrangeHiddenKey"][i],
                "icon": last["BgTrackInfoIconIDKey"][i], "collapsible": last["BgTrackInfoCollapsibleInfoKey"][i],
                "meta": last["BgTrackInfoMetaInfoFlagsKey"][i],
                "c": {k: v.hex() for k, v in last["c"][i].items()},
            })
    uuids = [row for row in (last.get("BgTrackInfoTrackUUIDKey", []) if isinstance(last, dict) else [])]

    fader = all_of("/gtFaderData")
    gindex = {row["gindex"] for row in table}
    fader_keys = {int(k) for k in fader[0].get("g", {})} if fader else set()

    schema = state_schema_check.load_schema()
    schema_errors = []
    for frame, address, argument in messages:
        value, _ = expand_argument(argument)
        for error in state_schema_check.check_message({address: for_schema(value)}, schema):
            schema_errors.append({"n": frame["n"], "address": address, "error": error})

    colour_map = all_of("/colorIndexMap")
    defaults = colour_map[0].get("defaultColorIndexForTrackTypes") if colour_map else None

    after = [f for f in frames if connected is not None and f["t_ms"] is not None and f["t_ms"] >= connected]
    meter_rates = {}
    if after:
        span = (after[-1]["t_ms"] - after[0]["t_ms"]) / 1000 or 1
        counts = collections.Counter(a for _, a, _ in messages if a in METER_ADDRESSES)
        meter_rates = {a: round(c / span, 1) for a, c in counts.items()}

    def plain(address):
        values = []
        for argument in all_of(address):
            value, wrapped = expand_argument(argument)
            values.append(jsonable(value))
        return values

    return {
        "capture": capture.name,
        "frames": len(frames),
        "messages": len(messages),
        "distinct_addresses": len({a for _, a, _ in messages}),
        "sent_by_peer": sent,
        "formats": [{"format": k[0], "compressed": k[1], "frames": v} for k, v in sorted(formats.items())],
        "uncompressed_payloads_over_1024": uncompressed_over_1024,
        "first_messages": [a for _, a, _ in messages[:5]],
        "initial_order": order,
        "ati_copies": len(ati),
        "ati_copies_equal": len(ati) > 1 and all(copy == ati[0] for copy in ati),
        "ati": table,
        "uuids_distinct": len(set(uuids)) == len(uuids),
        "sti": plain("/sti"),
        "track_counts": {"/allTrackCount": all_of("/allTrackCount"), "/trackCount": all_of("/trackCount")},
        "gtFaderData_first": jsonable(fader[0]) if fader else None,
        "fader_keys_equal_gindex": bool(fader) and fader_keys == gindex,
        "default_colour_index_for_track_types": jsonable(defaults),
        "tempo": {"/logicClock/currentTempo": all_of("/logicClock/currentTempo"), "/multiTempo": all_of("/multiTempo")},
        "doc_open": all_of("/docOpen"),
        "protocol": {"/protocolVersion": all_of("/protocolVersion"), "/jsonSupport": all_of("/jsonSupport"),
                     "/hostType": all_of("/hostType")},
        "schema_errors": schema_errors,
        "meter_messages_per_second": meter_rates,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=["report"])
    parser.add_argument("capture")
    options = parser.parse_args(argv)
    try:
        print(json.dumps(report(Path(options.capture)), ensure_ascii=False, indent=1))
    except (OSError, CaptureError, ValueError) as problem:
        print(f"cannot read the capture: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
