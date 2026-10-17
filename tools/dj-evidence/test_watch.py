import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

loader = importlib.machinery.SourceFileLoader('djwatch', str(Path(__file__).with_name('watch.pyw')))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.log = self.base / 'gta-earn.log'
        self.log.write_text('historic [dj-result]\n', encoding='utf-8')
        self.steam = self.base / 'video'
        self.session = self.steam / 'bg_3240220_test'
        self.session.mkdir(parents=True)
        (self.session / 'init-stream0.m4s').write_bytes(b'init')
        self.watch = self.new_watch()
        self.watch.poll(1000)

    def new_watch(self):
        return module.Watch(self.base / 'out', self.log, self.steam, self.base, self.base)

    def append(self, text):
        with self.log.open('a', encoding='utf-8') as stream:
            stream.write(text)

    def chunk(self, number, at):
        path = self.session / f'chunk-stream0-{number}.m4s'
        path.write_bytes(b'video')
        os.utime(path, (at, at))
        return path

    def test_partial_line_restart_and_duplicate_diagnostics(self):
        self.assertEqual([], self.watch.state['events'])
        self.append('new [dj-result] stage=resident_seen')
        self.watch.poll(1001)
        self.assertEqual([], self.watch.state['events'])
        self.watch = self.new_watch()
        self.append('\n멈춤: DJ: 교체 결과 미확인\n')
        self.watch.poll(1002)
        self.assertEqual(1, len(self.watch.state['events']))
        self.assertEqual(2, len(self.watch.state['events'][0]['lines']))
        self.new_watch().poll(1003)
        self.assertEqual(1, len(self.new_watch().state['events']))

    def test_preserves_pre_and_post_video_after_source_deletion_and_restart(self):
        self.chunk(1, 800)
        before = self.chunk(2, 990)
        self.append('new [dj-result] stage=resident_seen\n')
        self.watch.poll(1002)
        before.unlink()
        self.chunk(3, 1010)
        restarted = self.new_watch()
        restarted.poll(1044)
        event = restarted.state['events'][0]
        directory = self.base / 'out' / event['name']
        manifest = json.loads((directory / 'incident.json').read_text(encoding='utf-8'))
        self.assertTrue(event['done'])
        self.assertEqual(2, len(manifest['video_chunks']))
        self.assertTrue((directory / self.session.name / 'init-stream0.m4s').exists())
        self.assertTrue((directory / 'gta-earn.log.after').exists())

    def test_truncated_log_and_missing_recording_are_explicit(self):
        self.log.write_text('보류: dj test\n', encoding='utf-8')
        self.watch.poll(1004)
        event = self.watch.state['events'][0]
        manifest = json.loads((self.base / 'out' / event['name'] / 'incident.json').read_text(encoding='utf-8'))
        self.assertEqual([], manifest['video_chunks'])
        self.assertFalse(event['done'])


if __name__ == '__main__':
    unittest.main()
