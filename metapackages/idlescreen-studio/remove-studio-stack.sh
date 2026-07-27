#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Erase Studio product packages after idlescreen-studio meta is removed.
# Leaves: idle-savers, ffmpeg/ffmpeg-free, desktop host stack, repo drop-in.

set -eu

# Keep in sync with install-studio.sh product packages (not plugins / ffmpeg).
PKGS="
idle-studio
render
"

erase_rpm() {
    to_erase=""
    for p in $PKGS; do
        if rpm -q "$p" >/dev/null 2>&1; then
            to_erase="$to_erase $p"
        fi
    done
    # shellcheck disable=SC2086
    if [ -n "$to_erase" ]; then
        rpm -e --nodeps $to_erase 2>/dev/null || true
    fi
}

erase_deb() {
    to_erase=""
    for p in $PKGS; do
        if dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed'; then
            to_erase="$to_erase $p"
        fi
    done
    # shellcheck disable=SC2086
    if [ -n "$to_erase" ]; then
        dpkg --remove --force-depends $to_erase 2>/dev/null || true
    fi
}

if command -v rpm >/dev/null 2>&1 && [ -d /var/lib/rpm ]; then
    erase_rpm
fi
if command -v dpkg >/dev/null 2>&1 && [ -d /var/lib/dpkg ]; then
    erase_deb
fi

rm -f /var/tmp/idlescreen-remove-studio-stack 2>/dev/null || true
exit 0
