#!/usr/bin/env python3
"""Contract/adapter gate for local corrections. Contains no production matcher.

Default invocation validates the corpus and proves deliberately broken matchers
are rejected. --adapter runs the same oracle against a future executable adapter.
Expected outputs and reasons are NEVER sent to that adapter.
"""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import platform
import random
import subprocess
import sys
import time
import unicodedata

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "local-corrections"


class GateError(Exception):
    pass


def check(condition, message):
    if not condition:
        raise GateError(message)


def exact_keys(value, keys, label):
    check(isinstance(value, dict) and set(value) == set(keys), f"{label}: unexpected fields")


def load_corpus(root=FIXTURES, split="all"):
    manifest = json.loads((root / "manifest.json").read_text())
    check(manifest["schema_version"] == 1, "unsupported manifest version")
    cases = []
    for name, metadata in manifest["files"].items():
        content = (root / name).read_bytes()
        check(hashlib.sha256(content).hexdigest() == metadata["sha256"], f"{name}: frozen corpus hash changed")
        rows = [json.loads(line) for line in content.decode("utf-8").splitlines()]
        check(len(rows) == metadata["count"], f"{name}: count changed")
        check(dict(Counter(row["category"] for row in rows)) == metadata["categories"], f"{name}: category coverage changed")
        for row in rows:
            exact_keys(row, ["id", "category", "input", "active_group", "enabled", "rules", "expected", "reason"], "fixture")
            check(isinstance(row["id"], str) and row["id"], "missing fixture ID")
            check(isinstance(row["enabled"], bool), f'{row["id"]}: invalid enable state')
            check(row["active_group"] is None or isinstance(row["active_group"], str), "invalid group")
            for field in ["input", "expected", "reason"]:
                check(isinstance(row[field], str), f'{row["id"]}: invalid {field}')
                row[field].encode("utf-8")  # Reject lone surrogates too.
            check(len(row["reason"].strip()) >= 15, f'{row["id"]}: missing explanation')
            check(len(row["input"].encode("utf-8")) <= 65536, "oversize corpus input")
            check(row["category"] in {"positive", "negative", "edge"}, "unknown category")
            if row["category"] == "positive":
                check(row["input"] != row["expected"], "positive case makes no change")
            if row["category"] == "negative" or not row["enabled"]:
                check(row["input"] == row["expected"], "negative/disabled case changes input")
            check(isinstance(row["rules"], list) and len(row["rules"]) <= 1000, "invalid rules")
            ids = set()
            aliases = []
            for rule in row["rules"]:
                exact_keys(rule, ["id", "source", "replacement", "group", "enabled", "case_sensitive"], "rule")
                check(isinstance(rule["id"], str) and rule["id"] and rule["id"] not in ids, "invalid/duplicate rule ID")
                ids.add(rule["id"])
                for field in ["source", "replacement"]:
                    check(isinstance(rule[field], str) and rule[field].strip() and 0 < len(rule[field]) <= 256, "invalid phrase")
                    rule[field].encode("utf-8")
                check(isinstance(rule["enabled"], bool) and isinstance(rule["case_sensitive"], bool), "invalid rule flags")
                check(rule["group"] is None or isinstance(rule["group"], str), "invalid rule scope")
                normalized = unicodedata.normalize("NFC", rule["source"])
                folded = normalized.translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"))
                for previous, previous_normalized, previous_folded in aliases:
                    if previous["group"] != rule["group"]:
                        continue
                    overlap = (previous_normalized == normalized if previous["case_sensitive"] and rule["case_sensitive"]
                               else previous_folded == folded)
                    check(not overlap, f'{row["id"]}: duplicate or ambiguous alias definitions')
                aliases.append((rule, normalized, folded))
            active = [r for r in row["rules"] if r["enabled"] and (r["group"] is None or r["group"] == row["active_group"])]
            if not active:
                check(row["input"] == row["expected"], f'{row["id"]}: inactive rules change text')
            if split == "all" or metadata["split"] == split:
                cases.append(row)
    check(len({row["id"] for row in cases}) == len(cases), "duplicate fixture IDs")
    return cases


