#!/bin/sh
# IdleScreen Studio installer
# Usage: curl -fsSL https://idlescreen.github.io/packages/install-studio.sh | sh
#
# Per RULES.md §2 (one function per page), the install pipeline is
# broken into focused sibling files under `install-studio-lib/`.
# This top-level script is just the entry: it sources the helpers
# in order and dispatches `main`.
#
# Install story:
#   0. Pre-flight: confirm every package we are about to ask for
#      is actually published — before touching /etc or the rpm
#      keyring as root.
#   1. Write the IdleScreen package channel (DNF or APT).
#   2. Install idle-studio + render, then idle-savers when
#      available.
#   3. Confirm render, idle-studio, ffmpeg, plugins.
# Remove: sudo dnf remove idle-studio render   (or apt remove ...)
# SPDX-License-Identifier: Apache-2.0

set -eu

# Source helpers in load order. Each file owns one focused
# responsibility per RULES.md §2.
. "$(dirname "$0")/install-studio-lib/00-color.sh"
. "$(dirname "$0")/install-studio-lib/10-preflight.sh"
. "$(dirname "$0")/install-studio-lib/20-ffmpeg.sh"
. "$(dirname "$0")/install-studio-lib/30-channel.sh"
. "$(dirname "$0")/install-studio-lib/40-install.sh"
. "$(dirname "$0")/install-studio-lib/50-verify.sh"

main "$@"