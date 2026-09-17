"""Regression: generated Xcode identifiers must not depend on checkout location."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ProjectGenerationTests(unittest.TestCase):
    def test_identical_projects_across_checkout_locations(self):
        with tempfile.TemporaryDirectory() as temporary:
            outputs = []
            for name in ('local checkout/Conch', 'runner/work/Conch/Conch'):
                checkout = Path(temporary) / name
                (checkout / 'scripts').mkdir(parents=True)
                (checkout / 'Conch.xcodeproj').mkdir()
                shutil.copy2(ROOT / 'scripts/generate-project.py', checkout / 'scripts')
                for folder in ('Sources', 'Tests/ConchTests'):
                    shutil.copytree(ROOT / folder, checkout / folder)
                command = [sys.executable, str(checkout / 'scripts/generate-project.py')]
                subprocess.run(command, check=True, capture_output=True)
                project = checkout / 'Conch.xcodeproj'
                snapshot = {str(p.relative_to(project)): p.read_bytes()
                            for p in project.rglob('*') if p.is_file()}
                subprocess.run(command, check=True, capture_output=True)
                self.assertEqual(snapshot, {str(p.relative_to(project)): p.read_bytes()
                                            for p in project.rglob('*') if p.is_file()})
                outputs.append(snapshot)
            self.assertEqual(outputs[0], outputs[1])


if __name__ == '__main__':
    unittest.main()
