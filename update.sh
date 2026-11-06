#!/usr/bin/env bash
# Thin shell wrapper around `./bin/update`.
#
# All real metadata indexing and GPG signing lives in `src/update.oo`
# (built to `./bin/update` via `oodac`).
#
# SPDX-License-Identifier: Apache-2.0

set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cd "$REPO_ROOT"
exec ./bin/update
