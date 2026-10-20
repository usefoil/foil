"""Regression checks for failures that could make bundled notes silently stale."""

import json
import runpy
import shutil
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]
check = runpy.run_path(str(SOURCE_ROOT / "scripts/check-release-notes.py"))["check"]


class ReleaseNotesCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.current_version = json.loads((SOURCE_ROOT / "package.json").read_text())["version"]
        for name in (
            "CHANGELOG.md",
            "Foil/ReleaseNotes.swift",
            "project.yml",
            "package.json",
            "Foil.xcodeproj/project.pbxproj",
        ):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE_ROOT / name, target)

    def tearDown(self):
        self.temporary.cleanup()

    def test_current_release_is_complete(self):
        self.assertEqual(check(self.root, None), [])

    def test_commented_out_release_is_missing(self):
        path = self.root / "Foil/ReleaseNotes.swift"
        source = path.read_text()
        start = source.index('        ReleaseNote(\n            title: "1.14.3"')
        end = source.index('        ReleaseNote(\n            title: "1.14.2"', start)
        path.write_text(source[:start] + "/*" + source[start:end] + "*/" + source[end:])
        self.assertTrue(any("1.14.3" in error for error in check(self.root, None)))

    def test_xcode_build_version_must_match(self):
        path = self.root / "Foil.xcodeproj/project.pbxproj"
        path.write_text(path.read_text().replace(f"MARKETING_VERSION = {self.current_version};", "MARKETING_VERSION = 0.0.0;"))
        self.assertTrue(any("Foil.xcodeproj" in error for error in check(self.root, None)))

    def test_blank_highlight_is_rejected(self):
        path = self.root / "Foil/ReleaseNotes.swift"
        source = path.read_text()
        original = '"Fixed startup of advanced external whisper.cpp servers when Foil is opened outside Terminal, with clearer FFmpeg setup guidance."'
        self.assertIn(original, source)
        path.write_text(source.replace(original, '" "'))
        self.assertTrue(any("1.14.1 has an empty" in error for error in check(self.root, None)))

    def test_supported_prerelease_can_pass(self):
        version = "99.0.0-rc.1"
        changelog = self.root / "CHANGELOG.md"
        changelog.write_text(
            f"## [{version}](https://github.com/usefoil/foil/compare/v{self.current_version}...v{version}) "
            "(2026-10-20)\n\n- Preview fixes.\n\n" + changelog.read_text()
        )
        swift = self.root / "Foil/ReleaseNotes.swift"
        marker = "    static let recent: [ReleaseNote] = [\n"
        entry = (
            "        ReleaseNote(\n"
            f'            title: "{version}",\n'
            '            date: "October 20, 2026",\n'
            '            highlights: ["Preview fixes."]\n'
            "        ),\n"
        )
        swift.write_text(swift.read_text().replace(marker, marker + entry))
        package = self.root / "package.json"
        data = json.loads(package.read_text())
        data["version"] = version
        package.write_text(json.dumps(data))
        project = self.root / "project.yml"
        project.write_text(project.read_text().replace(f'MARKETING_VERSION: "{self.current_version}"', f'MARKETING_VERSION: "{version}"'))
        xcode = self.root / "Foil.xcodeproj/project.pbxproj"
        xcode.write_text(xcode.read_text().replace(f"MARKETING_VERSION = {self.current_version};", f"MARKETING_VERSION = {version};"))
        self.assertEqual(check(self.root, version), [])


if __name__ == "__main__":
    unittest.main()
