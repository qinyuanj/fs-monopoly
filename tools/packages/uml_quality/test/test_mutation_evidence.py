"""Run with the preflighted mutator venv: python -m unittest discover -s ... ."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from mutator.edn import dumps, keyword

SCRIPT = Path(__file__).resolve().parents[1] / 'mutation_evidence.py'


class MutationEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = 'src/demo/init.lua'
        self.source = self.root / self.target
        self.source.parent.mkdir(parents=True)
        self.source.write_text('function f() return 1 end\n', encoding='utf-8')
        self.targets = self.root / 'targets.json'
        self.targets.write_text(json.dumps([self.target]), encoding='utf-8')
        self.manifest = self.root / 'manifest.json'
        self.artifact = self.root / '.metrics/mutate/demo.edn'

    def run_phase(self, phase):
        return subprocess.run([sys.executable, '-I', str(SCRIPT), phase,
                               str(self.root), str(self.targets), str(self.manifest)],
                              capture_output=True, text=True, check=False)

    def prepare(self):
        result = self.run_phase('prepare')
        self.assertEqual(0, result.returncode, result.stderr)

    def publish(self, sites=2, killed=1, survived=1):
        self.artifact.parent.mkdir(parents=True, exist_ok=True)
        self.artifact.write_text(dumps({
            'version': 1, 'source': self.target, 'namespace': 'demo',
            'forms': [{'file': self.target, 'sites': sites, 'killed': killed,
                       'survived': survived, 'uncovered': 0}],
        }), encoding='utf-8')

    def test_missing_snapshot_with_sites_fails(self):
        self.prepare()
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertIn('status=not-executed target=src/demo/init.lua', result.stdout)

    def test_previous_snapshot_is_not_current(self):
        self.publish()
        self.prepare()
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertIn('snapshot is not from this run', result.stdout)

    def test_no_sites_requires_successful_scan_of_the_target(self):
        self.source.write_text('return {left="right"}\n', encoding='utf-8')
        self.prepare()
        result = self.run_phase('verify')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('status=no-sites target=src/demo/init.lua', result.stdout)

    def test_new_snapshot_reports_mutation_counts_and_init_mapping(self):
        self.prepare()
        self.publish()
        result = self.run_phase('verify')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('status=valid target=src/demo/init.lua mutations=2 killed=1 survived=1', result.stdout)

    def test_line_selection_can_publish_partial_site_counts(self):
        self.prepare()
        self.publish(sites=2, killed=1, survived=0)
        result = self.run_phase('verify')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('mutations=2 killed=1 survived=0', result.stdout)

    def test_target_selection_keeps_omission_diagnostics_out_of_json(self):
        repo = SCRIPT.parents[3]
        scripts = repo / '.uml-viewer/uml-viewer/scripts'
        args_file = self.root / 'args.json'
        args_file.write_text(json.dumps(['src/foundation/move_anim_debug.lua', 'tools/cli.lua']))
        output_file = self.root / 'selected.json'
        result = subprocess.run([sys.executable, '-I', '-B', str(SCRIPT.with_name('mutation_targets.py')),
                                 str(repo), str(scripts.parent), str(args_file), str(output_file)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(['src/foundation/move_anim_debug.lua'], json.loads(output_file.read_text(encoding='utf-8-sig')))
        # 上游 POSIX targets() 静默丢弃范围外目标、不再打诊断(qinyuanj/uml-viewer#165);只钉 JSON 不混入诊断。
        self.assertNotIn('omitted', output_file.read_text(encoding='utf-8-sig'))

    def test_scan_error_is_not_no_sites(self):
        self.prepare()
        self.source.unlink()
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertNotIn('status=no-sites', result.stdout)

    def test_parse_error_is_not_no_sites(self):
        self.source.write_text('function broken(\n', encoding='utf-8')
        self.prepare()
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertNotIn('status=no-sites', result.stdout)

    def test_uncovered_sites_are_not_executed_mutations(self):
        self.prepare()
        self.artifact.parent.mkdir(parents=True)
        self.artifact.write_text('{:version 1 :source "src/demo/init.lua" :namespace "demo" :forms [{:file "src/demo/init.lua" :sites 1 :killed 0 :survived 0 :uncovered 1}]}')
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertIn('no executed mutations', result.stdout)

    def test_snapshot_without_statistics_fails(self):
        self.prepare()
        self.artifact.parent.mkdir(parents=True)
        self.artifact.write_text('{:version 1 :source "src/demo/init.lua" :namespace "demo" :forms []}')
        result = self.run_phase('verify')
        self.assertEqual(1, result.returncode)
        self.assertIn('no statistics', result.stdout)


if __name__ == '__main__':
    unittest.main()
