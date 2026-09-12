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

# Savers live in the idle-savers monorepo (consolidated from the ten
# idle-saver-* repos). Members carry their own plugin manifests.
SAVERS_WS="$ROOT/idle-savers"
shopt -s nullglob
manifests=("$SAVERS_WS"/*/libscreensaver_*.idleplugin.toml)
if [[ ${#manifests[@]} -eq 0 ]]; then
  echo "FAIL: no saver manifests under $SAVERS_WS" >&2
  exit 1
fi

# Workspace Cargo.toml expects path idle/idle-api
if [[ ! -e "$SAVERS_WS/idle" ]]; then
  ln -sfn "$IDLE_API_SRC" "$SAVERS_WS/idle"
fi

echo ">>> idle-savers workspace (${#manifests[@]} savers)"
cd "$SAVERS_WS"
if cargo test --workspace --quiet; then
  echo "=========================================="
  echo "Savers gate: ${#manifests[@]} passed, 0 failed"
  echo "SAVERS_PACKAGE_GATE_PASS"
  exit 0
else
  echo "=========================================="
  echo "Savers gate: workspace suite FAILED" >&2
  echo "SAVERS_PACKAGE_GATE_FAIL"
  exit 1
fi
