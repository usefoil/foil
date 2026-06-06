#!/usr/bin/env python3
"""Create sanitized evidence from iOS WebDriverAgent source dumps.

This helper is intentionally narrow: it reads WDA `/source` JSON or raw XML,
checks for expected accessibility identifiers or target text counts, and emits a
receipt that does not include raw transcript or host-app content.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def short_hash(value: str) -> str:
    return sha256_text(value)[:16]


def load_wda_source(path: Path) -> str:
    raw = path.read_text(encoding="utf-8")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return raw

    value = payload.get("value") if isinstance(payload, dict) else None
    if isinstance(value, str):
        return value
    raise ValueError(f"{path} does not look like WDA source JSON or raw XML")


def xml_nodes(source: str) -> list[dict[str, str]]:
    try:
        root = ET.fromstring(source)
    except ET.ParseError as error:
        raise ValueError(f"WDA source XML could not be parsed: {error}") from error

    return [dict(element.attrib) for element in root.iter()]


def has_identifier(nodes: list[dict[str, str]], identifier: str) -> bool:
    return any(node.get("name") == identifier for node in nodes)


def identifier_attribute_matches(
    nodes: list[dict[str, str]],
    identifier: str,
    attribute: str,
    expected: str,
) -> tuple[bool, list[str]]:
    values = [node.get(attribute, "") for node in nodes if node.get("name") == identifier]
    return any(value == expected for value in values), values


def value_count(nodes: list[dict[str, str]], text: str) -> int:
    needle = text.casefold()
    return sum(node.get("value", "").casefold().count(needle) for node in nodes)


def value_contains(nodes: list[dict[str, str]], text: str) -> bool:
    return value_count(nodes, text) > 0


def accessible_text_contains(nodes: list[dict[str, str]], text: str) -> bool:
    needle = text.casefold()
    return any(
        needle in node.get(attribute, "").casefold()
        for node in nodes
        for attribute in ("name", "label", "value")
    )


def parse_expected_count(raw: str) -> tuple[str, int]:
    text, separator, count_text = raw.rpartition("=")
    if not separator or not text:
        raise argparse.ArgumentTypeError("expected TEXT=COUNT")
    try:
        expected = int(count_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError("COUNT must be an integer") from error
    return text, expected


def parse_identifier_state(raw: str) -> tuple[str, str, str]:
    left, separator, expected = raw.rpartition("=")
    if not separator or not left or not expected:
        raise argparse.ArgumentTypeError("expected IDENTIFIER.ATTRIBUTE=VALUE")
    identifier, dot, attribute = left.rpartition(".")
    if not dot or not identifier or not attribute:
        raise argparse.ArgumentTypeError("expected IDENTIFIER.ATTRIBUTE=VALUE")
    return identifier, attribute, expected


def snapshot_summary(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    transcript = payload.get("transcript")
    message = payload.get("message")
    summary: dict[str, Any] = {
        "file": path.name,
        "sha256": sha256_text(path.read_text(encoding="utf-8")),
        "phase": payload.get("phase"),
        "hasTranscript": bool(transcript),
    }
    if isinstance(message, str):
        summary["messageHash"] = short_hash(message)
    if isinstance(transcript, str) and transcript:
        summary["transcriptHash"] = short_hash(transcript)
    return summary


def storage_report_summary(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    summary: dict[str, Any] = {
        "file": path.name,
        "sha256": sha256_text(path.read_text(encoding="utf-8")),
        "operation": payload.get("operation"),
        "phase": payload.get("phase"),
        "hasTranscript": payload.get("hasTranscript"),
        "canonicalWriteSucceeded": payload.get("canonicalWriteSucceeded"),
        "canonicalVerificationPhase": payload.get("canonicalVerificationPhase"),
        "canonicalVerificationHasTranscript": payload.get("canonicalVerificationHasTranscript"),
        "defaultsWriteAttempted": payload.get("defaultsWriteAttempted"),
    }
    if payload.get("canonicalWriteError"):
        summary["canonicalWriteErrorHash"] = short_hash(str(payload["canonicalWriteError"]))
    return summary


def add_check(checks: list[dict[str, Any]], check: dict[str, Any]) -> None:
    check["passed"] = bool(check["passed"])
    checks.append(check)


def build_receipt(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    source = load_wda_source(args.source)
    nodes = xml_nodes(source)
    checks: list[dict[str, Any]] = []

    for identifier in args.require_identifier:
        present = has_identifier(nodes, identifier)
        add_check(
            checks,
            {
                "kind": "requireIdentifier",
                "identifier": identifier,
                "present": present,
                "passed": present,
            },
        )

    for identifier in args.forbid_identifier:
        present = has_identifier(nodes, identifier)
        add_check(
            checks,
            {
                "kind": "forbidIdentifier",
                "identifier": identifier,
                "present": present,
                "passed": not present,
            },
        )

    for identifier, attribute, expected in args.expect_identifier_state:
        matches, observed = identifier_attribute_matches(nodes, identifier, attribute, expected)
        add_check(
            checks,
            {
                "kind": "expectIdentifierState",
                "identifier": identifier,
                "attribute": attribute,
                "expected": expected,
                "observed": sorted(set(observed)),
                "passed": matches,
            },
        )

    for text in args.require_value:
        present = value_contains(nodes, text)
        add_check(
            checks,
            {
                "kind": "requireValueText",
                "textSha256": short_hash(text),
                "textLength": len(text),
                "present": present,
                "passed": present,
            },
        )

    for text in args.forbid_value:
        present = value_contains(nodes, text)
        add_check(
            checks,
            {
                "kind": "forbidValueText",
                "textSha256": short_hash(text),
                "textLength": len(text),
                "present": present,
                "passed": not present,
            },
        )

    for text in args.require_text:
        present = accessible_text_contains(nodes, text)
        add_check(
            checks,
            {
                "kind": "requireAccessibleText",
                "textSha256": short_hash(text),
                "textLength": len(text),
                "present": present,
                "passed": present,
            },
        )

    for text in args.forbid_text:
        present = accessible_text_contains(nodes, text)
        add_check(
            checks,
            {
                "kind": "forbidAccessibleText",
                "textSha256": short_hash(text),
                "textLength": len(text),
                "present": present,
                "passed": not present,
            },
        )

    for text, expected in args.expect_value_count:
        actual = value_count(nodes, text)
        add_check(
            checks,
            {
                "kind": "expectValueTextCount",
                "textSha256": short_hash(text),
                "textLength": len(text),
                "expected": expected,
                "actual": actual,
                "passed": actual == expected,
            },
        )

    app_group: dict[str, Any] = {}
    if args.app_group_snapshot:
        app_group["snapshot"] = snapshot_summary(args.app_group_snapshot)
    if args.storage_report:
        app_group["storageReport"] = storage_report_summary(args.storage_report)

    passed = all(check["passed"] for check in checks)
    receipt: dict[str, Any] = {
        "schema": "foil.iosPhysicalWdaEvidence.v1",
        "target": args.target,
        "source": {
            "file": args.source.name,
            "sha256": sha256_text(source),
            "nodeCount": len(nodes),
        },
        "checks": checks,
        "appGroup": app_group,
        "passed": passed,
    }
    return receipt, passed


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit sanitized Foil iOS physical-device evidence from WDA source JSON."
    )
    parser.add_argument("--source", required=True, type=Path, help="WDA /source JSON or raw XML path.")
    parser.add_argument(
        "--target",
        required=True,
        help="Sterile target row name, for example notes or safari-fixture.",
    )
    parser.add_argument(
        "--require-identifier",
        action="append",
        default=[],
        help="Accessibility identifier that must be present.",
    )
    parser.add_argument(
        "--forbid-identifier",
        action="append",
        default=[],
        help="Accessibility identifier that must be absent.",
    )
    parser.add_argument(
        "--expect-identifier-state",
        action="append",
        default=[],
        type=parse_identifier_state,
        metavar="IDENTIFIER.ATTRIBUTE=VALUE",
        help="Accessibility identifier attribute expectation, for example foil-keyboard-insert-latest.enabled=false.",
    )
    parser.add_argument(
        "--require-value",
        action="append",
        default=[],
        help="Private text that must appear in a value attribute; output is hashed.",
    )
    parser.add_argument(
        "--forbid-value",
        action="append",
        default=[],
        help="Private text that must be absent from value attributes; output is hashed.",
    )
    parser.add_argument(
        "--require-text",
        action="append",
        default=[],
        help="Private text that must appear in name, label, or value attributes; output is hashed.",
    )
    parser.add_argument(
        "--forbid-text",
        action="append",
        default=[],
        help="Private text that must be absent from name, label, and value attributes; output is hashed.",
    )
    parser.add_argument(
        "--expect-value-count",
        action="append",
        default=[],
        type=parse_expected_count,
        metavar="TEXT=COUNT",
        help="Private text count in value attributes; output is hashed.",
    )
    parser.add_argument(
        "--app-group-snapshot",
        type=Path,
        help="Optional copied foil-keyboard-snapshot.json.",
    )
    parser.add_argument(
        "--storage-report",
        type=Path,
        help="Optional copied foil keyboard storage report JSON.",
    )
    parser.add_argument("--write-json", type=Path, help="Write receipt to this path instead of stdout.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
        receipt, passed = build_receipt(args)
    except Exception as error:  # noqa: BLE001 - command-line tool should report any input failure.
        print(f"error: {error}", file=sys.stderr)
        return 2

    encoded = json.dumps(receipt, indent=2, sort_keys=True)
    if args.write_json:
        args.write_json.write_text(encoded + "\n", encoding="utf-8")
    else:
        print(encoded)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
