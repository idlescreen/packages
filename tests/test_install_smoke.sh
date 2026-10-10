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
    busctl)     exit 0 ;;
    curl)
        _url=""
        _out=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -o) [ -n "${2:-}" ] && _out="$2"; shift 2 ;;
                http*|file://*) _url="$1"; shift ;;
                *) shift ;;
            esac
        done
        if [ -n "$_url" ] && [ -n "$_out" ]; then
            case "$_url" in
                file://*)
                    _fpath="${_url#file://}"
                    if [ -f "$_fpath" ]; then
                        cp -f "$_fpath" "$_out"
                        exit 0
                    fi
                    ;;
            esac
        fi
        [ -n "$_out" ] && : > "$_out"
        exit 0
        ;;
    dnf)        printf 'fake-dnf-ok\n'; exit 0 ;;
    apt-get)    printf 'fake-apt-ok\n'; exit 0 ;;
    pacman)
        case "$1" in
            -Q)  printf 'fake-pkg 1.0-1\n'; exit 0 ;;
            -Si) printf 'Version : 1.0-1\n'; exit 0 ;;
            *)   printf 'fake-pacman-ok\n'; exit 0 ;;
        esac
        ;;
    tar)        exit 0 ;;
    omarchy-shell) printf 'false\n'; exit 0 ;;
    omarchy-toggle-enabled) exit 1 ;;
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
for cmd in rpm dpkg-query curl dnf apt-get sudo systemctl busctl pkexec gtk-update-icon-cache update-desktop-database; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$cmd"
done

# gpg is not symlinked to the dispatcher: --show-keys --with-colons must
# emit a fpr: line for the installer fingerprint checks. FAKE_GPG_FPR
# controls the emitted fingerprint so the negative case can forge a bad key.
cat > "$MOCKBIN/gpg" <<'GPG'
#!/bin/sh
_fpr="${FAKE_GPG_FPR:-549E73C9BC9229C786E538E2FBD8FC52C7817DD2}"
printf 'fpr:::::::::%s:\n' "$_fpr"
exit 0
GPG
chmod +x "$MOCKBIN/gpg"

# Helper modules from the repo.
SCRIPT_DIR="$TMP/repo"
mkdir -p "$SCRIPT_DIR"
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cp -f "$REPO_ROOT/install.sh" "$SCRIPT_DIR/"
for mod in ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh uninstall.sh; do
    if [ -f "$REPO_ROOT/$mod" ]; then
        cp -f "$REPO_ROOT/$mod" "$SCRIPT_DIR/"
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
    IDLESCREEN_RPM_GPG_DIR="$TMP/rpm-gpg" \
    IDLESCREEN_YUM_REPOS_D="$TMP/yum.repos.d" \
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

# 4b. IDLESCREEN_REPO_BASE must actually reach the DNF baseurl.
#     repo.sh used to reassign REPO_BASE unconditionally when sourced, so the
#     override worked for bootstrap downloads but was discarded for the written
#     .repo — and this test passed anyway because it separately redirected
#     RPM_GPG_DIR / YUM_REPOS_D. Assert the baseurl itself.
if [ -f "$TMP/yum.repos.d/idlescreen.repo" ]; then
    if grep -q "^baseurl=file://$SCRIPT_DIR/rpm$" "$TMP/yum.repos.d/idlescreen.repo"; then
        echo "ok: IDLESCREEN_REPO_BASE reached the DNF baseurl"
    else
        echo "FAIL: .repo baseurl did not honour IDLESCREEN_REPO_BASE (got:)"
        grep '^baseurl=' "$TMP/yum.repos.d/idlescreen.repo" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
else
    echo "FAIL: expected .repo at $TMP/yum.repos.d/idlescreen.repo"
    fail=$((fail + 1))
fi

