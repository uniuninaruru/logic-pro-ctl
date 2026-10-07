#!/usr/bin/env python3
"""Print bounded unread board text; keep a separate local cursor per reader."""
import argparse
import codecs
import hashlib
import json
import re
from pathlib import Path


def read_new(board, state, limit):
    data = board.read_bytes()
    prior = json.loads(state.read_text()) if state.exists() else None
    offset = prior['offset'] if prior else 0
    anchor = lambda n: hashlib.sha256(data[max(0, n - 64):n]).hexdigest()
    if prior and (offset > len(data) or anchor(offset) != prior['anchor']):
        offset = 0  # Replaced/truncated board: read again instead of skipping it.
    decoder = codecs.getincrementaldecoder('utf-8')()
    text = decoder.decode(data[offset:], final=False)
    complete_end = len(data) - len(decoder.getstate()[0])
    if prior is None:
        # First use reads the latest bounded context, subsequent uses only new text.
        text = text[-limit:]
        offset = complete_end - len(text.encode('utf-8'))
    chunk = text[:limit]
    if not chunk:
        return 'No new messages.'
    offset += len(chunk.encode('utf-8'))
    state.parent.mkdir(parents=True, exist_ok=True)
    tmp = state.with_suffix('.tmp')
    tmp.write_text(json.dumps({'offset': offset, 'anchor': anchor(offset)}))
    tmp.replace(state)
    return chunk + ('\n[More unread text: run again.]' if offset < len(data) else '')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reader', required=True, help='Use codex or claude, independently.')
    parser.add_argument('--max-chars', type=int, default=1000)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.reader) or args.max_chars < 1:
        parser.error('reader must be a simple name and max-chars must be positive')
    root = Path(__file__).resolve().parents[2]
    state = root / 'Research/raw/handoff/board-cursors' / (args.reader + '.json')
    print(read_new(root / 'chatgpt-claude.md', state, args.max_chars))


if __name__ == '__main__':
    main()
