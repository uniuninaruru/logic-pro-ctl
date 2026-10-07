import contextlib
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import gui_command_candidates as tool


CATALOG = ('# static only\n'
           'command_id\tname\tgroup\thandler\targ\tsource\tevidence\n'
           '10\tMute\tTracks\t0x100\t0\tconstructor\t0x200\n'
           '# another comment\n'
           '11\tMute\tRegions\t0x101\t1\tconstructor\t0x201\n'
           '12\tOpen…\tGlobal\t0x102\t0\tconstructor\t0x202\n')


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.catalog = Path(self.temp.name) / 'catalog.tsv'
        self.catalog.write_text(CATALOG, encoding='utf-8')
        self.rows, self.provenance = tool.read_catalog(self.catalog)

    def run_cli(self, args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                code = tool.main(['--catalog', str(self.catalog), *args])
            except SystemExit as error:
                code = error.code
        return code, stdout.getvalue(), stderr.getvalue()

    def test_duplicate_registrations_and_contexts_preserved(self):
        capture = {'context': {'hit_zone': 'region', 'selection_before': [1],
                               'selection_after': [1, 2], 'region_types': ['MIDI']},
                   'items': [{'label': 'Mute', 'enabled': True, 'order': 2,
                              'path': ['Region', 'Mute'], 'context': {'target': 'region'}},
                             {'label': 'Mute', 'enabled': True, 'order': 8,
                              'path': 'Track/Mute', 'context': {'target': 'track'}}]}
        path = Path(self.temp.name) / 'capture.json'
        path.write_text(json.dumps(capture), encoding='utf-8')
        code, stdout, stderr = self.run_cli(['--capture', str(path)])
        self.assertEqual((code, stderr), (0, ''))
        result = json.loads(stdout)
        self.assertEqual(result['context'], capture['context'])
        self.assertEqual([r['observation'] for r in result['items']], capture['items'])
        self.assertEqual(result['items'][0]['candidates'], result['items'][1]['candidates'])
        self.assertEqual([r['command_id'] for r in result['items'][0]['candidates']], ['10', '11'])
        self.assertEqual(result['catalog']['sha256'], hashlib.sha256(self.catalog.read_bytes()).hexdigest())
        self.assertEqual(result['input']['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_disabled_is_preserved_without_execution_authority(self):
        item = {'label': 'Mute', 'enabled': False, 'order': 0, 'path': ['Mute']}
        result = tool.match_items([item], self.rows)[0]
        self.assertEqual(result['observation'], item)
        self.assertEqual(len(result['candidates']), 2)
        for field in ['runtime_verified', 'applicability_verified', 'execution_authorized']:
            self.assertIs(result[field], False)

    def test_menu_order_never_changes_mapping(self):
        a, b = tool.match_items([{'label': 'Mute', 'order': 1},
                                {'label': 'Mute', 'order': 99}], self.rows)
        self.assertEqual(a['candidates'], b['candidates'])
        self.assertNotEqual(a['observation']['order'], b['observation']['order'])

    def test_localized_and_substring_labels_remain_unmatched(self):
        results = tool.match_items([{'label': 'ミュート'}, {'label': 'Mut'},
                                   {'label': 'Mute selected regions'}], self.rows)
        self.assertTrue(all(result['candidates'] == [] for result in results))

    def test_normalization_and_repeatable_labels(self):
        code, stdout, stderr = self.run_cli(['--label', '  ＯＰＥＮ...  ', '--label', '\tMuTe\n'])
        self.assertEqual((code, stderr), (0, ''))
        result = json.loads(stdout)
        self.assertEqual(result['items'][0]['candidates'][0]['command_id'], '12')
        self.assertEqual(result['items'][0]['candidates'][0]['match_type'], 'normalized')
        self.assertEqual(len(result['items'][1]['candidates']), 2)
        self.assertNotIn('context', result)
        self.assertEqual(tool.normalize_label(' A\t B… '), 'a b')
        self.assertEqual(tool.normalize_label('Open.'), 'open.')

    def test_malformed_capture_errors_are_stderr_only(self):
        path = Path(self.temp.name) / 'bad.json'
        bad = ['{', '{}', '{"context":{},"items":{}}',
               '{"context":{},"items":[{}]}',
               '{"context":{},"items":[null]}',
               '{"context":{},"items":[{"label":3}]}',
               '{"context":{},"items":[{"label":"Mute","enabled":"false"}]}',
               '{"context":{},"items":[{"label":"Mute","enabled":null}]}',
               '{"context":{},"items":[{"label":"Mute","order":true}]}',
               '{"context":{},"items":[{"label":"Mute","order":-1}]}',
               '{"context":{},"items":[{"label":"Mute","order":1.5}]}',
               '{"context":{},"items":[{"label":"Mute","order":null}]}',
               '{"context":{},"items":[{"label":"Mute","path":1}]}']
        for text in bad:
            with self.subTest(capture=text):
                path.write_text(text)
                code, stdout, stderr = self.run_cli(['--capture', str(path)])
                self.assertNotEqual(code, 0)
                self.assertEqual(stdout, '')
                self.assertIn('error:', stderr)


if __name__ == '__main__':
    unittest.main()
