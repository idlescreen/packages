#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Headless package gate for all official IdleScreen screensavers.
# Run before building/signing RPMs/DEBs for GitHub Pages.
#
# Layout expected (sibling checkouts):
#   .../idlescreen/idlescreen/       # consolidated monorepo (crates/idlescreen)
#   .../idlescreen/packages/         # this repo
#
# Usage (from packages/ or anywhere):
#   ./scripts/qa_savers_package_gate.sh
#   SKIP_TESTS=1 ./scripts/qa_savers_package_gate.sh
#
# Exit 0 only if the idlescreen suite passes `cargo test`.

set -euo pipefail

if [[ "${SKIP_TESTS:-}" == "1" || "${SKIP_TESTS:-}" == "true" || "${SKIP_TESTS:-}" == "yes" ]]; then
  echo "SKIP_TESTS set — savers package gate skipped."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$PACKAGES_ROOT/.." && pwd)"

if [[ -d "$ROOT/idlescreen/crates/idlescreen" ]]; then
  echo ">>> idlescreen monorepo (unified single-binary architecture)"
  cd "$ROOT/idlescreen"
  if cargo test -p idlescreen --quiet; then
    echo "=========================================="
    echo "Savers gate: monorepo idlescreen passed, 0 failed"
    echo "SAVERS_PACKAGE_GATE_PASS"
    exit 0
  else
    echo "=========================================="
    echo "Savers gate: monorepo idlescreen FAILED" >&2
    echo "SAVERS_PACKAGE_GATE_FAIL"
    exit 1
  fi
fi

echo "FAIL: idlescreen monorepo not found at $ROOT/idlescreen/crates/idlescreen" >&2
exit 1
