#!/bin/bash
set -euo pipefail

scenario=""
app=""
state_root=""
validate_receipt_path=""

while (($#)); do
  case "$1" in
    --scenario) scenario="${2:-}"; shift 2 ;;
    --app) app="${2:-}"; shift 2 ;;
    --state-root) state_root="${2:-}"; shift 2 ;;
    --validate-receipt) validate_receipt_path="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 64 ;;
  esac
done

case "$scenario" in
  clean-install-switch|offline-relaunch) ;;
  *) echo "ERROR: --scenario must be clean-install-switch or offline-relaunch" >&2; exit 64 ;;
esac

if [[ -z "$state_root" ]]; then
  echo "ERROR: --state-root is required" >&2
  exit 64
fi

mkdir -p "$state_root"
receipt="$state_root/receipt-$scenario.json"

validate_receipt() {
  local candidate=$1
  local receipt_scenario=${2:-$scenario}
  local script_dir
  script_dir=$(cd "$(dirname "$0")" && pwd)
  /usr/bin/python3 - "$candidate" "$receipt_scenario" "$state_root" \
    "$script_dir/../Foil/Resources/ManagedLocalModels.json" <<'PY'
import hashlib
import json
import os
import re
import struct
import sys

path, expected_scenario, expected_root, catalog_path = sys.argv[1:]
expected_root = os.path.realpath(expected_root)

def reject(message):
    print(f"INVALID RECEIPT: {message}", file=sys.stderr)
    raise SystemExit(3)

def load(candidate):
    try:
        with open(candidate, "rb") as handle:
            raw = handle.read()
        value = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        reject(f"cannot parse {candidate}: {error}")
    if not isinstance(value, dict):
        reject("receipt root must be a JSON object")
    return value, raw

def load_catalog():
    value, _ = load(catalog_path)
    models = value.get("models")
    require(isinstance(models, list), "managed model catalog has no models array")
    result = {}
    for model in models:
        require(isinstance(model, dict), "managed model catalog entry must be an object")
        exact_keys(model, ["id", "bytes", "sha256"], "managed model catalog entry")
        result[model["id"]] = model
    return result

def require(condition, message):
    if not condition:
        reject(message)

def exact_keys(value, required, context):
    missing = sorted(set(required) - set(value))
    require(not missing, f"{context} missing fields: {', '.join(missing)}")

def nonempty(value):
    return isinstance(value, str) and bool(value.strip())

def transcript(value, context):
    require(isinstance(value, dict), f"{context} must be an object")
    exact_keys(value, ["spokenPhrase", "transcript", "normalMicrophonePath"], context)
    require(nonempty(value["spokenPhrase"]), f"{context}.spokenPhrase must be nonempty")
    require(nonempty(value["transcript"]), f"{context}.transcript must be nonempty")
    require(value["normalMicrophonePath"] is True,
            f"{context} must use the normal microphone path")

def image_dimensions(candidate):
    with open(candidate, "rb") as handle:
        data = handle.read()
    if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        return struct.unpack(">II", data[16:24])
    if len(data) >= 4 and data[:2] == b"\xff\xd8":
        offset = 2
        start_of_frame = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                          0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        while offset + 4 <= len(data):
            if data[offset] != 0xFF:
                offset += 1
                continue
            while offset < len(data) and data[offset] == 0xFF:
                offset += 1
            if offset >= len(data):
                break
            marker = data[offset]
            offset += 1
            if marker in {0x01, 0xD8, 0xD9}:
                continue
            if offset + 2 > len(data):
                break
            length = struct.unpack(">H", data[offset:offset + 2])[0]
            if length < 2 or offset + length > len(data):
                break
            if marker in start_of_frame and length >= 7:
                height, width = struct.unpack(">HH", data[offset + 3:offset + 7])
                return width, height
            offset += length
    return None

def validated_model(value, context):
    require(isinstance(value, dict), f"{context} must be an object")
    exact_keys(value, ["id", "catalogBytes", "catalogSHA256", "downloadedBytes",
                       "installedBytes", "catalogVerified"], context)
    require(value["id"] in ["base.en", "base"], f"{context}.id must be a managed catalog ID")
    require(type(value["catalogBytes"]) is int and value["catalogBytes"] > 0,
            f"{context}.catalogBytes must be a positive integer")
    require(isinstance(value["catalogSHA256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", value["catalogSHA256"]) is not None,
            f"{context}.catalogSHA256 must be a lowercase SHA-256")
    require(value["downloadedBytes"] == value["catalogBytes"],
            f"{context} downloaded bytes must equal catalog bytes")
    require(value["installedBytes"] == value["catalogBytes"],
            f"{context} installed bytes must equal catalog bytes")
    require(value["catalogVerified"] is True, f"{context}.catalogVerified must be true")
    catalog_model = load_catalog().get(value["id"])
    require(catalog_model is not None, f"{context}.id is absent from Foil's pinned catalog")
    require(value["catalogBytes"] == catalog_model["bytes"],
            f"{context}.catalogBytes does not match Foil's pinned catalog")
    require(value["catalogSHA256"] == catalog_model["sha256"],
            f"{context}.catalogSHA256 does not match Foil's pinned catalog")
    return value

def common(value, scenario):
    exact_keys(value, [
        "schemaVersion", "scenario", "status", "fixture", "bundleIdentifier",
        "stateRoot", "productionPermissionsRetained", "productionInstallerRetained",
        "productionRestorationRetained", "permissions", "signing", "screenshots"
    ], "receipt")
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1,
            "schemaVersion must be integer 1")
    require(value["scenario"] == scenario, f"scenario must be {scenario}")
    require(value["status"] == "passed", "status must be passed")
    require(value["fixture"] is False, "fixture receipts cannot prove live acceptance")
    require(value["bundleIdentifier"] == "com.neonwatty.Foil.Dev",
            "bundleIdentifier must be com.neonwatty.Foil.Dev")
    require(nonempty(value["stateRoot"]) and os.path.realpath(value["stateRoot"]) == expected_root,
            "stateRoot must match --state-root")
    for field in ["productionPermissionsRetained", "productionInstallerRetained",
                  "productionRestorationRetained"]:
        require(value[field] is True, f"{field} must be true")
    permissions = value["permissions"]
    require(isinstance(permissions, dict), "permissions must be an object")
    exact_keys(permissions, ["accessibility", "microphone", "observedAt"], "permissions")
    require(permissions["accessibility"] == "granted", "Accessibility must be granted")
    require(permissions["microphone"] == "granted", "Microphone must be granted")
    require(nonempty(permissions["observedAt"]), "permissions.observedAt must be nonempty")
    signing = value["signing"]
    require(isinstance(signing, dict), "signing must be an object")
    exact_keys(signing, ["verified", "identity", "bundleIdentifier"], "signing")
    require(signing["verified"] is True, "signing.verified must be true")
    require(nonempty(signing["identity"]), "signing.identity must be nonempty")
    require(signing["bundleIdentifier"] == value["bundleIdentifier"],
            "signing bundle identifier must match the receipt")
    screenshots = value["screenshots"]
    minimum = 3 if scenario == "clean-install-switch" else 2
    require(isinstance(screenshots, list) and len(screenshots) >= minimum,
            f"{scenario} requires at least {minimum} screenshots")
    require(all(isinstance(item, str) for item in screenshots),
            "screenshot paths must be strings")
    require(len(set(screenshots)) == len(screenshots), "screenshot paths must be unique")
    for screenshot in screenshots:
        require(nonempty(screenshot) and os.path.isabs(screenshot),
                "screenshot paths must be nonempty absolute paths")
        require(os.path.isfile(screenshot) and os.path.getsize(screenshot) > 0,
                f"screenshot evidence is missing or empty: {screenshot}")
        dimensions = image_dimensions(screenshot)
        require(dimensions is not None,
                f"screenshot must be a decodable PNG or JPEG: {screenshot}")
        require(dimensions[0] >= 32 and dimensions[1] >= 32,
                f"screenshot dimensions must be at least 32x32: {screenshot}")

def clean(value):
    common(value, "clean-install-switch")
    exact_keys(value, ["freshStore", "languageChoice", "model", "switchTargetModel", "install",
                       "firstMicrophoneTranscript", "switch"], "clean receipt")
    fresh = value["freshStore"]
    require(isinstance(fresh, dict), "freshStore must be an object")
    exact_keys(fresh, ["initiallyAbsent", "path"], "freshStore")
    require(fresh["initiallyAbsent"] is True, "freshStore.initiallyAbsent must be true")
    require(nonempty(fresh["path"]) and os.path.realpath(fresh["path"]) == expected_root,
            "freshStore.path must match --state-root")
    require(value["languageChoice"] in ["englishOnly", "multilingual"],
            "languageChoice must be englishOnly or multilingual")
    model = validated_model(value["model"], "model")
    switch_target = validated_model(value["switchTargetModel"], "switchTargetModel")
    require(model["id"] != switch_target["id"],
            "model and switchTargetModel must be different managed models")
    install = value["install"]
    require(isinstance(install, dict), "install must be an object")
    exact_keys(install, ["progressObserved", "progressBytes", "completed"], "install")
    samples = install["progressBytes"]
    require(install["progressObserved"] is True, "install progress must be visibly observed")
    require(isinstance(samples, list) and len(samples) >= 2
            and all(type(sample) is int for sample in samples),
            "install.progressBytes requires at least two integer samples")
    require(all(left < right for left, right in zip(samples, samples[1:])),
            "install progress samples must increase")
    require(samples[0] >= 0 and samples[-1] <= model["catalogBytes"],
            "install progress samples must stay within catalog size")
    require(install["completed"] is True, "install.completed must be true")
    transcript(value["firstMicrophoneTranscript"], "firstMicrophoneTranscript")
    switch = value["switch"]
    require(isinstance(switch, dict), "switch must be an object")
    exact_keys(switch, ["fromModelID", "toModelID", "activeModelID", "succeeded"], "switch")
    require(switch["fromModelID"] in ["base.en", "base"]
            and switch["toModelID"] in ["base.en", "base"]
            and switch["fromModelID"] != switch["toModelID"],
            "switch must name two different managed catalog models")
    require(switch["fromModelID"] == model["id"]
            and switch["toModelID"] == switch_target["id"],
            "switch identities must match model and switchTargetModel evidence")
    require(switch["activeModelID"] == switch["toModelID"],
            "switch.activeModelID must equal switch.toModelID")
    require(switch["succeeded"] is True, "switch.succeeded must be true")

def offline(value):
    common(value, "offline-relaunch")
    exact_keys(value, ["cleanReceiptSHA256", "process", "networkTrap",
                       "modelNetworkRequests", "retainedSelection",
                       "secondMicrophoneTranscript"], "offline receipt")
    clean_path = os.path.join(expected_root, "receipt-clean-install-switch.json")
    clean_value, clean_raw = load(clean_path)
    clean(clean_value)
    digest = hashlib.sha256(clean_raw).hexdigest()
    require(value["cleanReceiptSHA256"] == digest,
            "cleanReceiptSHA256 must link the unchanged clean receipt from the same state root")
    process = value["process"]
    require(isinstance(process, dict), "process must be an object")
    exact_keys(process, ["previousPID", "relaunchPID", "previousSessionID", "newSessionID"], "process")
    require(type(process["previousPID"]) is int and process["previousPID"] > 0,
            "process.previousPID must be positive")
    require(type(process["relaunchPID"]) is int and process["relaunchPID"] > 0
            and process["relaunchPID"] != process["previousPID"],
            "offline relaunch must use a new app process")
    require(nonempty(process["previousSessionID"]) and nonempty(process["newSessionID"])
            and process["newSessionID"] != process["previousSessionID"],
            "offline relaunch must use a new managed session")
    trap = value["networkTrap"]
    require(isinstance(trap, dict), "networkTrap must be an object")
    exact_keys(trap, ["scope", "loopbackAvailable", "label"], "networkTrap")
    require(trap["scope"] == "app-model-host-only",
            "network trap scope must be app-model-host-only")
    require(trap["loopbackAvailable"] is True, "network trap must leave loopback available")
    require(nonempty(trap["label"]), "network trap must be explicitly labeled")
    require(type(value["modelNetworkRequests"]) is int and value["modelNetworkRequests"] == 0,
            "offline relaunch must record zero model requests")
    selection = value["retainedSelection"]
    require(isinstance(selection, dict), "retainedSelection must be an object")
    exact_keys(selection, ["selectedModelID", "activeModelID"], "retainedSelection")
    clean_active = clean_value["switch"]["activeModelID"]
    require(selection["selectedModelID"] == clean_active
            and selection["activeModelID"] == clean_active,
            "offline selection and active model must match the clean switch result")
    transcript(value["secondMicrophoneTranscript"], "secondMicrophoneTranscript")

value, _ = load(path)
require(value.get("scenario") == expected_scenario,
        f"receipt scenario does not match --scenario {expected_scenario}")
require(value.get("fixture") is False, "fixture receipts cannot prove live acceptance")
clean(value) if expected_scenario == "clean-install-switch" else offline(value)
print(f"VALID RECEIPT: {expected_scenario} ({path})")
PY
}

