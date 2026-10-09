#!/bin/sh
# Test --verify-self edge cases beyond the happy/wrong-hash cases.
set -eu
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"
LOG="$TMP/log"
: > "$LOG"
export FAKE_LOG_FILE="$LOG"
cat > "$MOCKBIN/_dispatch" <<'eof'
#!/bin/sh
cmd=$(basename "$0")
LOG_FILE="${FAKE_LOG_FILE:-/dev/null}"
printf '%s fake %s %s\n' "$(date +%s)" "$cmd" "$*" >> "$LOG_FILE"
case "$cmd" in
    rpm|dpkg-query|curl|dnf|apt-get|systemctl|pkexec|gtk-update-icon-cache|update-desktop-database) exit 0 ;;
esac
exit 0
eof
chmod +x "$MOCKBIN/_dispatch"
for c in rpm dpkg-query curl dnf apt-get sudo systemctl pkexec gtk-update-icon-cache update-desktop-database; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$c"
done
SCRIPT_DIR="$TMP/repo"
mkdir -p "$SCRIPT_DIR"
cp -f "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/install.sh" "$SCRIPT_DIR/"

fail=0
SCRIPT="$SCRIPT_DIR/install.sh"

if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT" --verify-self 2>/dev/null; then
    echo "FAIL: --verify-self with no expected should exit 2"
    fail=$((fail + 1))
else
    code=$?
    if [ "$code" -ne 2 ]; then
        echo "FAIL: --verify-self with no expected exit code was $code, want 2"
        fail=$((fail + 1))
    else
        echo "ok: --verify-self with no expected exits 2"
    fi
fi

HASH=$(PATH="/usr/bin:/bin" sha256sum "$SCRIPT" | awk '{print $1}')
OUT_NONEXIST="$TMP/nonexist.err"
if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT" \
    --verify-self "$HASH" "/nonexistent/install.sh" >/dev/null 2> "$OUT_NONEXIST"; then
    echo "FAIL: --verify-self with non-existent path returned success"
    fail=$((fail + 1))
else
    if grep -q 'file not found' "$OUT_NONEXIST"; then
        echo "ok: --verify-self with non-existent path refuses with explicit file not found"
    else
        echo "FAIL: --verify-self did not print 'file not found' error"
        cat "$OUT_NONEXIST"
        fail=$((fail + 1))
    fi
fi

OUT_SHORT="$TMP/short.err"
if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT" \
    --verify-self "deadbeef" "$SCRIPT" >/dev/null 2> "$OUT_SHORT"; then
    echo "FAIL: --verify-self with short hash returned success"
    fail=$((fail + 1))
else
    if grep -q 'expected 64-character sha256' "$OUT_SHORT"; then
        echo "ok: --verify-self with short hash refuses with length error"
    else
        echo "FAIL: --verify-self did not print length error"
        cat "$OUT_SHORT"
        fail=$((fail + 1))
    fi
fi

HASH_UPPER=$(printf '%s' "$HASH" | tr '[:lower:]' '[:upper:]')
if PATH="$MOCKBIN:/usr/bin:/bin" "$SCRIPT" \
    --verify-self "$HASH_UPPER" "$SCRIPT" >/dev/null 2>&1; then
    echo "ok: --verify-self with uppercase hash accepts"
else
    echo "FAIL: --verify-self with uppercase hash returned non-zero"
    fail=$((fail + 1))
fi

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
    exit 0
else
    echo "$fail check(s) failed"
    exit 1
fi