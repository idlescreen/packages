#!/bin/sh
# IdleScreen Installer
# Usage:
#   curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
#   curl -fsSL https://idlescreen.github.io/packages/install.sh -o install.sh && \
#       ./install.sh --verify && ./install.sh
#
# `--verify` prints the SHA-256 of this script plus any sibling files it
# sources. Compare those hashes against an out-of-band published copy
# (release notes, signed tag, social, etc.) before piping `sh` to it.
#
# `--verify-self <hex>` exits non-zero unless THIS script's SHA-256 matches
# the expected hex. Use for automated deploys to fail closed on a tampered
# download. Example:
#   curl -fsSL https://idlescreen.github.io/packages/install.sh -o install.sh && \
#       ./install.sh --verify-self 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08 install.sh && \
#       ./install.sh
#
# See TRUST.md for the full trust model and verification procedure.

# POSIX-safe: no pipefail — this script must run under `curl | sh` where sh
# may be dash (Debian/Ubuntu), and `set -o pipefail` is fatal there. Every
# security gate below (sha256 pins, key fingerprint) fails closed on empty
# output, so pipefail semantics are not load-bearing.
set -eu

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --plan|--dry-run)
            DRY_RUN=1
            ;;
    esac
done
REPO_BASE="${IDLESCREEN_REPO_BASE:-https://idlescreen.github.io/packages}"
MODULES="ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh"

# Handle `--verify` before sourcing anything else so the user can run it
# even if the helper files are missing.
case "${1:-}" in
    --verify|-V|verify)
        _script_path="$0"
        if command -v sha256sum >/dev/null 2>&1; then
            _hash_cmd="sha256sum"
        elif command -v shasum >/dev/null 2>&1; then
            _hash_cmd="shasum -a 256"
        else
            echo "verify: no sha256sum or shasum on PATH" >&2
            exit 1
        fi
        echo "=== SHA-256 of installer files ==="
        _dir="$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)"
        for _f in "$_script_path" \
                  "$_dir/ui.sh" \
                  "$_dir/detect.sh" \
                  "$_dir/repo.sh" \
                  "$_dir/install_core.sh" \
                  "$_dir/install_audit.sh" \
                  "$_dir/post_install.sh"; do
            if [ -f "$_f" ]; then
                $_hash_cmd "$_f" 2>/dev/null
            else
                echo "  (missing) $_f"
            fi
        done
        echo ""
        echo "Compare these hashes against an out-of-band published copy"
        echo "(GitHub release notes, signed commit, etc.) before running."
        exit 0
        ;;
    --verify-self)
        # Fail-closed self-check for automated deploys.
        _expected="${2:-}"
        _script_path="${3:-${0}}"
        if [ -z "$_expected" ]; then
            echo "verify-self: missing expected sha256" >&2
            echo "usage: $0 --verify-self <hex> [script-path]" >&2
            exit 2
        fi
        if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
            echo "verify-self: no sha256sum or shasum on PATH" >&2
            exit 1
        fi
        if command -v sha256sum >/dev/null 2>&1; then
            _actual=$(sha256sum "$_script_path" 2>/dev/null | awk '{print $1}')
        else
            _actual=$(shasum -a 256 "$_script_path" 2>/dev/null | awk '{print $1}')
        fi
        if [ "$_actual" != "$_expected" ]; then
            echo "verify-self: FAIL — expected $_expected, got $_actual" >&2
            exit 1
        fi
        echo "verify-self: OK ($_actual)"
        exit 0
        ;;
esac

# Resolve module directory: local checkout, or bootstrap from REPO_BASE (curl|sh).
# Fail closed if cd fails: sourcing from "." would source ui.sh from the
# caller's cwd (B5 forbidden path). Refuse to run if we cannot resolve
# our own directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" != "$(cd "$(dirname "$0")" && pwd)" ]; then
    echo "install: failed to resolve own script directory; refusing to run" >&2
    exit 1
fi
BOOTSTRAP_TMP=""
cleanup_bootstrap() {
    if [ -n "$BOOTSTRAP_TMP" ] && [ -d "$BOOTSTRAP_TMP" ]; then
        rm -rf "$BOOTSTRAP_TMP"
    fi
}
trap cleanup_bootstrap EXIT INT TERM