# 4c. On non-COSMIC desktops, idlescreen.repo must exclude idle-cosmic and
#     dnf must be invoked with install_weak_deps=False.
if [ -f "$TMP/yum.repos.d/idlescreen.repo" ]; then
    if grep -q "^excludepkgs=idle-cosmic$" "$TMP/yum.repos.d/idlescreen.repo"; then
        echo "ok: non-COSMIC repo excludes idle-cosmic"
    else
        echo "FAIL: idlescreen.repo did not exclude idle-cosmic on non-COSMIC desktop"
        fail=$((fail + 1))
    fi
fi
if grep -q -- '--setopt=install_weak_deps=False' "$LOG" 2>/dev/null; then
    echo "ok: dnf disabled weak dependencies on non-COSMIC desktop"
else
    echo "FAIL: dnf was not invoked with --setopt=install_weak_deps=False on non-COSMIC desktop"
    fail=$((fail + 1))
fi

# 5. Negative: forged RPM signing key (wrong fingerprint) must refuse
#    BEFORE the package-manager stage — fail closed on a poisoned origin.
: > "$LOG"
(
    cd "$SCRIPT_DIR"
    PATH="$MOCKBIN:/usr/bin:/bin" \
    IDLESCREEN_REPO_BASE="file://$SCRIPT_DIR" \
    IDLESCREEN_RPM_GPG_DIR="$TMP/rpm-gpg-bad" \
    IDLESCREEN_YUM_REPOS_D="$TMP/yum.repos.d-bad" \
    FAKE_GPG_FPR="DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home" \
    timeout 30 sh install.sh >/dev/null 2>&1 || true
)
if grep -qE 'fake dnf |fake apt-get ' "$LOG" 2>/dev/null; then
    echo "FAIL: forged RPM key fingerprint still reached package-manager stage"
    fail=$((fail + 1))
else
    echo "ok: forged RPM key fingerprint refuses before dnf/apt"
fi

# 6. Arch/pacman path. detect_pkg_mgr checks pacman first precisely so this
#    is reachable on a runner that also has apt-get on PATH.
MOCKBIN_ARCH="$TMP/bin-arch"
mkdir -p "$MOCKBIN_ARCH"
LOG_ARCH="$TMP/install-arch.log"
: > "$LOG_ARCH"
for cmd in pacman tar curl sudo systemctl busctl pkexec gtk-update-icon-cache update-desktop-database \
           omarchy-shell omarchy-toggle-enabled; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN_ARCH/$cmd"
done
cp -f "$MOCKBIN/gpg" "$MOCKBIN_ARCH/gpg"
(
    cd "$SCRIPT_DIR"
    PATH="$MOCKBIN_ARCH:/usr/bin:/bin" \
    FAKE_LOG_FILE="$LOG_ARCH" \
    IDLESCREEN_OS_ID="arch" \
    IDLESCREEN_REPO_BASE="file://$SCRIPT_DIR" \
    IDLESCREEN_PACMAN_XDG_D="$TMP/xdg-idlescreen" \
    IDLESCREEN_PACMAN_KEY_D="$TMP/pacman-keys" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home-arch" \
    XDG_CONFIG_HOME="$TMP/home-arch/.config" \
    XDG_DATA_HOME="$TMP/home-arch/.local/share" \
    XDG_STATE_HOME="$TMP/home-arch/.local/state" \
    timeout 30 sh install.sh >/dev/null 2>&1 || true
)
if grep -q 'fake pacman -S' "$LOG_ARCH" 2>/dev/null; then
    echo "ok: install.sh reached the pacman stage"
else
    echo "FAIL: install.sh never called pacman (log:)"
    head -10 "$LOG_ARCH" | sed 's/^/    /'
    fail=$((fail + 1))
fi
if grep -qE 'fake dnf |fake apt-get ' "$LOG_ARCH" 2>/dev/null; then
    echo "FAIL: pacman host also took the dnf/apt branch"
    fail=$((fail + 1))
else
    echo "ok: pacman host did not fall through to dnf/apt"
fi
if [ -f "$TMP/pacman-keys/idlescreen-key.gpg" ]; then
    echo "ok: pacman trust anchor written to the configured key dir"
else
    echo "FAIL: pacman key not written to $TMP/pacman-keys/idlescreen-key.gpg"
    fail=$((fail + 1))
