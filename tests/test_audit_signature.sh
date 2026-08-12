#!/bin/sh
# Test signature field extraction and enforcement flag in audit log (H-A12)

set -eu
. /home/jeryd/Projects/idlescreen/packages/install_audit.sh

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

gpghomedir="$TMP/gpg"
mkdir -p "$gpghomedir"
chmod 700 "$gpghomedir"
GNUPGHOME="$gpghomedir" gpg --batch --passphrase '' --quick-generate-key "testkey@example.com" default default 1y >/dev/null 2>&1

mkdir -p "$TMP/screensavers"
touch "$TMP/screensavers/testplugin.so"
cat > "$TMP/screensavers/testplugin.idleplugin.toml" <<'EOF'
plugin_id = "test.plugin"
plugin_version = "1.0.0"
schema_version = 1
api_version = 1
runtime = "c"
library = "testplugin.so"
network = false
audio_capture = false
audio_output = false
filesystem_read = []
filesystem_write = []
profile = "strict"
EOF

GNUPGHOME="$gpghomedir" gpg --batch --detach-sign "$TMP/screensavers/testplugin.idleplugin.toml" >/dev/null 2>&1

# 1. Test keyid extraction from signature
extracted_signer=$(_audit_signer_from_sig "$TMP/screensavers/testplugin.idleplugin.toml.sig")
case "$extracted_signer" in
    '"'*'"') check "valid" "valid" "extracted hex keyid quoted string" ;;
    *) check "quoted string" "$extracted_signer" "extracted keyid" ;;
esac

# 2. Test record generation when signature present & enforcement active
record=$(IDLE_REQUIRE_MANIFEST_SIGNATURE=1 _audit_record "$TMP/screensavers/testplugin.so" "2026-08-11T12:00:00Z" "linux" "6.1.0" "1")

case "$record" in
    *'"signature":{"enforce":true,"present":true,"sha256":'*'"signer":'*'}'*)
        echo "  ok   record contains populated signature block with enforce=true, present=true"
        ;;
    *)
        echo "  FAIL record signature block invalid: $record"
        fail=$((fail + 1))
        ;;
esac

# 3. Test record generation when no signature present & enforcement inactive
rm -f "$TMP/screensavers/testplugin.idleplugin.toml.sig"
record_nosig=$(IDLE_REQUIRE_MANIFEST_SIGNATURE= _audit_record "$TMP/screensavers/testplugin.so" "2026-08-11T12:00:00Z" "linux" "6.1.0" "1")

case "$record_nosig" in
    *'"signature":{"enforce":false,"present":false,"sha256":null,"signer":null}'*)
        echo "  ok   record contains null signature sha256/signer when sig absent"
        ;;
    *)
        echo "  FAIL record signature block invalid when sig absent: $record_nosig"
        fail=$((fail + 1))
        ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "all signature audit tests passed"
    exit 0
else
    echo "$fail test(s) failed"
    exit 1
fi
