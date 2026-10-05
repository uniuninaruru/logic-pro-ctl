#!/usr/bin/env python3
"""Rebuild Logic's mixer state from a saved Logic Remote reception, offline (research tool, not the product).

Input: a capture of Tools/remote-research-peer (Research/raw/remote-recv/<time>-e1/, not tracked by Git),
decoded by remote_capture.py. Nothing is sent anywhere and Logic is not needed.

The contract (EXP-REMOTE-002):

1. Unknown is null. A field that has not been received is null. 0 / false appear only when Logic sent them.
2. Four identifiers are kept apart and never stand in for each other:
     gindex    the strip's key: /ati n.gindex, and the keys of /gtFaderData "g"
     position  1-based index in the latest /ati (this changes on a reorder)
     track_id  /ati BgTrackInfoTrackIDKey, and the keys of /gtFaderData "t"
     uuid      /ati BgTrackInfoTrackUUIDKey
   Strip values follow gindex. Nothing is carried over by position.
3. /ati is a whole snapshot. A malformed one (schema error, columns of different length, a duplicate gindex,
   track_id or uuid) is rejected and the previous state is kept. An identical repeat is a duplicate, not a change.
   A gindex whose uuid changes is treated as a different strip: its fader values go back to null.
   A strip that leaves /ati loses its values; if it comes back they start as null.
4. /gtFaderData entries are partial: only the fields present are updated, absent fields keep their value
   (or stay null). An entry for a gindex / track_id that the current /ati does not list is held as an orphan
   (and reported); it is attached if a later /ati lists that identifier.
5. /sti is tied to a strip of the latest /ati by its index and checked (name, tn), again whenever a new /ati
   arrives (an /sti can come first). A disagreement leaves the selection unresolved (gindex null) and is
   reported. "NoTrackSelected" means no selection, not an unknown one.
6. Logic sends no end-of-initial-state marker (SA-REMOTE-STATE-001 §3), so "complete" is never true; it is null.
   Coverage (how many fields are known) is reported instead and does not imply completeness.
7. Within one message group, /ati is applied before the other addresses (they refer to it); the order of keys
   inside a dictionary is not defined by Logic.

  remote_state.py replay CAPTURE [--at FRAME]     state, events and issues as JSON
  remote_state.py coverage CAPTURE                the coverage table (TSV) of the schema addresses
  remote_state.py addresses CAPTURE               every address family seen (TSV), without values
"""
import argparse
import base64
import collections
import json
import re
import sys
from pathlib import Path

import remote_capture
import state_schema_check

ATI_COLUMNS = ("c", "n", "t", "nc", "p", "tn", "BgTrackInfoTrackIDKey", "BgTrackInfoTrackUUIDKey",
               "BgTrackInfoIconIDKey", "BgTrackInfoHasArrangeKey", "BgTrackInfoArrangeHiddenKey",
               "BgTrackInfoCollapsibleInfoKey", "BgTrackInfoMetaInfoFlagsKey")
STRIP_FIELDS = ("vL", "s", "m")
TRACK_FIELDS = ("r", "ip")
STATE_ADDRESSES = ("/ati", "/gtFaderData", "/sti", "/allTrackCount", "/trackCount", "/docOpen")
NO_SELECTION = "NoTrackSelected"
COMPLETE_REASON = "Logic sends no end-of-initial-state marker (SA-REMOTE-STATE-001 §3); complete is never inferred"

ISSUE_KINDS = {"ati_rejected", "fader_rejected", "sti_rejected", "orphan_gindex", "orphan_track_id",
               "identity_changed", "selection_mismatch", "count_mismatch", "bad_key"}