fi

# 6b. Session-shell integration. Both `omarchy-shell` and the shim are on the
#     mock PATH, so the installer must stand IdleScreen's own idle timer down
#     — otherwise two screensavers fire at two different delays.
_arch_home="$TMP/home-arch/.config/idlescreen/config.yaml"
if [ -f "$_arch_home" ] && grep -q '^idle_enabled: false' "$_arch_home"; then
    echo "ok: shell integration stood the own idle timer down"
else
    echo "FAIL: idle_enabled was not set false (config: ${_arch_home:-absent})"
    [ -f "$_arch_home" ] && sed 's/^/    /' "$_arch_home"
    fail=$((fail + 1))
fi

# 7. --uninstall. Removal must work on a host with no reachable channel, so
#    it is asserted against the mock with no repo config written at all.
LOG_UN="$TMP/install-uninstall.log"
: > "$LOG_UN"
# Seed the shim so removal is observable. SESSION_SHIM is env-overridable for
# exactly this reason — the test must not write to the real /usr/local/bin.
: > "$TMP/un-shim"
(
    cd "$SCRIPT_DIR"
    PATH="$MOCKBIN_ARCH:/usr/bin:/bin" \
    FAKE_LOG_FILE="$LOG_UN" \
    IDLESCREEN_OS_ID="arch" \
    IDLESCREEN_REPO_BASE="file://$SCRIPT_DIR" \
    IDLESCREEN_PACMAN_XDG_D="$TMP/un-xdg" \
    IDLESCREEN_PACMAN_KEY_D="$TMP/un-keys" \
    IDLESCREEN_SESSION_SHIM="$TMP/un-shim" \
    IDLESCREEN_RPM_GPG_DIR="$TMP/un-rpm-gpg" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home-un" \
    timeout 30 sh install.sh --uninstall >/dev/null 2>&1 || true
)
if grep -q 'fake pacman -R' "$LOG_UN" 2>/dev/null; then
    echo "ok: --uninstall removes packages via pacman"
else
    echo "FAIL: --uninstall never called pacman -R (log:)"
    head -10 "$LOG_UN" | sed 's/^/    /'
    fail=$((fail + 1))
fi
if grep -qE 'fake dnf |fake apt-get ' "$LOG_UN" 2>/dev/null; then
    echo "FAIL: --uninstall fell through to dnf/apt on an Arch host"
    fail=$((fail + 1))
else
    echo "ok: --uninstall did not fall through to dnf/apt"
fi
# The channel must be torn down without ever having been configured: a
# removal that depends on the repo being reachable is not a removal.
if [ ! -e "$TMP/un-xdg/idlescreen.db" ] && [ ! -e "$TMP/un-keys/idlescreen-key.gpg" ]; then
    echo "ok: --uninstall leaves no repo trust anchor behind"
else
    echo "FAIL: --uninstall left pacman repo state behind"
    fail=$((fail + 1))
fi
# The shim lives in /usr/local/bin, outside every package tree, so no package
# manager removes it. If it survived, it would shadow the shell's launcher and
# call a daemon that is gone.
if [ -f "$TMP/un-shim" ]; then
    echo "FAIL: --uninstall left the integration shim behind"
    fail=$((fail + 1))
else
    echo "ok: --uninstall removed the integration shim"
fi

