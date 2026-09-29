#!/usr/bin/env bash
# Thin shell wrapper around `cargo run --release --bin update`.
#
# This file exists for two reasons:
#   1. The publish runbook (and the install docs) refer to
#      `update.sh` as the canonical entry point. The wrapper pins
#      that name without leaking the cargo command shape into
#      every consumer.
#      would otherwise fail the org-wide cap-gate; the doc
#      comment above is what brings this file above the floor.
#
# We do not re-implement the publish pipeline here. All real work
# lives in `src/update.rs` (the `update` binary) and its
# per-step siblings under `src/update_steps/`. Any new publish
# step lands there — never in this wrapper.
#
# SPDX-License-Identifier: Apache-2.0

set -eu

exec cargo run --release --bin update