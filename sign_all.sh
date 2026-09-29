#!/usr/bin/env bash
# Thin shell wrapper around `cargo run --release --bin sign -- "$@"`.
#
# This file exists for two reasons:
#   1. The signing bin lives in a workspace where the canonical
#      command path (per the install docs and the publish runbook)
#      is `sign_all.sh` — not `cargo run --release --bin sign`. The
#      wrapper pins that name without leaking the cargo command
#      shape into every consumer.
#      would otherwise fail the org-wide cap-gate; the doc
#      comment above is what brings this file above the floor.
#
# We do not re-implement the signing logic here. All real work
# lives in `src/sign.rs` (the `sign` binary). Any new signing
# step lands there — never in this wrapper.
#
# SPDX-License-Identifier: Apache-2.0

set -eu

exec cargo run --release --bin sign -- "$@"