# 8. Module bootstrapping without pre-copied modules (happy path):
#    Runs install.sh in an isolated directory where ui.sh does NOT exist.
#    install.sh must fetch all modules from IDLESCREEN_REPO_BASE, verify
#    their sha256 hashes against its pinned table, source them, and proceed.
LOG_BOOT="$TMP/install-boot.log"
: > "$LOG_BOOT"
BOOT_DIR="$TMP/repo-boot"
mkdir -p "$BOOT_DIR"
cp -f "$REPO_ROOT/install.sh" "$BOOT_DIR/"
(
    cd "$BOOT_DIR"
    PATH="$MOCKBIN_ARCH:/usr/bin:/bin" \
    FAKE_LOG_FILE="$LOG_BOOT" \
    IDLESCREEN_OS_ID="arch" \
    IDLESCREEN_REPO_BASE="file://$REPO_ROOT" \
    IDLESCREEN_PACMAN_XDG_D="$TMP/boot-xdg" \
    IDLESCREEN_PACMAN_KEY_D="$TMP/boot-keys" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home-boot" \
    timeout 30 sh install.sh --plan > "$TMP/boot.out" 2>&1 || true
)
if grep -q 'fake pacman ' "$LOG_BOOT" 2>/dev/null; then
    echo "ok: module bootstrapping fetched, verified, and executed cleanly"
else
    echo "FAIL: module bootstrapping failed to reach package-manager stage (output:)"
    head -20 "$TMP/boot.out" 2>/dev/null | sed 's/^/    /'
    fail=$((fail + 1))
fi

# 8b. Negative: tampered module during bootstrap must fail closed
LOG_BAD_BOOT="$TMP/install-bad-boot.log"
: > "$LOG_BAD_BOOT"
BAD_REPO="$TMP/bad-repo"
mkdir -p "$BAD_REPO"
for mod in ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh uninstall.sh; do
    cp -f "$REPO_ROOT/$mod" "$BAD_REPO/"
done
echo "# POISONED MODULE" >> "$BAD_REPO/post_install.sh"
BAD_BOOT_DIR="$TMP/repo-bad-boot"
mkdir -p "$BAD_BOOT_DIR"
cp -f "$REPO_ROOT/install.sh" "$BAD_BOOT_DIR/"
_bad_rc=0
(
    cd "$BAD_BOOT_DIR"
    PATH="$MOCKBIN_ARCH:/usr/bin:/bin" \
    FAKE_LOG_FILE="$LOG_BAD_BOOT" \
    IDLESCREEN_OS_ID="arch" \
    IDLESCREEN_REPO_BASE="file://$BAD_REPO" \
    IDLESCREEN_PACMAN_XDG_D="$TMP/bad-xdg" \
    IDLESCREEN_PACMAN_KEY_D="$TMP/bad-keys" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home-bad-boot" \
    timeout 30 sh install.sh --plan > "$TMP/bad-boot.out" 2>&1
) || _bad_rc=$?

if [ "$_bad_rc" -ne 0 ] && grep -q 'hash mismatch on bootstrapped module' "$TMP/bad-boot.out" 2>/dev/null; then
    echo "ok: tampered module bootstrap refuses with hash mismatch"
else
    echo "FAIL: tampered module bootstrap did not fail closed (rc=$_bad_rc, output:)"
    head -20 "$TMP/bad-boot.out" 2>/dev/null | sed 's/^/    /'
    fail=$((fail + 1))
fi

# 8c. Piped execution (curl|sh) with a hostile ui.sh in CWD:
#     Must NOT source the hostile local ui.sh. Must bootstrap, verify, and run.
LOG_PIPE="$TMP/install-pipe.log"
: > "$LOG_PIPE"
HOSTILE_DIR="$TMP/hostile-cwd"
mkdir -p "$HOSTILE_DIR"
cat > "$HOSTILE_DIR/ui.sh" <<'EOF'
echo "FATAL_CWD_INJECTION_EXPLOIT" >&2
exit 99
EOF
PIPE_OUT="$TMP/pipe.out"
(
    cd "$HOSTILE_DIR"
    export PATH="$MOCKBIN_ARCH:/usr/bin:/bin"
    export FAKE_LOG_FILE="$LOG_PIPE"
    export IDLESCREEN_OS_ID="arch"
    export IDLESCREEN_REPO_BASE="file://$REPO_ROOT"
    export IDLESCREEN_PACMAN_XDG_D="$TMP/pipe-xdg"
    export IDLESCREEN_PACMAN_KEY_D="$TMP/pipe-keys"
    export XDG_RUNTIME_DIR="$TMP/xdg"
    export HOME="$TMP/home-pipe"
    # shellcheck disable=SC2002
    cat "$REPO_ROOT/install.sh" | timeout 30 sh -s -- --plan > "$PIPE_OUT" 2>&1 || true
)

