#!/usr/bin/env python3
"""Keep the bundled What's New list aligned with the release changelog."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path


FIRST_BUNDLED_VERSION = "1.13.5"
VERSION = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?"
CHANGELOG_ENTRY = re.compile(rf"^## \[({VERSION})\].*\((\d{{4}}-\d{{2}}-\d{{2}})\)$", re.M)
SWIFT_ENTRY = re.compile(
    rf'ReleaseNote\(\s*title:\s*"(?P<version>{VERSION})",\s*'
    r'date:\s*"(?P<date>[^"]+)",\s*highlights:\s*\[(?P<highlights>.*?)\]\s*\)',
    re.S,
)
SWIFT_HIGHLIGHT = re.compile(r'^\s*"(?:[^"\\]|\\.)+"\s*,?\s*$', re.M)


def check(root: Path, expected_version: str | None) -> list[str]:
    errors: list[str] = []
    changelog = (root / "CHANGELOG.md").read_text()
    swift = (root / "Foil/ReleaseNotes.swift").read_text()
    project = (root / "project.yml").read_text()
    xcode_project = (root / "Foil.xcodeproj/project.pbxproj").read_text()
    package_version = json.loads((root / "package.json").read_text())["version"]

    releases = CHANGELOG_ENTRY.findall(changelog)
    versions = [version for version, _ in releases]
    if FIRST_BUNDLED_VERSION not in versions:
        return [f"CHANGELOG.md has no {FIRST_BUNDLED_VERSION} baseline"]
    releases = releases[: versions.index(FIRST_BUNDLED_VERSION) + 1]
    expected_versions = [version for version, _ in releases]
    if len(expected_versions) != len(set(expected_versions)):
        errors.append("CHANGELOG.md has duplicate release versions")

    notes = list(SWIFT_ENTRY.finditer(swift))
    if len(notes) != len(re.findall(r"\bReleaseNote\(", swift)):
        errors.append("Could not parse every ReleaseNote in Foil/ReleaseNotes.swift")
    actual_versions = [note["version"] for note in notes]
    if actual_versions != expected_versions:
        errors.append(
            "What's New versions must match CHANGELOG.md from newest through "
            f"{FIRST_BUNDLED_VERSION}: expected {expected_versions}, got {actual_versions}"
        )

    dates = dict(releases)
    for note in notes:
        version = note["version"]
        if version in dates:
            try:
                actual_date = datetime.strptime(note["date"], "%B %d, %Y").date().isoformat()
            except ValueError:
                actual_date = "invalid date"
            if actual_date != dates[version]:
                errors.append(f"{version} date is {actual_date}; CHANGELOG.md says {dates[version]}")
        if not SWIFT_HIGHLIGHT.search(note["highlights"]):
            errors.append(f"{version} has no user-facing highlight")

    current_version = expected_versions[0]
    project_versions = set(re.findall(r'MARKETING_VERSION:\s*"([^"]+)"', project))
    xcode_versions = set(re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", xcode_project))
    if package_version != current_version or project_versions != {current_version} or xcode_versions != {current_version}:
        errors.append(
            f"Latest release {current_version} must match package.json ({package_version}) "
            f"project.yml ({sorted(project_versions)}), and Foil.xcodeproj ({sorted(xcode_versions)})"
        )
    if expected_version and expected_version != current_version:
        errors.append(f"Requested release {expected_version} does not match {current_version}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--expected-version")
    args = parser.parse_args()
    try:
        errors = check(args.root, args.expected_version)
    except (OSError, KeyError, json.JSONDecodeError) as error:
        errors = [str(error)]
    if errors:
        for error in errors:
            print(f"Release notes check failed: {error}", file=sys.stderr)
        return 1
    print("Bundled What's New covers every release through the current version.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
