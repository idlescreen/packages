#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Headless package gate for screensaver (run before generate-rpm / cargo deb).
set -euo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT"

if [[ "${SKIP_TESTS:-}" == "1" || "${SKIP_TESTS:-}" == "true" ]]; then
  echo "SKIP_TESTS set — saver gate skipped."
  exit 0
fi

if [[ ! -e idle ]]; then
  if [[ -d ../idle ]]; then
    ln -sfn ../idle idle
  else
    echo "FAIL: need sibling ../idle (idle-api) or ./idle symlink" >&2
    exit 1
  fi
fi

echo ">>> cargo test ($(basename "$ROOT"))"
cargo test
echo "SAVER_PACKAGE_GATE_PASS"