if [ ! -f "$SCRIPT_DIR/ui.sh" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "install: ui.sh missing and curl not available to bootstrap from $REPO_BASE" >&2
        exit 1
    fi
    BOOTSTRAP_TMP=$(mktemp -d)
    echo "Bootstrapping installer modules from ${REPO_BASE}…"
    for f in $MODULES; do
        curl -fsSL "${REPO_BASE}/${f}" -o "${BOOTSTRAP_TMP}/${f}" \
            || { echo "install: failed to download ${REPO_BASE}/${f}" >&2; exit 1; }
        
        # Verify the downloaded module hash to prevent supply chain injection during bootstrap.
        if command -v sha256sum >/dev/null 2>&1; then
            _dl_hash=$(sha256sum "${BOOTSTRAP_TMP}/${f}" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            _dl_hash=$(shasum -a 256 "${BOOTSTRAP_TMP}/${f}" | awk '{print $1}')
        else
            echo "install: no sha256sum or shasum available to verify bootstrap modules" >&2
            exit 1
        fi
        
        _expected_hash=""
        case "$f" in
            "ui.sh") _expected_hash="af4ba64b19c76a0dcfaf9b9536ed9551a708efe2c8fa4980e9603dc292e2851c" ;;
            "detect.sh") _expected_hash="74bfc7fc66a3554e324e9cc2684e5e1da7767a6622a238a0514655ae9ad59d93" ;;
            "repo.sh") _expected_hash="034ae9c8a2e290db538ea9602690a38604a4f2f740677d9b0f398f2ebb39bc77" ;;
            "install_core.sh") _expected_hash="18856b9a53482fd1092e9096cb0bdbb90d5dcedfdccb343ed7bb64d34fa1263f" ;;
            "install_audit.sh") _expected_hash="c98ef03512480e3fbb54cf35381227a901ce330a466e8023fae770d2246bec49" ;;
            "post_install.sh") _expected_hash="f9e3792b8feefe8e2415a7191ed65161d635d9d12d36d3e391506017f6b9eb91" ;;
            *) echo "install: unknown module $f" >&2; exit 1 ;;
        esac
        
        if [ "$_dl_hash" != "$_expected_hash" ]; then
            echo "install: hash mismatch on bootstrapped module ${f}!" >&2
            echo "install: expected $_expected_hash, got $_dl_hash" >&2
            exit 1
        fi

        # Mirror the runtime's signature posture: when the operator has
        # set IDLE_REQUIRE_MANIFEST_SIGNATURE=1, every downloaded module
        # must have a sibling .sig file that gpg accepts. If gpg or the
        # .sig is missing, refuse to source the module.
        if [ -n "${IDLE_REQUIRE_MANIFEST_SIGNATURE:-}" ]; then
            if ! command -v gpg >/dev/null 2>&1; then
                echo "install: IDLE_REQUIRE_MANIFEST_SIGNATURE=1 but gpg not on PATH" >&2
                exit 1
            fi
            curl -fsSL "${REPO_BASE}/${f}.sig" -o "${BOOTSTRAP_TMP}/${f}.sig" \
                || { echo "install: missing signature ${REPO_BASE}/${f}.sig" >&2; exit 1; }
            if ! gpg --no-tty --verify "${BOOTSTRAP_TMP}/${f}.sig" "${BOOTSTRAP_TMP}/${f}" >/dev/null 2>&1; then
                echo "install: signature verification FAILED for ${f}" >&2
                exit 1
            fi
        fi
    done
    SCRIPT_DIR="$BOOTSTRAP_TMP"
fi

# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/ui.sh"
# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/detect.sh"
# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/repo.sh"
# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/install_core.sh"
# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/install_audit.sh"
# shellcheck disable=SC1090,SC1091
. "$SCRIPT_DIR/post_install.sh"

main() {
    banner
    story_line "Preparing IdleScreen for this machine…"
    say ""
    countdown 3 "System scan"

    # --- Phase 1: identity ---
    step "[1/5]  Scanning host identity"
    read_os_release
    detect_pkg_mgr
    detect_de

    say "  ${DIM}os${RESET}       ${GREEN}${OS_NAME}${RESET}"
    if [ -n "$OS_VERSION" ]; then
        dim "          id=${OS_ID}  version=${OS_VERSION}  like=${OS_LIKE:-—}"
    fi
    say "  ${DIM}arch${RESET}     ${GREEN}${ARCH}${RESET}"
    say "  ${DIM}session${RESET}  ${GREEN}${SESSION_TYPE}${RESET}"
    say "  ${DIM}desktop${RESET}  ${GREEN}${DE_LABEL}${RESET}  ${DIM}(${DE_ID})${RESET}"
    say "  ${DIM}packages${RESET} ${GREEN}${PKG_HOST_LABEL}${RESET}"

    if [ -z "$PKG_MGR" ]; then
        say ""
        if [ "$OS_ID" = "arch" ] || [ "$OS_LIKE" = "arch" ]; then
            err "Arch Linux is not natively supported by this script yet."
            dim "  Please build from source using the PKGBUILD:"
            dim "  ${REPO_BASE}/arch/PKGBUILD"
        else
            err "No supported package manager (need DNF or APT)."
            dim "  Arch users: see ${REPO_BASE}/  → arch/"
        fi
        dim "  Manual:     ${REPO_BASE}/"
        exit 1
    fi

    pause 0.4

    # --- Phase 2: repo ---
    if [ "$PKG_MGR" = "dnf" ]; then
        setup_repo_dnf
    else
        setup_repo_apt
    fi

    pause 0.3

    # --- Phase 3: plan + survey installed vs channel ---
    PKGS=$(build_pkg_list)
    survey_modules "$PKGS"

    if [ "$DRY_RUN" = "1" ]; then
        say ""
        say "Dry run complete. Exiting."
        return 0
    fi

    # --- Phase 4: upgrade outdated + install missing + full re-sync ---
    install_packages "$PKGS"

    # --- Phase 5: daemon ---
    awaken_daemon

    victory "$PKGS"

    say ""
    say "Previewing IdleScreen beams for 5 seconds..."
    idlescreen preview beams --timeout 5 || true
}

main "$@"