if [[ -n "$validate_receipt_path" ]]; then
  validate_receipt "$validate_receipt_path"
  exit 0
fi

if [[ -z "$app" ]]; then
  echo "ERROR: --app is required unless --validate-receipt is used" >&2
  exit 64
fi
if [[ ! -d "$app" || ! -x "$app/Contents/MacOS/Foil Dev" ]]; then
  echo "ERROR: Foil Dev app is missing or not executable: $app" >&2
  exit 66
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [[ "$bundle_id" != "com.neonwatty.Foil.Dev" ]]; then
  echo "ERROR: acceptance requires the isolated Foil Dev identity, got $bundle_id" >&2
  exit 65
fi

write_blocker() {
  local reason=$1
  /usr/bin/python3 - "$receipt" "$scenario" "$bundle_id" "$reason" <<'PY'
import json, sys
path, scenario, bundle_id, reason = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "scenario": scenario,
        "status": "blocked-prerequisite",
        "fixture": False,
        "bundleIdentifier": bundle_id,
        "reason": reason,
        "productionPermissionsRetained": True,
        "productionInstallerRetained": True,
        "productionRestorationRetained": True
    }, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  echo "BLOCKED: $reason" >&2
  echo "Receipt: $receipt" >&2
  exit 2
}

if [[ "$scenario" == "clean-install-switch" ]]; then
  if find "$state_root" -mindepth 1 -maxdepth 1 ! -name "receipt-$scenario.json" -print -quit | grep -q .; then
    write_blocker "Clean acceptance requires a new empty --state-root; existing data was not erased."
  fi
