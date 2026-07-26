#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Remove every package the IdleScreen installer seats (except idlescreen itself,
# which is already being erased by the package manager).
#
# Invoked from the idlescreen metapackage %preun / postrm (after a short delay
# so we do not fight an in-progress dnf/apt transaction).

set -eu

# Product stack + official savers. Keep in sync with install_honesty::PRODUCT_STACK.
PKGS="
idle-cosmic
idle-tui
idle-cli
idle-savers
idle-saver-beams
idle-saver-bursts
idle-saver-chaos
idle-saver-cosmos
idle-saver-glyphs
idle-saver-gnats
idle-saver-hearth
idle-saver-radar
idle-saver-ripple
idle-saver-storm
idle-daemon
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
        # --nodeps: break circular "meta vs modules" ordering; we intentionally
        # wipe the product set when the brand package is removed.
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

# Repo drop-ins written by install.sh / install binary (not owned by RPMs).
remove_repo_dropins() {
    rm -f /etc/yum.repos.d/idlescreen.repo 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/idlescreen.list 2>/dev/null || true
    # Leave keyring in place (harmless; reinstall re-writes it).
}

if command -v rpm >/dev/null 2>&1 && [ -d /var/lib/rpm ]; then
    erase_rpm
fi
if command -v dpkg >/dev/null 2>&1 && [ -d /var/lib/dpkg ]; then
    erase_deb
fi
remove_repo_dropins

rm -f /var/tmp/idlescreen-remove-product-stack 2>/dev/null || true
exit 0
