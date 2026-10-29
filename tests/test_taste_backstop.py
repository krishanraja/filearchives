"""W3.3: the SessionEnd hook keeps only Krish's flagged, scrubbed lines, locally. Synthetic transcript only."""
import io, json, sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.claude' / 'hooks'))
import taste_backstop as backstop  # noqa: E402


class Backstop(unittest.TestCase):
    def test_flagged_lines_scrubbed_and_kept_once(self):
        with tempfile.TemporaryDirectory() as d:
            root, path = Path(d), Path(d) / 't.jsonl'
            path.write_text('\n'.join(json.dumps(r) for r in [
                {'type': 'user', 'message': {'content': 'No, never move that folder. Key sk-SYNTHETICsynthetic0123456789'}},
                {'type': 'user', 'message': {'content': [{'type': 'tool_result', 'content': 'No, tool output'}]}},
                {'type': 'assistant', 'message': {'content': 'No, wrong.'}}]), encoding='utf-8')
            hook = json.dumps({'transcript_path': str(path), 'session_id': 'synthetic'})
            for _ in range(2):
                self.assertEqual(backstop.main([], io.StringIO(hook), root, lambda *_: None), 0)
            rows = [json.loads(l) for l in (root / backstop.OUTBOX).read_text().splitlines()]
            self.assertEqual(len(rows), 1)
            self.assertNotIn('sk-SYNTHETIC', rows[0]['line'])
            self.assertIsNone(rows[0]['venture'])
            self.assertEqual(rows[0]['repository'], 'krishanraja/filearchives')
            self.assertEqual(backstop.main([], io.StringIO('junk'), root, lambda *_: None), 0)


if __name__ == '__main__':
    unittest.main()