else
  clean_receipt="$state_root/receipt-clean-install-switch.json"
  if [[ ! -f "$clean_receipt" ]] || ! validate_receipt "$clean_receipt" clean-install-switch >/dev/null; then
    write_blocker "Offline relaunch requires a passed clean-install-switch receipt from the same isolated state root."
  fi
fi

if [[ "${FOIL_MANAGED_LOCAL_GUI_APPROVED:-0}" != "1" ]]; then
  write_blocker "Set FOIL_MANAGED_LOCAL_GUI_APPROVED=1 only after approving visible UI control, model downloads, and app termination/relaunch."
fi
if [[ "${FOIL_MANAGED_LOCAL_GUI_PERMISSIONS_READY:-0}" != "1" ]]; then
  write_blocker "Foil Dev needs user-granted Accessibility and Microphone permission; this driver does not reset or seed TCC state."
fi
if [[ -z "${FOIL_MANAGED_LOCAL_GUI_AUDIO_DRIVER:-}" || ! -x "${FOIL_MANAGED_LOCAL_GUI_AUDIO_DRIVER:-}" ]]; then
  write_blocker "Set FOIL_MANAGED_LOCAL_GUI_AUDIO_DRIVER to an executable that routes a controlled spoken phrase through the normal microphone input without changing global audio state."
