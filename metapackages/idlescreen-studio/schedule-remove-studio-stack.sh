#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Schedule Studio stack wipe after idlescreen-studio erase (not upgrade).

set -eu

SRC="/usr/libexec/idlescreen-studio/remove-studio-stack"
DST="/var/tmp/idlescreen-remove-studio-stack"

if [ ! -x "$SRC" ]; then
    exit 0
fi

cp -f "$SRC" "$DST"
chmod 755 "$DST"

run_later() {
    /bin/sh -c 'sleep 3; /var/tmp/idlescreen-remove-studio-stack' &
}

if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --no-block --collect \
        --unit="idlescreen-remove-studio-stack.service" \
        --description="IdleScreen Studio stack cleanup after idlescreen-studio erase" \
        /bin/sh -c 'sleep 3; /var/tmp/idlescreen-remove-studio-stack' \
        2>/dev/null || run_later
else
    run_later
fi

exit 0
