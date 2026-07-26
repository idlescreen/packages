#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Headless package gate for all official IdleScreen screensavers.
# Run before building/signing saver RPMs for GitHub Pages.
#
# Layout expected (sibling checkouts):
#   .../idlescreen/idle/              # idle-api path dependency
#   .../idlescreen/idle-saver-beams/
#   .../idlescreen/idle-saver-*/
#   .../idlescreen/packages/          # this repo
#
# Usage (from packages/ or anywhere):
#   ./scripts/qa_savers_package_gate.sh
#   SKIP_TESTS=1 ./scripts/qa_savers_package_gate.sh
#
# Exit 0 only if every discovered saver passes `cargo test`.

set -euo pipefail

if [[ "${SKIP_TESTS:-}" == "1" || "${SKIP_TESTS:-}" == "true" || "${SKIP_TESTS:-}" == "yes" ]]; then
  echo "SKIP_TESTS set — savers package gate skipped."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# packages/ is under idlescreen/; savers are siblings of packages/
ROOT="$(cd "$PACKAGES_ROOT/.." && pwd)"
IDLE_API_SRC="$ROOT/idle"

if [[ ! -d "$IDLE_API_SRC/idle-api" ]]; then
  echo "FAIL: idle-api not found at $IDLE_API_SRC/idle-api" >&2
  echo "Clone idlescreen/idle next to packages and savers." >&2
  exit 1
fi

echo "=========================================="
echo "IdleScreen savers package gate (headless)"
echo "=========================================="
echo "Root: $ROOT"
echo ""

shopt -s nullglob
savers=("$ROOT"/idle-saver-*/)
if [[ ${#savers[@]} -eq 0 ]]; then
  echo "FAIL: no idle-saver-* directories under $ROOT" >&2
  exit 1
fi

failed=0
passed=0

for dir in "${savers[@]}"; do
  name="$(basename "$dir")"
  echo ">>> $name"
  cd "$dir"
  # Cargo.toml expects path idle/idle-api
  if [[ ! -e idle ]]; then
    ln -sfn ../idle idle
  fi
  if cargo test --quiet; then
    echo "PASS: $name"
    passed=$((passed + 1))
  else
    echo "FAIL: $name" >&2
    failed=$((failed + 1))
  fi
  echo ""
done

echo "=========================================="
echo "Savers gate: $passed passed, $failed failed (${#savers[@]} total)"
if [[ "$failed" -gt 0 ]]; then
  echo "SAVERS_PACKAGE_GATE_FAIL"
  exit 1
fi
echo "SAVERS_PACKAGE_GATE_PASS"
exit 0
