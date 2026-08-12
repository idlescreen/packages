# Install-time plugin audit (Sprint 02, DECISION-MANIFEST-01)
#
# Walks every installed screensaver .so, pairs it with its
# <stem>.idleplugin.toml, and appends one JSONL record per plugin so operators
# can answer "what capabilities did I actually install, and did they change?"
#
# System log is 0640 root-owned; falls back to the user's XDG state dir when
# /var/log is not writable (unprivileged or containerised installs).

AUDIT_SYS_DIR="/var/log/idlescreen"
AUDIT_SYS_LOG="${AUDIT_SYS_DIR}/install-audit.jsonl"
AUDIT_PLUGIN_DIRS="/usr/libexec/idle/screensavers /usr/libexec/trance/screensavers"

_audit_sha256() {
    [ -f "$1" ] || { printf 'null'; return 0; }
    if command -v sha256sum >/dev/null 2>&1; then
        printf '"%s"' "$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"
    elif command -v shasum >/dev/null 2>&1; then
        printf '"%s"' "$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)"
    else
        printf 'null'
    fi
}

# Scalar lookup: _audit_toml <file> <key>. Strips quotes/comments, first match.
_audit_toml() {
    [ -f "$1" ] || return 0
    sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null |
        head -n1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//; s/[[:space:]]*$//'
}

# Emit a TOML scalar as JSON: quoted, or bare for true/false/integers.
_audit_json_scalar() {
    case "$1" in
        "") printf 'null' ;;
        true|false) printf '%s' "$1" ;;
        *[!0-9]*) printf '"%s"' "$(printf '%s' "$1" | _audit_json_escape)" ;;
        *) printf '%s' "$1" ;;
    esac
}

# JSON-escape a string per RFC 8259 §7: backslash, double-quote, and
# all control characters (U+0000..=U+001F). Newlines and tabs in a
# plugin_id / plugin_version would break the audit log JSONL; this
# keeps the format valid even if a malicious manifest sneaks past the
# manifest gate.
#
# Implementation: sed first escapes backslash + double-quote. Then
# `tr` rewrites each literal control char to a sentinel letter
# (b/f/n/r/t). Then sed adds the backslash prefix. We do the tr-then-sed
# dance in the opposite order from a naive pipeline because sed's `\b`
# pattern is a word-boundary anchor, not a literal backslash — sed
# re-pass would mangle the result.
_audit_json_escape() {
    _c1=$(printf '\1')
    _c2=$(printf '\2')
    _c3=$(printf '\3')
    _c4=$(printf '\4')
    _c5=$(printf '\5')
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\b\f\n\r\t' '\1\2\3\4\5' |
    sed -e "s/$_c1/\\\\b/g" \
        -e "s/$_c2/\\\\f/g" \
        -e "s/$_c3/\\\\n/g" \
        -e "s/$_c4/\\\\r/g" \
        -e "s/$_c5/\\\\t/g"
}

# TOML array -> JSON array (already bracketed in the source file).
_audit_json_array() {
    [ -n "$1" ] || { printf '[]'; return 0; }
    printf '%s' "$1"
}

_audit_landlock_abi() {
    if [ -f /sys/kernel/security/landlock/abi_version ]; then
        cat /sys/kernel/security/landlock/abi_version 2>/dev/null || printf 'null'
    else
        printf 'null'
    fi
}

# Best-effort extraction of the signer identity from a detached .sig file.
# We do NOT verify the signature here — only inspect the OpenPGP packet
# to recover the signing keyid (4-byte, hex). Returns "null" on any failure
# so the audit log never fails the install.
_audit_signer_from_sig() {
    [ -f "$1" ] || { printf 'null'; return 0; }
    _gpg_out=$(gpg --list-packets --no-tty "$1" 2>/dev/null) || { printf 'null'; return 0; }
    _keyid=$(printf '%s\n' "$_gpg_out" | grep -i 'key.*id' 2>/dev/null | grep -oE '[0-9A-Fa-f]{16}' 2>/dev/null | head -n1)
    if [ -z "$_keyid" ]; then
        printf 'null'
    else
        _audit_json_scalar "$_keyid"
    fi
}

# Resolve a writable audit log path, creating the directory. Echoes the path.
_audit_log_path() {
    if mkdir -p "$AUDIT_SYS_DIR" 2>/dev/null && : >>"$AUDIT_SYS_LOG" 2>/dev/null; then
        chmod 0640 "$AUDIT_SYS_LOG" 2>/dev/null || true
        printf '%s' "$AUDIT_SYS_LOG"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 &&
        sudo mkdir -p "$AUDIT_SYS_DIR" 2>/dev/null &&
        sudo touch "$AUDIT_SYS_LOG" 2>/dev/null; then
        sudo chmod 0640 "$AUDIT_SYS_LOG" 2>/dev/null || true
        printf '%s' "$AUDIT_SYS_LOG"
        return 0
    fi
    _fallback="${XDG_STATE_HOME:-$HOME/.local/state}/idle"
    mkdir -p "$_fallback" 2>/dev/null || return 1
    _fb_log="${_fallback}/install-audit.jsonl"
    # Must exist before the caller's `[ -w ]` check: -w is false for a path
    # that is merely creatable.
    : >>"$_fb_log" 2>/dev/null || return 1
    chmod 0640 "$_fb_log" 2>/dev/null || true
    printf '%s' "$_fb_log"
}

