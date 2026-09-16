#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: runner-cleanup.sh --workspace-root PATH --run-root PATH --mode before|after" >&2
}

fail() {
  echo "runner-cleanup: $*" >&2
  exit 1
}

workspace_input=""
run_input=""
mode=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace-root)
      [ "$#" -ge 2 ] || fail "--workspace-root requires a value"
      workspace_input="$2"
      shift 2
      ;;
    --run-root)
      [ "$#" -ge 2 ] || fail "--run-root requires a value"
      run_input="$2"
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || fail "--mode requires a value"
      mode="$2"
      shift 2
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$workspace_input" ] || fail "workspace root must not be empty"
[ -n "$run_input" ] || fail "run root must not be empty"
case "$mode" in
  before|after) ;;
  *) fail "mode must be before or after" ;;
esac

[ -d "$workspace_input" ] || fail "workspace root is not an existing directory: $workspace_input"
[ -d "$run_input" ] || fail "run root is not an existing directory: $run_input"

workspace_root="$(cd "$workspace_input" && pwd -P)" || fail "cannot resolve workspace root"
run_root="$(cd "$run_input" && pwd -P)" || fail "cannot resolve run root"

[ -n "$workspace_root" ] || fail "resolved workspace root is empty"
[ -n "$run_root" ] || fail "resolved run root is empty"
[ "$workspace_root" != "/" ] || fail "workspace root must not be /"
[ "$run_root" != "/" ] || fail "run root must not be /"
[ "$run_root" != "$workspace_root" ] || fail "run root must not equal workspace root"

canonical_home=""
if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
  canonical_home="$(cd "$HOME" && pwd -P)" || fail "cannot resolve home directory"
fi
[ -z "$canonical_home" ] || [ "$workspace_root" != "$canonical_home" ] || \
  fail "workspace root must not be the home directory"
[ -z "$canonical_home" ] || [ "$run_root" != "$canonical_home" ] || \
  fail "run root must not be the home directory"

case "$run_root" in
  "$workspace_root"/*) ;;
  *) fail "run root must be a strict descendant of workspace root" ;;
esac

run_basename="${run_root##*/}"
if ! [[ "$run_basename" =~ ^[0-9]+-[0-9]+-[abc]$ ]]; then
  fail "invalid run root basename: $run_basename"
fi

run_parent="${run_root%/*}"
if [ "$mode" = "after" ]; then
  cd "$run_parent" || fail "cannot anchor cleanup in run parent: $run_parent"
  anchored_parent="$(pwd -P)" || fail "cannot resolve anchored run parent"
  [ "$anchored_parent" = "$run_parent" ] || \
    fail "anchored run parent changed during validation"
fi

command_has_workspace_path() {
  local search_rest prefix suffix before after
  search_rest="$1"

  while [ -n "$search_rest" ]; do
    case "$search_rest" in
      *"$workspace_root"*) ;;
      *) return 1 ;;
    esac

    prefix="${search_rest%%"$workspace_root"*}"
    suffix="${search_rest#*"$workspace_root"}"
    before=""
    after=""
    [ -z "$prefix" ] || before="${prefix#"${prefix%?}"}"
    [ -z "$suffix" ] || after="${suffix%"${suffix#?}"}"

    case "$before" in
      ""|" "|$'\t'|"="|"\""|"'") ;;
      *) search_rest="$suffix"; continue ;;
    esac
    case "$after" in
      ""|"/"|" "|$'\t'|"\""|"'") return 0 ;;
      *) search_rest="$suffix" ;;
    esac
  done
  return 1
}

process_is_scoped() {
  scoped_name="$1"
  scoped_command="$2"
  case "$scoped_name" in
    Foil|FoilE2E)
      return 0
      ;;
    xcodebuild|xctest)
      case "$scoped_command" in
        *Foil*) ;;
        *) return 1 ;;
      esac
      command_has_workspace_path "$scoped_command"
      ;;
    *)
      return 1
      ;;
  esac
}

select_foil_processes() {
  selection_input="$1"
  while read -r pid comm command_line; do
    [ -n "${pid:-}" ] || continue
    case "$pid" in
      *[!0-9]*) continue ;;
    esac
    process_name="${comm##*/}"
    if process_is_scoped "$process_name" "$command_line"; then
      printf '%s %s\n' "$pid" "$process_name"
    fi
  done <<EOF
$selection_input
EOF
}

list_foil_processes() {
  process_output="$(ps -axo pid=,comm=,command=)" || {
    echo "runner-cleanup: unable to inspect processes" >&2
    return 1
  }
  select_foil_processes "$process_output"
}

revalidate_process() {
  expected_pid="$1"
  expected_name="$2"
  current_output="$(ps -p "$expected_pid" -o pid=,comm=,command=)" || return 1
  [ -n "$current_output" ] || return 1
  current_selection="$(select_foil_processes "$current_output")"
  [ "$current_selection" = "$expected_pid $expected_name" ] || return 2
}

foil_processes="$(list_foil_processes)" || exit 1

if [ "$mode" = "before" ]; then
  if [ -n "$foil_processes" ]; then
    while read -r pid process_name; do
      [ -n "${pid:-}" ] || continue
      if [ "${FOIL_CI_DRY_RUN:-0}" = "1" ]; then
        echo "dry-run: terminate pid $pid ($process_name)"
      else
        revalidation_status=0
        revalidate_process "$pid" "$process_name" || revalidation_status="$?"
        if [ "$revalidation_status" -ne 0 ]; then
          if [ "$revalidation_status" -eq 1 ]; then
            echo "pid $pid ($process_name) exited before termination"
            continue
          fi
          fail "pid $pid changed identity before termination"
        fi
        echo "terminate pid $pid ($process_name)"
        env kill -TERM "$pid" || fail "failed to terminate pid $pid ($process_name)"
      fi
    done <<EOF
$foil_processes
EOF
  fi

  if [ "${FOIL_CI_DRY_RUN:-0}" = "1" ]; then
    exit 0
  fi

  attempts=0
  while [ "$attempts" -lt 50 ]; do
    foil_processes="$(list_foil_processes)" || exit 1
    [ -n "$foil_processes" ] || exit 0
    attempts=$((attempts + 1))
    sleep 0.1
  done
  fail "known Foil processes remain after termination"
fi

if [ -n "$foil_processes" ]; then
  while read -r pid process_name; do
    [ -n "${pid:-}" ] || continue
    echo "runner-cleanup: refusing after cleanup while pid $pid ($process_name) is running" >&2
  done <<EOF
$foil_processes
EOF
  exit 1
fi

active_parent="$(pwd -P)" || fail "cannot resolve active run parent"
[ "$active_parent" = "$run_parent" ] || fail "run parent changed before cleanup"
[ -d "./$run_basename" ] || fail "anchored run root is not an existing directory"
active_run="$(cd "./$run_basename" && pwd -P)" || \
  fail "cannot resolve anchored run root"
[ "$active_run" = "$run_root" ] || fail "run root changed before cleanup"

if [ "${FOIL_CI_DRY_RUN:-0}" = "1" ]; then
  echo "dry-run: remove $run_root"
  exit 0
fi

echo "remove $run_root"
rm -rf -- "./$run_basename"
if [ -e "./$run_basename" ] || [ -L "./$run_basename" ]; then
  fail "run root still exists after removal: $run_root"
fi
