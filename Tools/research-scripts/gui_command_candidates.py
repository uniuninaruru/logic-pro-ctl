#!/usr/bin/env python3
"""Match observed GUI labels to static catalog candidates; never execute commands."""
import argparse
import csv
import hashlib
import io
import json
import re
import sys
import unicodedata
from pathlib import Path


DEFAULT_CATALOG = Path(__file__).resolve().parents[2] / 'Research/protocol/operation-catalog.tsv'
FIELDS = ('command_id', 'name', 'group', 'handler', 'arg', 'source', 'evidence')


def normalize_label(label):
    label = ' '.join(unicodedata.normalize('NFKC', label).split()).casefold()
    return re.sub(r'\.\.\.$', '', label).rstrip()


def validate_capture(capture):
    if not isinstance(capture, dict) or not isinstance(capture.get('context'), dict):
        raise ValueError('capture must contain a context object and an items array')
    if not isinstance(capture.get('items'), list):
        raise ValueError('capture items must be an array')
    for item in capture['items']:
        if not isinstance(item, dict) or not isinstance(item.get('label'), str):
            raise ValueError('each capture item must contain a string label')
        if not normalize_label(item['label']):
            raise ValueError('capture labels must not be empty')
        if 'enabled' in item and not isinstance(item['enabled'], bool):
            raise ValueError('item enabled must be a boolean')
        if 'order' in item and (type(item['order']) is not int or item['order'] < 0):
            raise ValueError('item order must be a nonnegative integer')
        path = item.get('path')
        if path is not None and not (isinstance(path, str) or
                isinstance(path, list) and all(isinstance(p, str) for p in path)):
            raise ValueError('item path must be a string, string array or null')
    return capture


def read_catalog(path):
    data = path.read_bytes()
    lines = (line for line in io.StringIO(data.decode('utf-8-sig'))
             if not line.lstrip().startswith('#'))
    reader = csv.DictReader(lines, delimiter='\t')
    if not reader.fieldnames or not set(FIELDS).issubset(reader.fieldnames):
        raise ValueError('catalog is missing required columns')
    rows = []
    for row in reader:
        if None in row or any(row[field] is None for field in FIELDS):
            raise ValueError('malformed catalog row')
        if not normalize_label(row['name']):
            raise ValueError('catalog contains an empty name')
        rows.append({field: row[field] for field in FIELDS})
    provenance = {'path': str(path.resolve()), 'sha256': hashlib.sha256(data).hexdigest(),
                  'registrations': len(rows)}
    return rows, provenance


def match_items(items, rows):
    by_label = {}
    for row in rows:
        by_label.setdefault(normalize_label(row['name']), []).append(row)
    results = []
    for item in items:
        normalized = normalize_label(item['label'])
        candidates = [dict(row, match_type='exact' if row['name'] == item['label']
                           else 'normalized') for row in by_label.get(normalized, [])]
        results.append({'observation': item, 'normalized_label': normalized,
                        'candidates': candidates, 'runtime_verified': False,
                        'applicability_verified': False, 'execution_authorized': False})
    return results


class Parser(argparse.ArgumentParser):
    def print_help(self, file=None):
        super().print_help(file or sys.stderr)


def main(argv=None):
    parser = Parser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--label', action='append', help='Observed label; repeatable.')
    inputs.add_argument('--capture', type=Path, help='JSON with context and items.')
    parser.add_argument('--catalog', type=Path, default=DEFAULT_CATALOG)
    args = parser.parse_args(argv)
    try:
        rows, provenance = read_catalog(args.catalog)
        result = {'schema_version': 1, 'catalog': provenance, 'runtime_verified': False,
                  'applicability_verified': False, 'execution_authorized': False}
        if args.capture is not None:
            data = args.capture.read_bytes()
            capture = validate_capture(json.loads(data.decode('utf-8-sig')))
            items = capture['items']
            result['context'] = capture['context']
            result['input'] = {'mode': 'capture', 'path': str(args.capture.resolve()),
                               'sha256': hashlib.sha256(data).hexdigest()}
        else:
            items = [{'label': label} for label in args.label]
            if any(not normalize_label(item['label']) for item in items):
                raise ValueError('labels must not be empty')
            result['input'] = {'mode': 'labels'}
        result['items'] = match_items(items, rows)
        output = json.dumps(result, ensure_ascii=False, allow_nan=False)
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        parser.error(str(error))
    print(output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
