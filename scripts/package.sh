#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build RPM/DEB for screensaver only after tests pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$PWD}"
cd "$ROOT"

"$SCRIPT_DIR/qa_package_gate.sh" "$ROOT"
echo ">>> cargo build --release"
cargo build --release
echo ">>> cargo generate-rpm"
cargo generate-rpm
if command -v cargo-deb >/dev/null 2>&1 || cargo deb --help >/dev/null 2>&1; then
  cargo deb --no-build || true
fi
echo "Package artifacts under target/generate-rpm/ (and target/debian/ if deb built)"