def request_for(case):
    return {"schema_version": 1, "operation": "correct", **{
        key: case[key] for key in ["id", "input", "active_group", "enabled", "rules"]
    }}


def compare(cases, replies):
    check(len(replies) == len(cases), "missing or extra adapter replies")
    failures = []
    for case, reply in zip(cases, replies):
        exact_keys(reply, ["schema_version", "id", "text"], "adapter reply")
        check(type(reply["schema_version"]) is int and reply["schema_version"] == 1, "bad adapter version")
        check(reply["id"] == case["id"], "out-of-order/duplicate adapter reply ID")
        check(isinstance(reply["text"], str), "adapter text is not a string")
        if reply["text"].encode("utf-8") != case["expected"].encode("utf-8"):
            failures.append(case["id"])
    return failures


def run_adapter(command, cases, timeout=30):
    payload = "".join(json.dumps(request_for(case), ensure_ascii=False) + "\n" for case in cases)
    try:
        result = subprocess.run(command, input=payload, text=True, encoding="utf-8",
                                capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GateError(f"adapter failed: {type(error).__name__}") from error
    check(result.returncode == 0, f"adapter exited {result.returncode}")
    # No stderr dump: an adapter can accidentally emit private local state.
    try:
        replies = [json.loads(line) for line in result.stdout.splitlines()]
    except json.JSONDecodeError as error:
        raise GateError("adapter output is not JSONL") from error
    return compare(cases, replies)


def broken_replace(case, defect):
    """Deliberately WRONG implementations, only on targeted minimal witnesses.

    They are not a reference engine and are never used to generate expectations.
    Each witness isolates one defect (boundary, scope, enable, or rescanning).
    """
    if not case["enabled"] and defect != "disabled":
        return case["input"]
    rules = [r for r in case["rules"] if
             (r["enabled"] or defect == "disabled") and
             (r["group"] is None or r["group"] == case["active_group"] or defect == "scope")]
    text = case["input"]
    for rule in rules:
        text = text.replace(rule["source"], rule["replacement"])
    return text


def mutation_receipt(cases):
    witnesses = {"substring": "N01", "scope": "N21", "disabled": "N31", "recursive": "E01"}
    indexed = {case["id"]: case for case in cases}
    receipt = {}
    for defect, fixture_id in witnesses.items():
        case = indexed[fixture_id]
        reply = {"schema_version": 1, "id": fixture_id, "text": broken_replace(case, defect)}
        failed = compare([case], [reply])
        check(failed == [fixture_id], f"mutant survived: {defect}")
        receipt[defect] = {"rejected_by": fixture_id, "reason": case["reason"]}
    return receipt


def percentile(samples, quantile):
    return sorted(samples)[max(0, math.ceil(len(samples) * quantile) - 1)]


def benchmark_workloads():
    workloads = {}
    for name, count, size in [("normal", 500, 10240), ("maximum", 1000, 65536)]:
        rng = random.Random(20260914)
        rules = [{"id": f"r{i:04}", "source": f"alias{i:04}", "replacement": f"Term{i:04}",
                  "group": None, "enabled": True, "case_sensitive": True} for i in range(count)]
        tokens, expected = [], []
        remaining = size
        while remaining >= 10:
            index = rng.randrange(count)
            # Each token is exactly ten ASCII bytes. Includes shared prefixes and
            # known misses; expected text comes from construction, not a matcher.
            hit = rng.randrange(4) != 0
            tokens.append(f"alias{index:04} " if hit else f"other{index:04} ")
            expected.append(f"Term{index:04} " if hit else f"other{index:04} ")
            remaining -= 10
        tokens.append(" " * remaining)
        expected.append(" " * remaining)
        text = "".join(tokens)
        workloads[name] = {
            "request": {"schema_version": 1, "operation": "correct", "id": name,
                        "input": text, "active_group": None, "enabled": True, "rules": rules},
            "expected_sha256": hashlib.sha256("".join(expected).encode()).hexdigest()
        }
    return workloads


def validate_benchmark(report):
    """Validate a future in-process Release adapter's raw timing samples.

    Process-start/IPC timing is not accepted as correction latency. The adapter
    must time compilation and the real controller separately and check its output.
    """
    exact_keys(report, ["schema_version", "build_configuration", "boundary", "hardware",
                        "os", "commit", "seed", "scenarios"], "benchmark report")
    check(report["schema_version"] == 1, "bad benchmark version")
    check(report["build_configuration"] == "Release", "benchmark must use Release")
    check(report["boundary"] == "TranscriptionController.processTranscriptOrRaw", "missing real controller boundary")
    for field in ["hardware", "os", "commit"]:
        check(isinstance(report[field], str) and report[field].strip(), f"missing benchmark {field}")
    check(report["seed"] == 20260914, "benchmark seed changed")
    check(set(report["scenarios"]) == {"normal", "maximum"}, "missing benchmark scenario")
    result = {}
    workloads = benchmark_workloads()
    for name, rule_count, input_bytes, p95_limit, p99_limit in [
        ("normal", 500, 10240, 10, 25), ("maximum", 1000, 65536, 100, 100)
    ]:
        scenario = report["scenarios"][name]
        exact_keys(scenario, ["rule_count", "input_bytes", "output_sha256", "cold_compile_ms",
                              "warm_controller_ms", "cold_controller_ms"], name)
        check(scenario["rule_count"] == rule_count and scenario["input_bytes"] == input_bytes, "wrong workload size")
        check(scenario["output_sha256"] == workloads[name]["expected_sha256"], "benchmark output mismatch")
        for key, count in [("cold_compile_ms", 50), ("cold_controller_ms", 50), ("warm_controller_ms", 1000)]:
            samples = scenario[key]
            check(isinstance(samples, list) and len(samples) == count, f"{name}: wrong {key} sample count")
            check(all(type(x) in (int, float) and math.isfinite(x) and x >= 0 for x in samples), "invalid timing sample")
        warm = scenario["warm_controller_ms"]
        p95, p99 = percentile(warm, .95), percentile(warm, .99)
        check(p95 <= p95_limit and p99 <= p99_limit, f"{name}: latency budget exceeded")
        result[name] = {"p95_ms": p95, "p99_ms": p99,
                        "cold_compile_p95_ms": percentile(scenario["cold_compile_ms"], .95),
                        "cold_controller_p95_ms": percentile(scenario["cold_controller_ms"], .95)}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--split", choices=["development", "holdout", "all"], default="development")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--benchmark-report", type=Path)
    parser.add_argument("--write-benchmark-workloads", type=Path)
    parser.add_argument("--adapter", nargs=argparse.REMAINDER, help="executable and arguments (last option)")
    args = parser.parse_args()
    started = time.monotonic()
    try:
        cases = load_corpus(split=args.split)
        receipt = {"kind": "test_foundation_only", "fixture_count": len(cases),
                   "split": args.split, "mutants": mutation_receipt(load_corpus(split="development")),
                   "host": platform.platform(), "production_engine": "NOT_RUN"}
        if args.write_benchmark_workloads:
            # Only requests are handed to an implementation; digest oracle stays here.
            requests = {name: data["request"] for name, data in benchmark_workloads().items()}
            args.write_benchmark_workloads.write_text(json.dumps(requests, indent=2) + "\n")
        if args.adapter is not None:
            check(bool(args.adapter), "--adapter needs an executable")
            failures = run_adapter(args.adapter, cases)
            receipt.update(kind="production_engine_gate", production_engine="adapter_exercised", failures=failures)
            check(not failures, f"adapter failed {len(failures)} cases: {', '.join(failures[:20])}")
        if args.benchmark_report:
            receipt["benchmark"] = validate_benchmark(json.loads(args.benchmark_report.read_text()))
        receipt["harness_elapsed_seconds"] = time.monotonic() - started
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, indent=2))
        return 0
    except (GateError, ValueError, KeyError, TypeError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