# Build one JSONL record for a single plugin .so.
_audit_record() {
    _so="$1"
    _ts="$2"
    _os="$3"
    _kernel="$4"
    _abi="$5"

    _base=$(basename "$_so")
    _stem=${_base%.so}
    _mf=$(dirname "$_so")/${_stem}.idleplugin.toml
    [ -f "$_mf" ] || _mf=""

    if [ -n "$_mf" ]; then
        _result="manifest_present"
        _mf_json="\"$_mf\""
    else
        _result="manifest_missing"
        _mf_json="null"
    fi

    printf '{"ts":"%s"' "$_ts"
    printf ',"plugin_id":%s' "$(_audit_json_scalar "$(_audit_toml "$_mf" plugin_id)")"
    printf ',"plugin_version":%s' "$(_audit_json_scalar "$(_audit_toml "$_mf" plugin_version)")"
    printf ',"binary":"%s","binary_path":"%s"' "$_base" "$_so"
    printf ',"binary_sha256":%s' "$(_audit_sha256 "$_so")"
    printf ',"manifest_sha256":%s' "$(_audit_sha256 "$_mf")"
    printf ',"manifest_path":%s' "$_mf_json"
    printf ',"schema_version":%s' "$(_audit_json_scalar "$(_audit_toml "$_mf" schema_version)")"
    printf ',"api_version":%s' "$(_audit_json_scalar "$(_audit_toml "$_mf" api_version)")"
    printf ',"entry":{"runtime":%s,"library":%s}' \
        "$(_audit_json_scalar "$(_audit_toml "$_mf" runtime)")" \
        "$(_audit_json_scalar "$(_audit_toml "$_mf" library)")"
    printf ',"capabilities":{"network":%s,"audio_capture":%s,"audio_output":%s' \
        "$(_audit_json_scalar "$(_audit_toml "$_mf" network)")" \
        "$(_audit_json_scalar "$(_audit_toml "$_mf" audio_capture)")" \
        "$(_audit_json_scalar "$(_audit_toml "$_mf" audio_output)")"
    printf ',"filesystem_read":%s,"filesystem_write":%s}' \
        "$(_audit_json_array "$(_audit_toml "$_mf" filesystem_read)")" \
        "$(_audit_json_array "$(_audit_toml "$_mf" filesystem_write)")"
    printf ',"sandbox_profile":%s' "$(_audit_json_scalar "$(_audit_toml "$_mf" profile)")"
    # Signature state: recorded from the on-disk artifacts + the operator's
    # runtime opt-in env var. The host enforces IDLE_REQUIRE_MANIFEST_SIGNATURE;
    # the audit log mirrors the same posture so an operator reading the log can
    # see whether each plugin was deployed under a verifier.
    _sig="${_mf%.idleplugin.toml}.idleplugin.toml.sig"
    _sig_present="false"
    [ -f "$_sig" ] && _sig_present="true"
    _sig_hash="null"
    _signer="null"
    if [ -f "$_sig" ]; then
        _sig_hash=$(_audit_sha256 "$_sig")
        _signer=$(_audit_signer_from_sig "$_sig" 2>/dev/null || printf 'null')
    fi
    _enforce="false"
    [ -n "${IDLE_REQUIRE_MANIFEST_SIGNATURE:-}" ] && _enforce="true"
    printf ',"signature":{"enforce":%s,"present":%s,"sha256":%s,"signer":%s}' \
        "$_enforce" "$_sig_present" "$_sig_hash" "$_signer"
    printf ',"host":{"os":"%s","kernel":"%s","landlock_abi":%s}' "$_os" "$_kernel" "$_abi"
    printf ',"result":"%s"}\n' "$_result"
}

# Walk installed plugins and append one JSONL line each. Never fails the
# install: an unwritable log is a warning, not a deployment error.
audit_installed_plugins() {
    _log=$(_audit_log_path) || {
        warn "install audit: no writable log location — skipping"
        return 0
    }

    _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')
    _os=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-unknown}")
    _kernel=$(uname -r 2>/dev/null || printf 'unknown')
    _abi=$(_audit_landlock_abi)
    _count=0
    _missing=0

    for _dir in $AUDIT_PLUGIN_DIRS; do
        [ -d "$_dir" ] || continue
        for _so in "$_dir"/*.so; do
            [ -f "$_so" ] || continue
            _line=$(_audit_record "$_so" "$_ts" "$_os" "$_kernel" "$_abi")
            if [ -w "$_log" ]; then
                printf '%s\n' "$_line" >>"$_log"
            elif command -v sudo >/dev/null 2>&1; then
                printf '%s\n' "$_line" | sudo tee -a "$_log" >/dev/null 2>&1 || true
            fi
            _count=$((_count + 1))
            case "$_line" in
                *'"result":"manifest_missing"'*) _missing=$((_missing + 1)) ;;
            esac
        done
    done

    if [ "$_count" -eq 0 ]; then
        story_line "Install audit: no installed screensaver plugins found."
        return 0
    fi
    ok "Install audit: recorded ${_count} plugin(s) → ${_log}"
    if [ "$_missing" -gt 0 ]; then
        warn "Install audit: ${_missing} plugin(s) have no .idleplugin.toml manifest."
    fi
}
