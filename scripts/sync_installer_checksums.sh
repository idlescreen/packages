#!/usr/bin/env bash
# sync_installer_checksums.sh — synchronize and verify installer module checksums
# across packages/install.sh, packages/install-studio.sh, and idlescreen.github.io/install.sh.
#
# Usage:
#   scripts/sync_installer_checksums.sh          # update checksums in-place
#   scripts/sync_installer_checksums.sh --check  # verify checksums without modifying
#
# SPDX-License-Identifier: Apache-2.0

set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -x "./bin/sync-hashes" ]; then
    exec ./bin/sync-hashes "$@"
elif [ -x "./bin/packages" ]; then
    exec ./bin/packages sync-hashes "$@"
else
    echo "ERROR: ./bin/sync-hashes not found; run 'make build' first." >&2
    exit 1
fi
