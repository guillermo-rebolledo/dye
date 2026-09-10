import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from ci_scope import classify, scope


class ScopeTests(unittest.TestCase):
    def test_required_jobs(self):
        cases = [
            (["README.md", "docs/print.md", "design_handoff_dye_editor/mockup.png"], (False, False)),
            (["FilmApp/Editor/Parameter.swift", "FilmApp.xcodeproj/project.pbxproj"], (False, True)),
            (["Tests/FilmEngineTests/Fixtures/README.md"], (True, False)),
            (["ProfileBaker/Bake.swift"], (True, False)),
            (["FilmApp/Editor/Parameter.swift", "Tests/FilmEngineTests/RendererTests.swift"], (True, True)),
            (["Sources/FilmEngine/Renderer.swift"], (True, True)),
            (["Curves/portra-400/SOURCES.md"], (True, True)),
            (["Sources/FilmEngine/Catalogue/portra-400.filmprofile"], (True, True)),
            (["Package.swift"], (True, True)),
            ([".github/workflows/ci.yml"], (True, True)),
            (["Scripts/ci_scope.py"], (True, True)),
            (["new-build-config"], (True, True)),
            ([], (False, False)),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(classify(paths), expected)

    def test_main_and_manual_runs_do_not_filter(self):
        with patch("ci_scope.subprocess.check_output") as diff:
            self.assertEqual(scope(""), (True, True))
            diff.assert_not_called()

    def test_missing_base_fails_instead_of_skipping_checks(self):
        with patch("ci_scope.subprocess.check_output", side_effect=subprocess.CalledProcessError(128, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                scope("missing")

    def test_full_diff_includes_earlier_commits_and_renamed_source(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], stderr=subprocess.DEVNULL).decode().strip()

            git("init")
            git("config", "user.name", "CI test")
            git("config", "user.email", "ci@example.invalid")
            root = Path(directory)
            (root / "FilmApp").mkdir()
            (root / "FilmApp/view.swift").write_text("original\n")
            git("add", ".")
            git("commit", "-m", "base")
            base = git("rev-parse", "HEAD")
            (root / "docs").mkdir()
            git("mv", "FilmApp/view.swift", "docs/old view\n.swift")
            git("commit", "-m", "move source into docs")
            (root / "README.md").write_text("docs-only final commit\n")
            git("add", ".")
            git("commit", "-m", "docs")
            previous = os.getcwd()
            try:
                os.chdir(directory)
                self.assertEqual(scope(base), (False, True))
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
