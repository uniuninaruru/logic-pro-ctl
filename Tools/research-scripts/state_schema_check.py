"""Check example Logic Remote state messages against logic-remote-state.schema.json.

This is NOT a general JSON Schema implementation. It understands only the keywords the
schema uses (type, properties, patternProperties, additionalProperties, required, items,
enum, minimum, maximum, $ref into #/$defs) so that a typo in the schema or a wrong example
is caught without installing a package. It adds the one rule JSON Schema cannot express:
the 13 arrays of /ati have the same length.
"""

import json
import re
from pathlib import Path

SCHEMA_PATH = Path(__file__).resolve().parents[2] / "Research" / "protocol" / "logic-remote-state.schema.json"

_TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
}

_KNOWN = {
    "$schema", "$id", "$defs", "$ref", "title", "description", "type", "properties", "patternProperties",
    "additionalProperties", "required", "items", "enum", "minimum", "maximum", "contentEncoding",
}


def load_schema(path=SCHEMA_PATH):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _resolve(ref, root):
    assert ref.startswith("#/"), ref
    node = root
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def validate(value, schema, root=None, path="$"):
    """Return a list of error strings; empty means the value fits."""
    root = root or schema
    if "$ref" in schema:
        return validate(value, _resolve(schema["$ref"], root), root, path)
    unknown = {k for k in schema if k not in _KNOWN and not k.startswith("x-")}
    if unknown:
        return [f"{path}: schema uses keyword(s) this checker does not know: {sorted(unknown)}"]
    errors = []
    if "type" in schema:
        kinds = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_TYPES[k](value) for k in kinds):
            return [f"{path}: expected {kinds}, got {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value} < minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value} > maximum {schema['maximum']}")
    if isinstance(value, dict):
        for name in schema.get("required", []):
            if name not in value:
                errors.append(f"{path}: missing required '{name}'")
        props = schema.get("properties", {})
        patterns = schema.get("patternProperties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if key in props:
                errors += validate(item, props[key], root, f"{path}.{key}")
                continue
            matched = [sub for pattern, sub in patterns.items() if re.search(pattern, key)]
            if matched:
                for sub in matched:
                    errors += validate(item, sub, root, f"{path}.{key}")
            elif extra is False:
                errors.append(f"{path}: unexpected key '{key}'")
            elif isinstance(extra, dict):
                errors += validate(item, extra, root, f"{path}.{key}")
    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            errors += validate(item, schema["items"], root, f"{path}[{index}]")
    return errors


def check_ati_lengths(ati):
    """All arrays of one /ati dictionary describe the same strips, so they must be equally long."""
    lengths = {key: len(column) for key, column in ati.items() if isinstance(column, list)}
    if len(set(lengths.values())) > 1:
        return [f"/ati: arrays differ in length: {lengths}"]
    return []


def check_message(message, schema=None):
    schema = schema or load_schema()
    errors = validate(message, schema)
    if isinstance(message, dict) and isinstance(message.get("/ati"), dict):
        errors += check_ati_lengths(message["/ati"])
    return errors
