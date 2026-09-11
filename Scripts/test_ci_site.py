"""The published pages must say what the app says.

App Store Connect points at two URLs, and a privacy policy that has drifted from the
app it describes is a false statement rather than a stale file. `build-site.py`
generates both pages from `FilmApp/Legal.swift`; this fails the build the moment the
committed HTML stops matching, which is the only thing making "one source" true.
"""

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_site", ROOT / "Scripts/build-site.py")
build_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_site)


class PublishedPagesMatchTheApp(unittest.TestCase):
    def test_every_generated_file_is_committed_and_current(self):
        for path, contents in build_site.expected().items():
            relative = path.relative_to(ROOT)
            with self.subTest(file=str(relative)):
                self.assertTrue(path.is_file(), f"{relative} is missing; run Scripts/build-site.py")
                self.assertEqual(path.read_text(), contents,
                                 f"{relative} is stale; run Scripts/build-site.py")

    def test_the_policy_names_the_things_the_app_actually_does(self):
        """A policy is only worth publishing if it is specific. These are the four
        claims the App Privacy answers rest on, so losing one silently is the failure
        this catches."""
        policy = build_site.swift_literal((ROOT / "FilmApp/Legal.swift").read_text(), "privacyPolicy")
        for claim in ["no analytics", "add-only", "no network connection", "Presets"]:
            self.assertIn(claim, policy)


class SwiftLiteralsSurviveTheTripToHTML(unittest.TestCase):
    def test_a_trailing_backslash_joins_the_line_as_swift_would(self):
        source = '    static let x = """\n        one \\\n        two\n\n        three\n        """\n'
        self.assertEqual(build_site.swift_literal(source, "x"), "one two\n\nthree")

    def test_a_short_line_without_a_full_stop_is_a_heading(self):
        tagged = list(build_site.blocks("Children\n\nDye collects nothing.\n"))
        self.assertEqual(tagged, [("h2", "Children"), ("p", "Dye collects nothing.")])

    def test_a_multi_line_paragraph_is_never_a_heading(self):
        tagged = list(build_site.blocks("a line\nand another with no stop"))
        self.assertEqual([tag for tag, _ in tagged], ["p"])


if __name__ == "__main__":
    unittest.main()