def _schema_form(value):
    if isinstance(value, bytes):
        return base64.b64encode(value).decode()
    if isinstance(value, dict):
        return {str(k): _schema_form(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_schema_form(v) for v in value]
    return value


def _known(value, frame):
    return {"value": value, "frame": frame}


class StateBuilder:
    def __init__(self):
        self.schema = state_schema_check.load_schema()
        self.strips = {}            # gindex -> strip record
        self.order = []             # gindex in /ati order
        self.track_fader = {}       # track_id -> {"r": known|None, "ip": known|None}
        self.orphans = {"gindex": {}, "track_id": {}}
        self.selection = None       # None = no /sti yet
        self.counts = {"/allTrackCount": None, "/trackCount": None}
        self.doc_open = None
        self.last_ati = None
        self.last_sti = None
        self.last_frame = None
        self.ati_frame = None
        self.events = []

    # -- events -----------------------------------------------------------------------------------------
    def _event(self, frame, address, kind, **detail):
        event = {"frame": frame, "address": address, "kind": kind, "issue": kind in ISSUE_KINDS}
        event.update(detail)
        self.events.append(event)

    @property
    def issues(self):
        return [e for e in self.events if e["issue"]]

    # -- entry points -----------------------------------------------------------------------------------
    def apply_group(self, frame, group):
        """group: list of (address, argument) from one dictionary. /ati first (contract 7)."""
        ordered = sorted(group, key=lambda item: 0 if item[0] == "/ati" else 1)
        for address, argument in ordered:
            self.apply(frame, address, argument)

    def apply(self, frame, address, argument):
        if address not in STATE_ADDRESSES:
            return
        self.last_frame = frame
        value, _ = remote_capture.expand_argument(argument)
        errors = state_schema_check.check_message({address: _schema_form(value)}, self.schema)
        handler = {"/ati": self._ati, "/gtFaderData": self._fader, "/sti": self._sti}.get(address)
        if errors:
            kind = {"/ati": "ati_rejected", "/gtFaderData": "fader_rejected", "/sti": "sti_rejected"}.get(address, "rejected")
            self._event(frame, address, kind, reason="schema", errors=errors[:5])
            return
        if handler:
            handler(frame, value)
        elif address == "/docOpen":
            self.doc_open = _known(value, frame)
        else:
            self._count(frame, address, value)

    # -- /ati -------------------------------------------------------------------------------------------
    def _ati(self, frame, ati):
        rows = len(ati["t"])
        gindex = [entry["gindex"] for entry in ati["n"]]
        track_id = list(ati["BgTrackInfoTrackIDKey"])
        uuid = list(ati["BgTrackInfoTrackUUIDKey"])
        for name, column in (("gindex", gindex), ("track_id", track_id), ("uuid", uuid)):
            repeated = [v for v, count in collections.Counter(column).items() if count > 1]
            if repeated:
                self._event(frame, "/ati", "ati_rejected", reason=f"duplicate {name}", values=repeated[:5])
                return
        if ati == self.last_ati:
            self._event(frame, "/ati", "ati_duplicate")
            return
        new_strips = {}
        for i in range(rows):
            g = gindex[i]
            previous = self.strips.get(g)
            record = {
                "gindex": g, "position": i + 1, "track_id": track_id[i], "uuid": uuid[i],
                "tn": ati["tn"][i], "name": ati["n"][i]["name"], "t": ati["t"][i], "nc": ati["nc"][i], "p": ati["p"][i],
                "has_arrange": ati["BgTrackInfoHasArrangeKey"][i], "arrange_hidden": ati["BgTrackInfoArrangeHiddenKey"][i],
                "icon": ati["BgTrackInfoIconIDKey"][i], "collapsible": ati["BgTrackInfoCollapsibleInfoKey"][i],
                "meta": ati["BgTrackInfoMetaInfoFlagsKey"][i],
                "colours": {k: (v.hex() if isinstance(v, bytes) else v) for k, v in ati["c"][i].items()},
                "ati_frame": frame,
                "fader": {f: None for f in STRIP_FIELDS},
            }
            if previous is None:
                self._event(frame, "/ati", "strip_added", gindex=g, position=i + 1)
            elif previous["uuid"] != uuid[i]:
                self._event(frame, "/ati", "identity_changed", gindex=g, position=i + 1)
            else:
                record["fader"] = previous["fader"]
                if previous["position"] != i + 1:
                    self._event(frame, "/ati", "strip_moved", gindex=g, from_position=previous["position"], to_position=i + 1)
            new_strips[g] = record
        for g in self.strips:
            if g not in new_strips:
                self._event(frame, "/ati", "strip_removed", gindex=g)
        kept_tracks = set(track_id)
        self.track_fader = {tid: v for tid, v in self.track_fader.items() if tid in kept_tracks}
        self.strips, self.order = new_strips, gindex
        self.last_ati, self.ati_frame = ati, frame
        self._event(frame, "/ati", "ati_applied", strips=rows)
        self._attach_orphans(frame)
        self._resolve_selection(frame, "/ati")
        self._check_counts(frame)

    def _attach_orphans(self, frame):
        for g in [g for g in self.orphans["gindex"] if g in self.strips]:
            for field, known in self.orphans["gindex"].pop(g).items():
                self.strips[g]["fader"][field] = known
            self._event(frame, "/ati", "orphan_attached", gindex=g)
        tracks = {s["track_id"] for s in self.strips.values()}
        for tid in [t for t in self.orphans["track_id"] if t in tracks]:
            entry = self.track_fader.setdefault(tid, {f: None for f in TRACK_FIELDS})
            entry.update(self.orphans["track_id"].pop(tid))
            self._event(frame, "/ati", "orphan_attached", track_id=tid)

    # -- /gtFaderData -----------------------------------------------------------------------------------
    @staticmethod
    def _int_key(key):
        try:
            return int(key)
        except (TypeError, ValueError):
            return None

    def _fader(self, frame, data):
        tracks = {s["track_id"] for s in self.strips.values()}
        changed = unchanged = 0
        for raw, fields in data.get("g", {}).items():
            g = self._int_key(raw)
            if g is None:
                self._event(frame, "/gtFaderData", "bad_key", side="g", key=str(raw))
                continue
            known = {f: _known(fields[f], frame) for f in STRIP_FIELDS if f in fields}
            if g not in self.strips:
                self.orphans["gindex"].setdefault(g, {}).update(known)
                self._event(frame, "/gtFaderData", "orphan_gindex", gindex=g, fields=sorted(known))
                continue
            fader = self.strips[g]["fader"]
            for f, k in known.items():
                if fader[f] is not None and fader[f]["value"] == k["value"]:
                    unchanged += 1
                else:
                    fader[f] = k
                    changed += 1
        for raw, fields in data.get("t", {}).items():
            tid = self._int_key(raw)
            if tid is None:
                self._event(frame, "/gtFaderData", "bad_key", side="t", key=str(raw))
                continue
            known = {f: _known(fields[f], frame) for f in TRACK_FIELDS if f in fields}
            if tid not in tracks:
                self.orphans["track_id"].setdefault(tid, {}).update(known)
                self._event(frame, "/gtFaderData", "orphan_track_id", track_id=tid, fields=sorted(known))
                continue
            entry = self.track_fader.setdefault(tid, {f: None for f in TRACK_FIELDS})
            for f, k in known.items():
                if entry[f] is not None and entry[f]["value"] == k["value"]:
                    unchanged += 1
                else:
                    entry[f] = k
                    changed += 1
        self._event(frame, "/gtFaderData", "fader_applied", changed=changed, unchanged=unchanged)

    # -- /sti -------------------------------------------------------------------------------------------
    def _sti(self, frame, sti):
        if sti == self.last_sti:
            self._event(frame, "/sti", "sti_duplicate")
            return
        self.last_sti = sti
        if sti.get("n") == NO_SELECTION:
            self.selection = {"selected": False, "frame": frame}
            self._event(frame, "/sti", "sti_applied", selected=False)
            return
        self.selection = {"selected": True, "name": sti.get("n"), "index": sti.get("BgTrackInfoIndexKey"),
                          "tn": sti.get("tn"), "t": sti.get("t"), "frame": frame,
                          "gindex": None, "position": None, "resolved_with_ati_frame": None}
        self._resolve_selection(frame, "/sti")
        self._event(frame, "/sti", "sti_applied", selected=True, gindex=self.selection["gindex"])

    def _resolve_selection(self, frame, address):
        """Tie the selection to a strip of the latest /ati by its index, and check name and tn.
        Called for a new /sti and again for every new /ati (an /sti may arrive before the first /ati)."""
        selection = self.selection
        if not selection or not selection.get("selected") or not self.order:
            return
        index = selection["index"]
        selection.update(gindex=None, position=None, resolved_with_ati_frame=self.ati_frame)
        problems = []
        if isinstance(index, int) and 0 <= index < len(self.order):
            strip = self.strips[self.order[index]]
            selection.update(gindex=strip["gindex"], position=strip["position"])
            if strip["name"] != selection["name"]:
                problems.append("name")
            if strip["tn"] != selection["tn"]:
                problems.append("tn")
        else:
            problems.append("index outside /ati")
        if problems:
            selection.update(gindex=None, position=None)
            self._event(frame, address, "selection_mismatch", problems=problems, sti_frame=selection["frame"])

    # -- counts -----------------------------------------------------------------------------------------
    def _count(self, frame, address, value):
        previous = self.counts[address]
        self.counts[address] = _known(value, frame)
        self._event(frame, address, "count_duplicate" if previous and previous["value"] == value else "count_applied", value=value)
        self._check_counts(frame)

    def _check_counts(self, frame):
        total = self.counts["/allTrackCount"]
        if total is not None and self.last_ati is not None and total["value"] != len(self.order):
            self._event(frame, "/allTrackCount", "count_mismatch", count=total["value"], ati_strips=len(self.order))

    # -- output -----------------------------------------------------------------------------------------
    def snapshot(self):
        strips = []
        for g in self.order:
            record = dict(self.strips[g])
            record["track_fader"] = self.track_fader.get(record["track_id"], {f: None for f in TRACK_FIELDS})
            strips.append(record)
        fader_known = sum(1 for s in strips for f in STRIP_FIELDS if s["fader"][f] is not None)
        track_known = sum(1 for s in strips for f in TRACK_FIELDS if s["track_fader"][f] is not None)
        return {
            "observation": {"source": "logic_remote_capture", "complete": None, "complete_reason": COMPLETE_REASON,
                            "last_frame": self.last_frame, "ati_frame": self.ati_frame},
            "strips": strips,
            "orphans": {k: {str(i): v for i, v in d.items()} for k, d in self.orphans.items()},
            "selection": self.selection,
            "counts": self.counts,
            "doc_open": self.doc_open,
            "coverage": {
                "strips": len(strips),
                "fader_fields_known": fader_known, "fader_fields_total": len(strips) * len(STRIP_FIELDS),
                "track_fields_known": track_known, "track_fields_total": len(strips) * len(TRACK_FIELDS),
                "selection_known": self.selection is not None,
                "counts_known": all(v is not None for v in self.counts.values()),
                "note": "coverage is not completeness: a field can change after this point",
            },
        }


def replay(capture: Path, until=None):
    _, frames = remote_capture.load(capture)
    builder = StateBuilder()
    for frame in frames:
        if until is not None and frame["n"] > until:
            break
        for group in frame["groups"]:
            builder.apply_group(frame["n"], group)
    return builder


# -- tables ----------------------------------------------------------------------------------------------

def _summary(values):
    """A value summary that never prints strings (names, UUIDs, locales stay out of the table)."""
    values = list(values)
    if not values:
        return "—"
    if all(isinstance(v, bool) for v in values):
        return "/".join(sorted({str(v).lower() for v in values}))
    if all(isinstance(v, int) and not isinstance(v, bool) for v in values):
        distinct = sorted(set(values))
        return ", ".join(str(v) for v in distinct) if len(distinct) <= 6 else f"{distinct[0]}..{distinct[-1]} ({len(distinct)} distinct)"
    if all(isinstance(v, (bytes, str)) for v in values):
        return f"{len(set(values))} distinct {'byte strings' if isinstance(values[0], bytes) else 'strings'} (not listed)"
    return f"{len(values)} values of mixed or structured type"


def _messages(capture):
    _, frames = remote_capture.load(capture)
    for frame in frames:
        for group in frame["groups"]:
            for address, argument in group:
                yield frame, address, remote_capture.expand_argument(argument)[0]


def coverage_rows(capture: Path):
    schema = state_schema_check.load_schema()
    by_address = collections.defaultdict(list)
    for _, address, value in _messages(capture):
        by_address[address].append(value)
    rows = []

    def row(address, field, values, checked, distinct_messages):
        rows.append([address, field, "yes", str(len(values)), _summary(values), checked,
                     "yes" if distinct_messages > 1 else "no", "one reception (EXP-REMOTE-001); not repeated"])

    for address in sorted(schema["properties"]):
        values = by_address.get(address, [])
        bad = sum(1 for v in values if state_schema_check.check_message({address: _schema_form(v)}, schema))
        checked = f"pass {len(values) - bad}/{len(values)}" if values else "not seen"
        distinct = len({json.dumps(_schema_form(v), sort_keys=True) for v in values})
        if address == "/ati":
            for column in ATI_COLUMNS:
                cells = [x for v in values for x in v[column]]
                if column == "n":
                    row(address, "n.name", [c["name"] for c in cells], checked, distinct)
                    row(address, "n.gindex", [c["gindex"] for c in cells], checked, distinct)
                elif column == "c":
                    for key in ("nc", "sc", "tnc", "tsc"):
                        row(address, f"c.{key}", [c[key] for c in cells], checked, distinct)
                else:
                    row(address, column, cells, checked, distinct)
        elif address == "/gtFaderData":
            for side, fields in (("g", STRIP_FIELDS), ("t", TRACK_FIELDS)):
                for field in fields:
                    cells = [entry[field] for v in values for entry in v.get(side, {}).values() if field in entry]
                    row(address, f"{side}.{field}", cells, checked, distinct)
        elif address == "/sti":
            for key in sorted({k for v in values for k in v}):
                row(address, key, [v[key] for v in values if key in v], checked, distinct)
        elif address == "/trackSelectionStates":
            for key in sorted({k for v in values for k in v}):
                row(address, key, [v[key] for v in values if key in v], checked, distinct)
        else:
            row(address, "(argument)", values, checked, distinct)
    return rows


def address_rows(capture: Path):
    schema = state_schema_check.load_schema()
    families = collections.OrderedDict()
    for frame, address, _ in _messages(capture):
        pattern = re.sub(r"\d+", "{n}", address)
        entry = families.setdefault(pattern, {"messages": 0, "addresses": set(), "formats": set(), "first": frame["n"]})
        entry["messages"] += 1
        entry["addresses"].add(address)
        entry["formats"].add(frame["format"] + ("+mazp" if frame["compressed"] else ""))
    rows = []
    for pattern, e in families.items():
        in_schema = "yes" if pattern in schema["properties"] else "no"
        rows.append([pattern, str(e["messages"]), str(len(e["addresses"])), ",".join(sorted(e["formats"])), in_schema, str(e["first"])])
    return rows


COVERAGE_HEADER = """# Schema addresses of logic-remote-state.schema.json against one captured reception (EXP-REMOTE-001, EXP-REMOTE-002).
# Generated: python3 Tools/research-scripts/remote_state.py coverage <capture>. The capture itself is not committed.
# Strings (track names, UUIDs, locale, host data) are summarised by count only; no string value is listed.
# changed_seen: whether two messages of the address differed. stability: one reception only, so no value is known to be stable.
# address\tfield\tin_schema\tvalues_seen\tsummary\tschema_check\tchanged_seen\tstability"""

ADDRESS_HEADER = """# Every address family seen in one captured reception (EXP-REMOTE-001); digits are folded into {n}. No values.
# Generated: python3 Tools/research-scripts/remote_state.py addresses <capture>. The capture itself is not committed.
# first_frame: the frame number of the first message of the family (frames are numbered from 1 in arrival order).
# pattern\tmessages\tdistinct_addresses\tformats\tin_schema\tfirst_frame"""


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=["replay", "coverage", "addresses"])
    parser.add_argument("capture")
    parser.add_argument("--at", type=int, help="replay: stop after this frame number")
    options = parser.parse_args(argv)
    capture = Path(options.capture)
    try:
        if options.command == "replay":
            builder = replay(capture, options.at)
            print(json.dumps({"state": builder.snapshot(), "issues": builder.issues,
                              "events": collections.Counter(e["kind"] for e in builder.events)}, ensure_ascii=False, indent=1))
        else:
            header, rows = (COVERAGE_HEADER, coverage_rows(capture)) if options.command == "coverage" else (ADDRESS_HEADER, address_rows(capture))
            print(header)
            for r in rows:
                print("\t".join(r))
    except (OSError, remote_capture.CaptureError, ValueError, KeyError) as problem:
        print(f"cannot read the capture: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
