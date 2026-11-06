#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Headless package gate for all official IdleScreen screensavers.
# Run before building/signing RPMs/DEBs for GitHub Pages.

set -euo pipefail

if [[ "${SKIP_TESTS:-}" == "1" || "${SKIP_TESTS:-}" == "true" || "${SKIP_TESTS:-}" == "yes" ]]; then
  echo "SKIP_TESTS set — savers package gate skipped."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$PACKAGES_ROOT/.." && pwd)"

if [[ -f "$ROOT/idlescreen/main.oo" ]]; then
  echo ">>> idlescreen native openOODA (.oo) monorepo"
  cd "$ROOT/idlescreen"
  if make test && make parity; then
    echo "=========================================="
    echo "Savers gate: monorepo idlescreen (.oo) passed, 0 failed"
    echo "SAVERS_PACKAGE_GATE_PASS"
    exit 0
  else
    echo "=========================================="
    echo "Savers gate: monorepo idlescreen (.oo) FAILED" >&2
    echo "SAVERS_PACKAGE_GATE_FAIL"
    exit 1
  fi
fi

echo "FAIL: idlescreen monorepo not found at $ROOT/idlescreen/main.oo" >&2
exit 1
