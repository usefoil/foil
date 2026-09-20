#!/usr/bin/env python3
"""Run deterministic baseline suites in a uniquely branded temporary test host.

Existing hosted tests clear UserDefaults.standard. Never run them against the
normal Foil identity for this gate. Only storage identity and updater startup
differ in the copy; processing implementation and test sources are unchanged.
Does not install apps, run paste automation, or change normal Foil preferences.
"""
import argparse
import difflib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
SUITES = ["TranscriptionControllerTests", "TranscriptionHistoryTests", "AppStateTests",
          "CleanupGroupTests", "PasteQueueTests", "QueuedPasteTests"]


def prepare(destination):
    checkout = destination / "checkout"
    checkout.mkdir()
    for name in ["Foil", "FoilTests", "FoilUITests", "FoilE2E", "Foil.xcodeproj"]:
        shutil.copytree(ROOT / name, checkout / name,
                        ignore=shutil.ignore_patterns("xcuserdata", "DerivedData"))
    suffix = uuid.uuid4().hex
    identity = "com.neonwatty.Foil.Tranche0QA." + suffix
    support = "Foil Tranche0 QA " + suffix
    edits = [
        ("Foil.xcodeproj/project.pbxproj", "FOIL_APP_BUNDLE_IDENTIFIER = com.neonwatty.Foil;",
         f"FOIL_APP_BUNDLE_IDENTIFIER = {identity};", 2),
        ("Foil/SparkleUpdater.swift", "!isUITesting && !AppBrand.isDevelopmentBuild",
         "false // Isolated baseline host: never start the updater.", 1),
        ("Foil/AppBrand.swift", "static var applicationSupportDirectoryName: String {\n        name\n    }",
         f'static var applicationSupportDirectoryName: String {{\n        "{support}"\n    }}', 1)
    ]
    diffs = []
    for relative, old, new, count in edits:
        path = checkout / relative
        before = path.read_text()
        if before.count(old) != count:
            raise RuntimeError(f"isolation anchor changed: {relative}")
        after = before.replace(old, new)
        path.write_text(after)
        diffs.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                        fromfile=relative, tofile=relative + " (isolated copy)"))
    (destination / "isolation.patch").write_text("".join(diffs))
    return checkout, identity, support


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="new, nonexistent artifact directory")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug",
                        help="existing suites require DEBUG-only test hooks; Release is diagnostic only")
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="foil-tranche0-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    checkout, identity, support = prepare(output)
    command = ["xcodebuild", "test", "-scheme", "Foil", "-configuration", args.configuration,
               "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
               "-derivedDataPath", str(output / "DerivedData"),
               "-resultBundlePath", str(output / "baseline.xcresult"),
               "ENABLE_TESTABILITY=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=NO"]
    command += ["-only-testing:FoilTests/" + suite for suite in SUITES]
    metadata = {"command": command, "checkout": str(checkout), "bundle_identifier": identity,
                "application_support_namespace": support, "host": platform.platform(),
                "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "status": "prepared", "physical_cross_app_delivery": "NOT_RUN"}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Artifacts: {output}", flush=True)
    if args.prepare_only:
        return 0
    environment = dict(os.environ, RUN_LIVE_GROQ_TESTS="0", FOIL_DIAGNOSTICS="0")
    for key in ["GROQ_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"]:
        environment.pop(key, None)
    with (output / "xcodebuild.log").open("w") as log:
        try:
            result = subprocess.run(command, cwd=checkout, env=environment, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=1200, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    log_text = (output / "xcodebuild.log").read_text()
    metadata.update(status="passed" if code == 0 and "** TEST SUCCEEDED **" in log_text else "failed",
                    exit_code=code)
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f'Baseline: {metadata["status"]}; exit={code}; log={output / "xcodebuild.log"}', flush=True)
    return 0 if metadata["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
