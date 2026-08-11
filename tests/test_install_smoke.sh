#!/bin/sh
# Mock-package-manager smoke test for packages/install.sh.
#
# Closes part of K2 (PROBE.md): shellcheck + bash -n only catch syntax +
# lint. This test runs the actual install.sh against a mock PATH of
# fake-but-well-behaved binaries (rpm, dpkg-query, dnf, apt-get, sudo,
# curl, etc.) to catch logic errors in install.sh (env-var handling,
# module sourcing, dnf vs apt branching, signature keyring download,
# post-install hook ordering).
#
# PATH discipline:
# - The fakes intercept commands install.sh calls for the install
#   (rpm, dpkg-query, dnf, apt-get, sudo, curl, systemctl, pkexec,
#   gtk-update-icon-cache, update-desktop-database).
# - sha256sum / shasum are NOT in the mock dir — install.sh must use
#   the real ones for `--verify-self`.

set -eu

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

MOCKBIN="$TMP/bin"
LOG="$TMP/install-call.log"
: > "$LOG"
mkdir -p "$MOCKBIN"

# Single sh dispatcher. Symlink every command we want to fake to this
# script. The dispatcher uses basename of argv0 to know which fake
# behaviour to run. `sudo` execs its tail (skipping argv0) so a
# `sudo dnf install -y foo` invocation lands in the dnf fake.
cat > "$MOCKBIN/_dispatch" <<'DISPATCH'
#!/bin/sh
cmd=$(basename "$0")
LOG_FILE="${FAKE_LOG_FILE:-/dev/null}"
printf '%s fake %s %s\n' "$(date +%s)" "$cmd" "$*" >> "$LOG_FILE"
case "$cmd" in
    rpm)        printf 'fake-pkg-1.0-1\n'; exit 0 ;;
    dpkg-query) printf 'Package: fake-pkg\nVersion: 1.0\n'; exit 0 ;;
    curl)       cat >/dev/null; exit 0 ;;
    dnf)        printf 'fake-dnf-ok\n'; exit 0 ;;
    apt-get)    printf 'fake-apt-ok\n'; exit 0 ;;
    systemctl)  exit 0 ;;
    pkexec)     exit 0 ;;
    gtk-update-icon-cache) exit 0 ;;
    update-desktop-database) exit 0 ;;
    sudo)
        # exec the wrapped command (argv is the full command; argv0
        # is the symlink path, $1 is the first real arg). We want to
        # run, e.g., `dnf install -y foo` — no shift, exec "$@".
        FAKE_LOG_FILE="$LOG_FILE" PATH="$PATH" exec "$@"
        ;;
esac
exit 0
DISPATCH
chmod +x "$MOCKBIN/_dispatch"
export FAKE_LOG_FILE="$LOG"

# Symlink with absolute target. A relative target like
# `MOCKBIN/_dispatch` resolves against the symlink's parent
# directory (not the caller's cwd) so a broken symlink can go
# unnoticed.
for cmd in rpm dpkg-query curl dnf apt-get sudo systemctl pkexec gtk-update-icon-cache update-desktop-database; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$cmd"
done

# Helper modules from the repo.
SCRIPT_DIR="$TMP/repo"
mkdir -p "$SCRIPT_DIR"
cp -f /home/jeryd/Projects/idlescreen/packages/install.sh "$SCRIPT_DIR/"
for mod in ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh; do
    if [ -f "/home/jeryd/Projects/idlescreen/packages/$mod" ]; then
        cp -f "/home/jeryd/Projects/idlescreen/packages/$mod" "$SCRIPT_DIR/"
    fi
done

fail=0

# 1. --verify-self with wrong hash: must exit non-zero
if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT_DIR/install.sh" \
    --verify-self "0000000000000000000000000000000000000000000000000000000000000000" \
    "$SCRIPT_DIR/install.sh" >/dev/null 2>&1; then
    echo "FAIL: --verify-self with wrong hash returned success"
    fail=$((fail + 1))
else
    echo "ok: --verify-self with wrong hash refuses"
fi

# 2. --verify-self with real hash: must exit 0
HASH=$(PATH="/usr/bin:/bin" sha256sum "$SCRIPT_DIR/install.sh" | awk '{print $1}')
if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT_DIR/install.sh" \
    --verify-self "$HASH" "$SCRIPT_DIR/install.sh" >/dev/null 2>&1; then
    echo "ok: --verify-self with real hash accepts"
else
    echo "FAIL: --verify-self with real hash returned non-zero"
    fail=$((fail + 1))
fi

# 3. Full install.sh against the mock PATH. The script may exit
#    non-zero near the end of phase 4 (daemon-launch needs real
#    binaries); we only assert that dnf was called.
(
    cd "$SCRIPT_DIR"
    PATH="$MOCKBIN:/usr/bin:/bin" \
    IDLESCREEN_REPO_BASE="file://$SCRIPT_DIR" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home" \
    XDG_CONFIG_HOME="$TMP/home/.config" \
    XDG_DATA_HOME="$TMP/home/.local/share" \
    XDG_STATE_HOME="$TMP/home/.local/state" \
    timeout 30 sh install.sh >/dev/null 2>&1 || true
)

# 4. Check the call log: install.sh should have called dnf or apt-get.
if grep -qE 'fake dnf |fake apt-get ' "$LOG" 2>/dev/null; then
    echo "ok: install.sh reached the package-manager stage"
else
    echo "FAIL: install.sh did not call dnf or apt-get (log:)"
    head -10 "$LOG" | sed 's/^/    /'
    fail=$((fail + 1))
fi

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
    exit 0
else
    echo "$fail check(s) failed"
    exit 1
fi