if grep -q 'FATAL_CWD_INJECTION_EXPLOIT' "$PIPE_OUT"; then
    echo "FAIL: piped install.sh sourced hostile ui.sh from caller cwd!"
    fail=$((fail + 1))
elif grep -q 'fake pacman ' "$LOG_PIPE" 2>/dev/null; then
    echo "ok: piped install.sh isolated from caller cwd and bootstrapped safely"
else
    echo "FAIL: piped install.sh failed to reach package manager:"
    head -20 "$PIPE_OUT" 2>/dev/null | sed 's/^/    /'
    fail=$((fail + 1))
fi

# 8d. Incomplete local module checkout:
#     A directory containing install.sh and ui.sh but lacking other modules
#     must bootstrap rather than crash attempting to source missing detect.sh.
LOG_INCOMPLETE="$TMP/install-incomplete.log"
: > "$LOG_INCOMPLETE"
INCOMPLETE_DIR="$TMP/incomplete-checkout"
mkdir -p "$INCOMPLETE_DIR"
cp -f "$REPO_ROOT/install.sh" "$INCOMPLETE_DIR/"
cp -f "$REPO_ROOT/ui.sh" "$INCOMPLETE_DIR/"
INCOMPLETE_OUT="$TMP/incomplete.out"
(
    cd "$INCOMPLETE_DIR"
    PATH="$MOCKBIN_ARCH:/usr/bin:/bin" \
    FAKE_LOG_FILE="$LOG_INCOMPLETE" \
    IDLESCREEN_OS_ID="arch" \
    IDLESCREEN_REPO_BASE="file://$REPO_ROOT" \
    IDLESCREEN_PACMAN_XDG_D="$TMP/incomplete-xdg" \
    IDLESCREEN_PACMAN_KEY_D="$TMP/incomplete-keys" \
    XDG_RUNTIME_DIR="$TMP/xdg" \
    HOME="$TMP/home-incomplete" \
    timeout 30 sh install.sh --plan > "$INCOMPLETE_OUT" 2>&1 || true
)

if grep -q 'detect.sh: No such file' "$INCOMPLETE_OUT"; then
    echo "FAIL: incomplete checkout crashed on missing sibling module instead of bootstrapping"
    fail=$((fail + 1))
elif grep -q 'fake pacman ' "$LOG_INCOMPLETE" 2>/dev/null; then
    echo "ok: incomplete module set detected and safely bootstrapped"
else
    echo "FAIL: incomplete module test failed to reach package manager:"
    head -20 "$INCOMPLETE_OUT" 2>/dev/null | sed 's/^/    /'
    fail=$((fail + 1))
fi

# 8e. Piped --verify does not hash dummy ./sh in CWD and outputs clean list
SH_DIR="$TMP/pipe-verify-cwd"
mkdir -p "$SH_DIR"
echo "# DUMMY SH" > "$SH_DIR/sh"
chmod +x "$SH_DIR/sh"
VERIFY_PIPE_OUT="$TMP/pipe-verify.out"
(
    cd "$SH_DIR"
    # shellcheck disable=SC2002
    cat "$REPO_ROOT/install.sh" | sh -s -- --verify > "$VERIFY_PIPE_OUT" 2>&1
)

if grep -q '(missing) sh' "$VERIFY_PIPE_OUT" || grep -q 'DUMMY SH' "$VERIFY_PIPE_OUT"; then
    echo "FAIL: piped --verify output corrupted by CWD ./sh"
    fail=$((fail + 1))
elif grep -q 'ui.sh (pinned bootstrap hash)' "$VERIFY_PIPE_OUT" && grep -q 'streamed via pipe' "$VERIFY_PIPE_OUT"; then
    echo "ok: piped --verify ignores CWD ./sh and cleanly outputs pinned bootstrap hashes"
