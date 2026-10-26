#!/bin/sh
# Regression test: the studio installer's pre-flight must accept a virtual
# provide, not only a real package.
#
# idle-savers has no .deb of its own — the idlescreen package provides it.
# The pre-flight used to require a `Package:` entry for every requested name,
# so it aborted on every host with "package is not published in the IdleScreen
# channel: idle-savers" and the studio installer never got past step 2.
#
# The fixture index is local: this test must not depend on the network.
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

fail=0
check() {
    expected="$1"
    actual="$2"
    desc="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ok   $desc"
    else
        echo "  FAIL $desc"
        echo "       expected: $expected"
        echo "       actual:   $actual"
        fail=$((fail + 1))
    fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/apt/dists/stable/main/binary-amd64"
cat > "$TMP/apt/dists/stable/main/binary-amd64/Packages" <<'INDEX'
Package: real-pkg
Version: 1.0-1
Provides: virt-pkg (= 1.0-1), other-virt (= 1.0-1)

Package: plain-pkg
Version: 1.0-1
INDEX

# Drive the installer's own modules in a separate shell, the way the real
# installer sources them, and report the exit status.
run_preflight() {
    _want="$1"
    _base="${2:-$TMP}"
    cat > "$TMP/driver.sh" <<DRIVER
set -eu
IDLESCREEN_REPO_BASE="file://$_base"
export IDLESCREEN_REPO_BASE
. "$REPO_ROOT/install-studio-lib/00-color.sh"
. "$REPO_ROOT/install-studio-lib/10-preflight.sh"
ALL_PKGS="$_want"
preflight_packages
DRIVER
    sh "$TMP/driver.sh" >/dev/null 2>&1
    echo $?
}

check 0 "$(run_preflight 'real-pkg plain-pkg')" 'real packages are published'
check 0 "$(run_preflight 'real-pkg virt-pkg')" 'a virtual provide counts as published'
check 0 "$(run_preflight 'other-virt')" 'any name in a Provides list is published'
check 1 "$(run_preflight 'real-pkg no-such-pkg')" 'an unpublished name is still fatal'

# The real request list must survive the check: idle-savers is provided by
# idlescreen, and the shipped index proves it.
REAL_ALL_PKGS=$(REPO_ROOT="$REPO_ROOT" sh -c '. "$REPO_ROOT/install-studio-lib/00-color.sh"; printf "%s" "$ALL_PKGS"')
case " $REAL_ALL_PKGS " in
    *idle-savers*) echo "  ok   the request list includes the virtual package idle-savers" ;;
    *) echo "  FAIL the request list no longer exercises a virtual package"; fail=$((fail + 1)) ;;
esac

# The shipped index, checked against the shipped request list — this is the
# combination the installer meets on a real host.
check 0 "$(run_preflight "$REAL_ALL_PKGS" "$REPO_ROOT")" \
    'the shipped index satisfies the shipped request list'

if [ "$fail" -ne 0 ]; then
    echo "studio pre-flight regression test FAILED ($fail check(s))"
    exit 1
fi
echo "studio pre-flight regression test passed"
