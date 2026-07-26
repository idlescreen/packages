#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Schedule product-stack cleanup after the current package transaction ends.
# Called from idlescreen %preun / postrm on full erase (not upgrade).

set -eu

SRC="/usr/libexec/idlescreen/remove-product-stack"
DST="/var/tmp/idlescreen-remove-product-stack"

if [ ! -x "$SRC" ]; then
    # Fallback: inline minimal erase if script already gone (should not happen in %preun).
    exit 0
fi

cp -f "$SRC" "$DST"
chmod 755 "$DST"

# Delay so dnf/apt can release the rpmdb/dpkg lock.
run_later() {
    /bin/sh -c 'sleep 3; /var/tmp/idlescreen-remove-product-stack' &
}

if command -v systemd-run >/dev/null 2>&1; then
    # Transient unit outlives the package manager transaction.
    systemd-run --no-block --collect \
        --unit="idlescreen-remove-stack.service" \
        --description="IdleScreen product stack cleanup after idlescreen erase" \
        /bin/sh -c 'sleep 3; /var/tmp/idlescreen-remove-product-stack' \
        2>/dev/null || run_later
else
    run_later
fi

exit 0
