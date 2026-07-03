#!/usr/bin/env bash
set -euo pipefail

swift tests/test_live_audio_cleanup_quality.swift "$@"
