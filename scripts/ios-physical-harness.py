#!/usr/bin/env python3
"""Privacy-safe harness for Foil iOS physical-device checks.

The harness wraps the proven WebDriverAgent and App Group flows used by the
physical iPhone GoalBuddy boards. It prints sanitized JSON receipts and avoids
printing transcript bodies or raw WDA source.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEVICE_ID = "5320F5AD-2A71-50AC-94FE-207B544B6247"
DEVICE_NAME = "iPhone-preview"
WDA_DESTINATION_ID = "00008030-001A0C980A33C02E"
TEAM_ID = "B3A6AN2HA4"
WDA_BUNDLE_ID = "com.neonwatty.WebDriverAgentRunner"
APP_GROUP_ID = "group.com.neonwatty.FoilIOS"
SNAPSHOT_PATH = "Library/foil-keyboard-snapshot.json"
WDA_URL = "http://127.0.0.1:8100"
WDA_PROJECT = Path(
    "/Users/neonwatty/.appium/node_modules/appium-xcuitest-driver/"
    "node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj"
)
REPO_ROOT = Path(__file__).resolve().parents[1]
EVIDENCE_HELPER = REPO_ROOT / "scripts" / "ios-physical-wda-evidence.py"
SWIFT_DATE_OFFSET = 978_307_200


class HarnessError(RuntimeError):
    """Expected command-line failure."""


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def short_hash(value: str) -> str:
    return sha256_text(value)[:16]


def write_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def run_command(argv: list[str], *, input_text: str | None = None, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def http_json(method: str, url: str, payload: dict[str, Any] | None = None, timeout: int = 5) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8")
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as error:
        raise HarnessError(f"{url} did not return JSON") from error
    if isinstance(decoded, dict):
        return decoded
    raise HarnessError(f"{url} returned non-object JSON")


def http_text(method: str, url: str, payload: dict[str, Any] | None = None, timeout: int = 10) -> str:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def wda_ready(wda_url: str) -> tuple[bool, dict[str, Any]]:
    try:
        payload = http_json("GET", f"{wda_url.rstrip('/')}/status", timeout=2)
    except (HarnessError, urllib.error.URLError, TimeoutError, OSError) as error:
        return False, {"error": type(error).__name__}
    return True, {
        "valueKeys": sorted(payload.get("value", {}).keys()) if isinstance(payload.get("value"), dict) else [],
        "state": payload.get("state"),
    }


def parse_device_line(output: str, device_id: str) -> dict[str, Any]:
    for line in output.splitlines():
        if device_id in line:
            parts = [part for part in line.split("   ") if part.strip()]
            return {
                "present": True,
                "rawLineSha256": short_hash(line),
                "looksAvailable": "available" in line,
            }
    return {"present": False, "rawLineSha256": None, "looksAvailable": False}


def snapshot_payload(phase: str, transcript: str | None, message: str) -> dict[str, Any]:
    return {
        "phase": phase,
        "transcript": transcript,
        "message": message,
        "updatedAt": time.time() - SWIFT_DATE_OFFSET,
    }


def summarize_snapshot_path(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8")
    payload = json.loads(raw)
    transcript = payload.get("transcript")
    message = payload.get("message")
    summary: dict[str, Any] = {
        "file": path.name,
        "sha256": sha256_text(raw),
        "phase": payload.get("phase"),
        "hasTranscript": bool(transcript),
    }
    if isinstance(message, str):
        summary["messageHash"] = short_hash(message)
    if isinstance(transcript, str) and transcript:
        summary["transcriptHash"] = short_hash(transcript)
        summary["transcriptLength"] = len(transcript)
    return summary


def copy_snapshot_to_device(source: Path, device_id: str) -> subprocess.CompletedProcess[str]:
    return run_command(
        [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "to",
            "--device",
            device_id,
            "--domain-type",
            "appGroupDataContainer",
            "--domain-identifier",
            APP_GROUP_ID,
            "--source",
            str(source),
            "--destination",
            SNAPSHOT_PATH,
        ],
        timeout=60,
    )


def copy_snapshot_from_device(destination: Path, device_id: str) -> subprocess.CompletedProcess[str]:
    return run_command(
        [
            "xcrun",
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            device_id,
            "--domain-type",
            "appGroupDataContainer",
            "--domain-identifier",
            APP_GROUP_ID,
            "--source",
            SNAPSHOT_PATH,
            "--destination",
            str(destination),
        ],
        timeout=60,
    )


def sanitized_process_result(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    return {
        "returncode": result.returncode,
        "stdoutSha256": short_hash(result.stdout) if result.stdout else None,
        "stderrSha256": short_hash(result.stderr) if result.stderr else None,
        "stdoutBytes": len(result.stdout.encode("utf-8")),
        "stderrBytes": len(result.stderr.encode("utf-8")),
    }


def wda_command_lines() -> list[str]:
    return [
        "xcodebuild \\",
        f"  -project {WDA_PROJECT} \\",
        "  -scheme WebDriverAgentRunner-nodebug \\",
        f"  -destination 'id={WDA_DESTINATION_ID}' \\",
        "  -configuration Debug \\",
        f"  DEVELOPMENT_TEAM={TEAM_ID} \\",
        "  CODE_SIGN_STYLE=Automatic \\",
        f"  PRODUCT_BUNDLE_IDENTIFIER={WDA_BUNDLE_ID} \\",
        "  -allowProvisioningUpdates \\",
        "  test 2>&1 | tee /tmp/foil-ios-wda.log",
    ]


def cmd_status(args: argparse.Namespace) -> int:
    devicectl = run_command(["xcrun", "devicectl", "list", "devices"], timeout=20)
    ready, wda_payload = wda_ready(args.wda_url)
    payload = {
        "schema": "foil.iosPhysicalHarness.status.v1",
        "device": {
            "name": DEVICE_NAME,
            "identifier": args.device_id,
            "devicectlReturncode": devicectl.returncode,
            "summary": parse_device_line(devicectl.stdout, args.device_id) if devicectl.returncode == 0 else {"present": False},
        },
        "wda": {
            "url": args.wda_url,
            "ready": ready,
            "status": wda_payload,
            "projectPresent": WDA_PROJECT.exists(),
        },
        "iproxy": {
            "path": shutil.which("iproxy"),
            "present": shutil.which("iproxy") is not None,
        },
    }
    write_json(payload)
    return 0


def cmd_wda_command(_: argparse.Namespace) -> int:
    print("\n".join(wda_command_lines()))
    return 0


def cmd_session(args: argparse.Namespace) -> int:
    payload = {
        "capabilities": {
            "alwaysMatch": {
                "platformName": "iOS",
                "automationName": "XCUITest",
            }
        }
    }
    response = http_json("POST", f"{args.wda_url.rstrip('/')}/session", payload=payload, timeout=10)
    value = response.get("value")
    session_id = None
    if isinstance(value, dict):
        session_id = value.get("sessionId") or response.get("sessionId")
    elif isinstance(response.get("sessionId"), str):
        session_id = response.get("sessionId")
    if not session_id:
        raise HarnessError("WDA session response did not include a session id")
    write_json(
        {
            "schema": "foil.iosPhysicalHarness.session.v1",
            "sessionId": session_id,
            "wdaUrl": args.wda_url,
            "bundleIdProvided": False,
        }
    )
    return 0


def cmd_delete_session(args: argparse.Namespace) -> int:
    try:
        response = http_json("DELETE", f"{args.wda_url.rstrip('/')}/session/{args.session_id}", timeout=10)
        deleted = True
    except (HarnessError, urllib.error.URLError, TimeoutError, OSError) as error:
        response = {"error": type(error).__name__}
        deleted = False
    write_json(
        {
            "schema": "foil.iosPhysicalHarness.deleteSession.v1",
            "sessionId": args.session_id,
            "deleted": deleted,
            "response": response,
        }
    )
    return 0 if deleted else 1


def cmd_fetch_source(args: argparse.Namespace) -> int:
    raw = http_text("GET", f"{args.wda_url.rstrip('/')}/session/{args.session_id}/source", timeout=15)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(raw, encoding="utf-8")
    write_json(
        {
            "schema": "foil.iosPhysicalHarness.fetchSource.v1",
            "sessionId": args.session_id,
            "output": str(args.output),
            "sha256": sha256_text(raw),
            "bytes": len(raw.encode("utf-8")),
            "printedRawSource": False,
        }
    )
    return 0


def write_and_copy_snapshot(args: argparse.Namespace, payload: dict[str, Any]) -> int:
    with tempfile.TemporaryDirectory(prefix="foil-ios-harness-") as temp_dir:
        temp = Path(temp_dir)
        source = temp / "foil-keyboard-snapshot.json"
        readback = temp / "foil-keyboard-snapshot-readback.json"
        source.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        copy_to = copy_snapshot_to_device(source, args.device_id)
        receipt: dict[str, Any] = {
            "schema": "foil.iosPhysicalHarness.appGroupWrite.v1",
            "operation": args.command_name,
            "deviceId": args.device_id,
            "appGroup": APP_GROUP_ID,
            "destination": SNAPSHOT_PATH,
            "copyTo": sanitized_process_result(copy_to),
            "writtenSummary": summarize_snapshot_path(source),
        }
        if copy_to.returncode == 0:
            copy_from = copy_snapshot_from_device(readback, args.device_id)
            receipt["copyFrom"] = sanitized_process_result(copy_from)
            if copy_from.returncode == 0 and readback.exists():
                receipt["readbackSummary"] = summarize_snapshot_path(readback)
        write_json(receipt)
        return 0 if copy_to.returncode == 0 and receipt.get("copyFrom", {}).get("returncode") == 0 else 1


def cmd_stage_transcript(args: argparse.Namespace) -> int:
    transcript = args.transcript_file.read_text(encoding="utf-8") if args.transcript_file else args.transcript
    if transcript is None:
        raise HarnessError("stage-transcript requires --transcript or --transcript-file")
    args.command_name = "stage-transcript"
    return write_and_copy_snapshot(args, snapshot_payload("complete", transcript, args.message))


def cmd_reset_transcript(args: argparse.Namespace) -> int:
    args.command_name = "reset-transcript"
    return write_and_copy_snapshot(args, snapshot_payload("idle", None, args.message))


def cmd_app_group_summary(args: argparse.Namespace) -> int:
    with tempfile.TemporaryDirectory(prefix="foil-ios-harness-") as temp_dir:
        destination = Path(temp_dir) / "foil-keyboard-snapshot.json"
        copy_from = copy_snapshot_from_device(destination, args.device_id)
        receipt: dict[str, Any] = {
            "schema": "foil.iosPhysicalHarness.appGroupSummary.v1",
            "deviceId": args.device_id,
            "appGroup": APP_GROUP_ID,
            "source": SNAPSHOT_PATH,
            "copyFrom": sanitized_process_result(copy_from),
        }
        if copy_from.returncode == 0 and destination.exists():
            receipt["summary"] = summarize_snapshot_path(destination)
        write_json(receipt)
        return 0 if copy_from.returncode == 0 else 1


def cmd_receipt(args: argparse.Namespace) -> int:
    helper_args = [
        sys.executable,
        str(EVIDENCE_HELPER),
        "--source",
        str(args.source),
        "--target",
        args.target,
    ]
    for option_name, values in [
        ("--require-identifier", args.require_identifier),
        ("--forbid-identifier", args.forbid_identifier),
        ("--expect-identifier-state", args.expect_identifier_state),
        ("--require-value", args.require_value),
        ("--forbid-value", args.forbid_value),
        ("--require-text", args.require_text),
        ("--forbid-text", args.forbid_text),
        ("--expect-value-count", args.expect_value_count),
    ]:
        for value in values:
            helper_args.extend([option_name, value])
    if args.app_group_snapshot:
        helper_args.extend(["--app-group-snapshot", str(args.app_group_snapshot)])
    if args.storage_report:
        helper_args.extend(["--storage-report", str(args.storage_report)])
    if args.write_json:
        helper_args.extend(["--write-json", str(args.write_json)])
    result = run_command(helper_args, timeout=30)
    if args.write_json:
        write_json(
            {
                "schema": "foil.iosPhysicalHarness.receipt.v1",
                "helper": str(EVIDENCE_HELPER),
                "returncode": result.returncode,
                "writeJson": str(args.write_json),
                "stdoutBytes": len(result.stdout.encode("utf-8")),
                "stderrSha256": short_hash(result.stderr) if result.stderr else None,
            }
        )
    else:
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
    return result.returncode


def run_helper_for_self_test(source: Path, *extra_args: str) -> subprocess.CompletedProcess[str]:
    return run_command(
        [
            sys.executable,
            str(EVIDENCE_HELPER),
            "--source",
            str(source),
            "--target",
            "self-test",
            *extra_args,
        ],
        timeout=30,
    )


def cmd_self_test(_: argparse.Namespace) -> int:
    secret_phrase = "Foil harness self test phrase"
    raw_xml = (
        '<AppiumAUT>'
        '<XCUIElementTypeOther name="foil-keyboard-root" enabled="true" />'
        '<XCUIElementTypeButton name="foil-keyboard-insert-latest" enabled="false" />'
        f'<XCUIElementTypeTextView value="{secret_phrase}" />'
        "</AppiumAUT>"
    )
    with tempfile.TemporaryDirectory(prefix="foil-ios-harness-self-test-") as temp_dir:
        temp = Path(temp_dir)
        source = temp / "source.json"
        source.write_text(json.dumps({"value": raw_xml}), encoding="utf-8")
        passing = run_helper_for_self_test(
            source,
            "--require-identifier",
            "foil-keyboard-root",
            "--expect-identifier-state",
            "foil-keyboard-insert-latest.enabled=false",
            "--expect-value-count",
            f"{secret_phrase}=1",
        )
        failing = run_helper_for_self_test(source, "--expect-value-count", f"{secret_phrase}=2")
        complete_snapshot = temp / "complete.json"
        idle_snapshot = temp / "idle.json"
        complete_snapshot.write_text(
            json.dumps(snapshot_payload("complete", secret_phrase, "Fake transcript ready")),
            encoding="utf-8",
        )
        idle_snapshot.write_text(
            json.dumps(snapshot_payload("idle", None, "Ready")),
            encoding="utf-8",
        )
        complete_summary = summarize_snapshot_path(complete_snapshot)
        idle_summary = summarize_snapshot_path(idle_snapshot)
        encoded_summaries = json.dumps({"complete": complete_summary, "idle": idle_summary})
        no_raw_transcript = secret_phrase not in passing.stdout and secret_phrase not in encoded_summaries
        checks = [
            {
                "name": "evidence-helper-passes-good-expectations",
                "passed": passing.returncode == 0,
            },
            {
                "name": "evidence-helper-fails-bad-count",
                "passed": failing.returncode != 0,
            },
            {
                "name": "summaries-omit-raw-transcript",
                "passed": no_raw_transcript,
            },
            {
                "name": "complete-summary-has-transcript-hash",
                "passed": complete_summary.get("hasTranscript") is True
                and "transcriptHash" in complete_summary
                and "transcript" not in complete_summary,
            },
            {
                "name": "idle-summary-has-no-transcript",
                "passed": idle_summary.get("hasTranscript") is False and "transcriptHash" not in idle_summary,
            },
        ]
        receipt = {
            "schema": "foil.iosPhysicalHarness.selfTest.v1",
            "checks": checks,
            "passed": all(check["passed"] for check in checks),
            "passingHelper": sanitized_process_result(passing),
            "failingHelper": sanitized_process_result(failing),
            "completeSummary": complete_summary,
            "idleSummary": idle_summary,
        }
        write_json(receipt)
        return 0 if receipt["passed"] else 1


def add_common_device_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--device-id", default=DEVICE_ID, help=f"CoreDevice id for {DEVICE_NAME}.")


def add_common_wda_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--wda-url", default=WDA_URL, help="Base WebDriverAgent URL.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Foil iOS physical-device harness.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    status = subparsers.add_parser("status", help="Print sanitized device and WDA readiness.")
    add_common_device_args(status)
    add_common_wda_args(status)
    status.set_defaults(func=cmd_status)

    wda_command = subparsers.add_parser("wda-command", help="Print the foreground WDA xcodebuild command.")
    wda_command.set_defaults(func=cmd_wda_command)

    session = subparsers.add_parser("session", help="Create a current-app WDA session without bundleId.")
    add_common_wda_args(session)
    session.set_defaults(func=cmd_session)

    delete_session = subparsers.add_parser("delete-session", help="Delete a WDA session id.")
    add_common_wda_args(delete_session)
    delete_session.add_argument("session_id")
    delete_session.set_defaults(func=cmd_delete_session)

    fetch_source = subparsers.add_parser("fetch-source", help="Fetch WDA source to a file without printing it.")
    add_common_wda_args(fetch_source)
    fetch_source.add_argument("session_id")
    fetch_source.add_argument("--output", required=True, type=Path)
    fetch_source.set_defaults(func=cmd_fetch_source)

    stage = subparsers.add_parser("stage-transcript", help="Stage a sterile transcript in the Foil App Group.")
    add_common_device_args(stage)
    stage.add_argument("--transcript", help="Sterile transcript text. It is hashed in output, not printed.")
    stage.add_argument("--transcript-file", type=Path, help="File containing sterile transcript text.")
    stage.add_argument("--message", default="Fake transcript ready")
    stage.set_defaults(func=cmd_stage_transcript)

    reset = subparsers.add_parser("reset-transcript", help="Reset Foil App Group transcript state to idle.")
    add_common_device_args(reset)
    reset.add_argument("--message", default="Ready")
    reset.set_defaults(func=cmd_reset_transcript)

    summary = subparsers.add_parser("app-group-summary", help="Copy and summarize the Foil App Group snapshot.")
    add_common_device_args(summary)
    summary.set_defaults(func=cmd_app_group_summary)

    receipt = subparsers.add_parser("receipt", help="Create sanitized WDA evidence via ios-physical-wda-evidence.py.")
    receipt.add_argument("--source", required=True, type=Path)
    receipt.add_argument("--target", required=True)
    receipt.add_argument("--require-identifier", action="append", default=[])
    receipt.add_argument("--forbid-identifier", action="append", default=[])
    receipt.add_argument("--expect-identifier-state", action="append", default=[])
    receipt.add_argument("--require-value", action="append", default=[])
    receipt.add_argument("--forbid-value", action="append", default=[])
    receipt.add_argument("--require-text", action="append", default=[])
    receipt.add_argument("--forbid-text", action="append", default=[])
    receipt.add_argument("--expect-value-count", action="append", default=[])
    receipt.add_argument("--app-group-snapshot", type=Path)
    receipt.add_argument("--storage-report", type=Path)
    receipt.add_argument("--write-json", type=Path)
    receipt.set_defaults(func=cmd_receipt)

    self_test = subparsers.add_parser("self-test", help="Run fixture-only privacy and fail-closed checks.")
    self_test.set_defaults(func=cmd_self_test)

    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except HarnessError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except urllib.error.URLError as error:
        print(f"error: WDA request failed: {error}", file=sys.stderr)
        return 2
    except subprocess.TimeoutExpired as error:
        print(f"error: command timed out: {error.cmd}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
