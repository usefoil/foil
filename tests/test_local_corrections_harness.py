"""Tests the gate itself, not the unimplemented local correction engine."""
import json
from pathlib import Path
import shutil
import hashlib
import importlib.util
import subprocess
import sys
import tempfile
import unittest

import local_corrections_harness as gate


class GateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = gate.load_corpus()

    def reply(self, case, **changes):
        return dict(schema_version=1, id=case["id"], text=case["expected"], **changes)

    def test_frozen_coverage_and_reserved_split(self):
        self.assertEqual(len(gate.load_corpus(split="development")), 120)
        self.assertEqual(len(gate.load_corpus(split="holdout")), 30)
        self.assertEqual(len(self.cases), 150)

    def test_request_cannot_leak_expected_output_or_rationale(self):
        for case in self.cases:
            request = gate.request_for(case)
            self.assertEqual(set(request), {"schema_version", "operation", "id", "input", "active_group", "enabled", "rules"})

    def test_changed_corpus_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "fixtures"
            shutil.copytree(gate.FIXTURES, root)
            with (root / "development.jsonl").open("a") as file:
                file.write("\n")
            with self.assertRaisesRegex(gate.GateError, "hash changed"):
                gate.load_corpus(root)

    def test_refrozen_corpus_still_rejects_invalid_rule_contracts(self):
        for mutation in ["blank", "duplicate", "wrong-scope"]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "fixtures"
                shutil.copytree(gate.FIXTURES, root)
                path = root / "development.jsonl"
                rows = [json.loads(line) for line in path.read_text().splitlines()]
                if mutation == "blank":
                    rows[0]["rules"][0]["source"] = " "
                elif mutation == "duplicate":
                    rows[0]["rules"].append(dict(rows[0]["rules"][0], id="other"))
                else:
                    rows[0]["active_group"] = "wrong"
                path.write_text("".join(json.dumps(row) + "\n" for row in rows))
                manifest_path = root / "manifest.json"
                manifest = json.loads(manifest_path.read_text())
                manifest["files"][path.name]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                manifest_path.write_text(json.dumps(manifest))
                with self.subTest(mutation=mutation), self.assertRaises(gate.GateError):
                    gate.load_corpus(root)

    def test_all_four_defects_have_minimal_witnesses(self):
        result = gate.mutation_receipt(self.cases)
        self.assertEqual(set(result), {"substring", "scope", "disabled", "recursive"})

    def test_comparator_accepts_exact_bytes(self):
        # Tests comparison plumbing only; this is not passed off as engine proof.
        self.assertEqual(gate.compare(self.cases, [self.reply(c) for c in self.cases]), [])

    def test_noop_adapter_fails_positive_cases(self):
        command = [sys.executable, "-c", "import sys,json\nfor line in sys.stdin:\n r=json.loads(line); print(json.dumps(dict(schema_version=1,id=r['id'],text=r['input'])))"]
        failures = gate.run_adapter(command, self.cases)
        self.assertTrue(all(c["id"] in failures for c in self.cases if c["category"] == "positive"))
        self.assertGreaterEqual(len(failures), 50)

    def test_raw_unicode_normalization_is_a_failure(self):
        case = {"id": "bytes", "expected": "Cafe\u0301"}
        self.assertEqual(gate.compare([case], [dict(schema_version=1, id="bytes", text="Café")]), ["bytes"])

    def test_missing_extra_duplicate_or_reordered_output_fails(self):
        cases = self.cases[:2]
        replies = [self.reply(c) for c in cases]
        for broken in [[], replies[:1], replies + replies, replies[::-1], [replies[0], replies[0]]]:
            with self.subTest(broken=broken), self.assertRaises(gate.GateError):
                gate.compare(cases, broken)

    def test_wrong_reply_shape_or_type_fails(self):
        case = self.cases[0]
        for reply in [{}, dict(schema_version=True, id=case["id"], text=case["expected"]),
                      dict(schema_version=2, id=case["id"], text=case["expected"]),
                      dict(schema_version=1, id=case["id"], text=None),
                      dict(schema_version=1, id=case["id"], text=case["expected"], debug="extra")]:
            with self.subTest(reply=reply), self.assertRaises(gate.GateError):
                gate.compare([case], [reply])

    def test_adapter_failure_garbage_and_timeout_are_not_passes(self):
        for code in ["raise SystemExit(9)", "print('not JSON')", "print('{}')"]:
            with self.subTest(code=code), self.assertRaises(gate.GateError):
                gate.run_adapter([sys.executable, "-c", code], self.cases[:1])
        with self.assertRaisesRegex(gate.GateError, "TimeoutExpired"):
            gate.run_adapter([sys.executable, "-c", "import time; time.sleep(10)"], self.cases[:1], timeout=.05)

    def benchmark_report(self):
        report = dict(schema_version=1, build_configuration="Release",
                      boundary="TranscriptionController.processTranscriptOrRaw",
                      hardware="test-only", os="test-only", commit="test-only", seed=20260914, scenarios={})
        for name, count, size in [("normal", 500, 10240), ("maximum", 1000, 65536)]:
            report["scenarios"][name] = dict(rule_count=count, input_bytes=size,
                output_sha256=gate.benchmark_workloads()[name]["expected_sha256"],
                cold_compile_ms=[1.] * 50, cold_controller_ms=[2.] * 50, warm_controller_ms=[1.] * 1000)
        return report

    def test_benchmark_workloads_are_fixed_and_correct_size(self):
        first = gate.benchmark_workloads()
        self.assertEqual(first, gate.benchmark_workloads())
        for name, count, size in [("normal", 500, 10240), ("maximum", 1000, 65536)]:
            request = first[name]["request"]
            self.assertEqual(len(request["rules"]), count)
            self.assertEqual(len(request["input"].encode()), size)
            self.assertNotIn("expected_sha256", request)

    def test_benchmark_validator_accepts_fixture_report_only_as_plumbing(self):
        result = gate.validate_benchmark(self.benchmark_report())
        self.assertEqual(result["normal"]["p99_ms"], 1)

    def test_benchmark_rejects_fast_noop_and_missing_samples(self):
        for field, value in [("output_sha256", "wrong"), ("warm_controller_ms", []),
                             ("cold_compile_ms", [1.] * 49), ("rule_count", 499),
                             ("input_bytes", 10000), ("warm_controller_ms", [float('nan')] * 1000),
                             ("warm_controller_ms", [-1.] * 1000),
                             ("warm_controller_ms", [True] * 1000)]:
            report = self.benchmark_report()
            report["scenarios"]["normal"][field] = value
            with self.subTest(field=field), self.assertRaises(gate.GateError):
                gate.validate_benchmark(report)

    def test_benchmark_catches_tail_regression_despite_fast_median(self):
        report = self.benchmark_report()
        report["scenarios"]["normal"]["warm_controller_ms"] = [1.] * 980 + [26.] * 20
        with self.assertRaisesRegex(gate.GateError, "budget exceeded"):
            gate.validate_benchmark(report)

    def test_benchmark_rejects_wrong_boundary_configuration_or_seed(self):
        for field, value in [("boundary", "IPC"), ("build_configuration", "Debug"), ("seed", 7)]:
            report = self.benchmark_report()
            report[field] = value
            with self.subTest(field=field), self.assertRaises(gate.GateError):
                gate.validate_benchmark(report)

    def test_percentiles_use_nearest_rank_without_averaging_out_tail(self):
        self.assertEqual(gate.percentile(list(range(1, 101)), .95), 95)
        self.assertEqual(gate.percentile(list(range(1, 101)), .99), 99)

    def test_baseline_copy_is_pinned_and_isolates_only_storage_identity(self):
        root = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("baseline", root / "scripts/run-local-corrections-baseline.py")
        baseline = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(baseline)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            checkout, identity, support = baseline.prepare(output)
            self.assertTrue(identity.startswith("com.neonwatty.Foil.Tranche0QA."))
            self.assertNotIn(identity, {"com.neonwatty.Foil", "com.neonwatty.Foil.Dev"})
            self.assertTrue(support.startswith("Foil Tranche0 QA "))
            project = (checkout / "Foil.xcodeproj/project.pbxproj").read_text()
            self.assertNotIn("FOIL_APP_BUNDLE_IDENTIFIER = com.neonwatty.Foil;", project)
            self.assertEqual(project.count(f"FOIL_APP_BUNDLE_IDENTIFIER = {identity};"), 2)
            self.assertIn(support, (checkout / "Foil/AppBrand.swift").read_text())
            self.assertIn("false // Isolated baseline host", (checkout / "Foil/SparkleUpdater.swift").read_text())
            self.assertFalse((checkout / "Foil/LocalCorrectionEngine.swift").exists())
            self.assertFalse((checkout / "Foil/LocalCorrectionStore.swift").exists())
            tracked = subprocess.check_output(
                ["git", "ls-tree", "-r", "--name-only", baseline.BASELINE_COMMIT, "--", "Foil", "FoilTests"],
                cwd=root,
                text=True,
            ).splitlines()
            changed = {
                relative
                for relative in tracked
                if subprocess.check_output(
                    ["git", "show", f"{baseline.BASELINE_COMMIT}:{relative}"], cwd=root
                ) != (checkout / relative).read_bytes()
            }
            self.assertEqual(changed, {"Foil/AppBrand.swift", "Foil/SparkleUpdater.swift"})


if __name__ == "__main__":
    unittest.main()