else
    echo "FAIL: piped --verify did not produce expected output:"
    sed 's/^/    /' "$VERIFY_PIPE_OUT"
    fail=$((fail + 1))
fi

# 8f. Transient HTTP 503 during module bootstrap and repo setup: retry and succeed
if command -v python3 >/dev/null 2>&1; then
    LOG_RETRY="$TMP/install-retry-boot.log"
    : > "$LOG_RETRY"
    BOOT_RETRY_DIR="$TMP/repo-retry-boot"
    mkdir -p "$BOOT_RETRY_DIR"
    cp -f "$REPO_ROOT/install.sh" "$BOOT_RETRY_DIR/"

    # Mockbin with dnf/rpm fakes but real curl
    MOCKBIN_RETRY="$TMP/bin-retry"
    mkdir -p "$MOCKBIN_RETRY"
    for c in rpm dnf sudo systemctl pkexec gtk-update-icon-cache update-desktop-database; do
        ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN_RETRY/$c"
    done
    cp -f "$MOCKBIN/gpg" "$MOCKBIN_RETRY/gpg"

    PORT_FILE_BOOT="$TMP/server_port_boot"
    python3 -c "
import http.server
import socketserver
import os

detect_attempts = 0
key_attempts = 0
repo_root = '$REPO_ROOT'

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global detect_attempts, key_attempts
        relpath = self.path.lstrip('/')
        filepath = os.path.join(repo_root, relpath)
        if not os.path.exists(filepath):
            self.send_response(404)
            self.end_headers()
            return
        if os.path.basename(filepath) == 'detect.sh':
            detect_attempts += 1
            if detect_attempts <= 2:
                self.send_response(503)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Service Unavailable')
                return
        if 'idlescreen-key.gpg' in filepath:
            key_attempts += 1
            if key_attempts <= 2:
                self.send_response(503)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Service Unavailable')
                return
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()
        with open(filepath, 'rb') as f:
            self.wfile.write(f.read())
    def log_message(self, *args):
        pass

httpd = socketserver.TCPServer(('127.0.0.1', 0), Handler)
with open('$PORT_FILE_BOOT', 'w') as f:
    f.write(str(httpd.server_address[1]))
httpd.serve_forever()
" &
    _srv_boot_pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if [ -s "$PORT_FILE_BOOT" ]; then break; fi
        sleep 0.1
    done
    RETRY_BOOT_PORT=$(cat "$PORT_FILE_BOOT")
    RETRY_BOOT_OUT="$TMP/retry-boot.out"
    _boot_retry_rc=0
    (
        cd "$BOOT_RETRY_DIR"
        PATH="$MOCKBIN_RETRY:/usr/bin:/bin" \
        FAKE_LOG_FILE="$LOG_RETRY" \
        IDLESCREEN_OS_ID="fedora" \
        IDLESCREEN_REPO_BASE="http://127.0.0.1:${RETRY_BOOT_PORT}" \
        IDLESCREEN_RPM_GPG_DIR="$TMP/retry-rpm-gpg" \
        IDLESCREEN_YUM_REPOS_D="$TMP/retry-yum.repos.d" \
        XDG_RUNTIME_DIR="$TMP/xdg" \
        HOME="$TMP/home-retry" \
        timeout 30 sh install.sh --plan > "$RETRY_BOOT_OUT" 2>&1
    ) || _boot_retry_rc=$?
    kill "$_srv_boot_pid" 2>/dev/null || true
    wait "$_srv_boot_pid" 2>/dev/null || true

    if [ "$_boot_retry_rc" -eq 0 ] && grep -q 'Dry run complete. Exiting.' "$RETRY_BOOT_OUT"; then
        echo "ok: module bootstrapping and repo key downloads retried through transient 503 and succeeded"
    else
        echo "FAIL: bootstrapping or repo setup failed to recover from transient 503 (rc=$_boot_retry_rc, output:)"
        sed 's/^/    /' "$RETRY_BOOT_OUT"
        fail=$((fail + 1))
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
    exit 0
else
    echo "$fail check(s) failed"
    exit 1
fi