fi
if [[ -z "${FOIL_MANAGED_LOCAL_GUI_UI_DRIVER:-}" || ! -x "${FOIL_MANAGED_LOCAL_GUI_UI_DRIVER:-}" ]]; then
  write_blocker "Set FOIL_MANAGED_LOCAL_GUI_UI_DRIVER to the approved visible-UI driver; --ui-testing, seeded models, and backend-only installation are forbidden."
fi

export FOIL_MANAGED_LOCAL_GUI_SCENARIO="$scenario"
export FOIL_MANAGED_LOCAL_GUI_APP="$app"
export FOIL_MANAGED_LOCAL_GUI_STATE_ROOT="$state_root"
export FOIL_MANAGED_LOCAL_GUI_RECEIPT="$receipt"
export FOIL_MANAGED_LOCAL_GUI_VALIDATOR="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
export FOIL_MANAGED_LOCAL_ACCEPTANCE_ROOT="$state_root/AppState"
export FOIL_MANAGED_LOCAL_ACCEPTANCE_ARGUMENT="--managed-local-gui-acceptance"
"$FOIL_MANAGED_LOCAL_GUI_UI_DRIVER"

if [[ ! -f "$receipt" ]] || ! validate_receipt "$receipt"; then
  write_blocker "The visible-UI driver did not produce a passed receipt."
fi
echo "PASS: $scenario ($receipt)"
