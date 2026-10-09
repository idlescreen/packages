#!/bin/sh
# IdleScreen Installer
# Usage:
#   curl -fsSL https://idlescreen.github.io/install.sh | sh
#   curl -fsSL https://idlescreen.github.io/install.sh -o install.sh && \
#       ./install.sh --verify && ./install.sh
#
# `--verify` prints the SHA-256 of this script plus any sibling files it
# sources. Compare those hashes against an out-of-band published copy
# (release notes, signed tag, social, etc.) before piping `sh` to it.
#
# `--verify-self <hex>` exits non-zero unless THIS script's SHA-256 matches
# the expected hex. Use for automated deploys to fail closed on a tampered
# download. Example:
#   curl -fsSL https://idlescreen.github.io/install.sh -o install.sh && \
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
UNINSTALL=0
UNINSTALL_PURGE=0
for arg in "$@"; do
    case "$arg" in
        --plan|--dry-run)
            DRY_RUN=1
            ;;
        --uninstall)
            UNINSTALL=1
            ;;
        --purge)
            # Only meaningful with --uninstall; wipes user config as well.
            UNINSTALL_PURGE=1
            ;;
        -h|--help)
            cat <<'USAGE'
Usage: install.sh [options]

  (no options)        install / update IdleScreen
  --uninstall         remove IdleScreen, keeping user configuration
  --purge             with --uninstall: also remove user and system config
  --plan | --dry-run  print the install plan and exit
  --verify            print SHA-256 of the installer and its modules
  --verify-self HEX   fail unless this script's SHA-256 matches HEX
USAGE
            exit 0
            ;;
    esac
done
REPO_BASE="${IDLESCREEN_REPO_BASE:-https://idlescreen.github.io/packages}"
MODULES="ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh uninstall.sh"

# Handle `--verify` before sourcing anything else so the user can run it
# even if the helper files are missing.
case "${1:-}" in
    --verify|-V|verify)
        if command -v sha256sum >/dev/null 2>&1; then
            _hash_cmd="sha256sum"
        elif command -v shasum >/dev/null 2>&1; then
            _hash_cmd="shasum -a 256"
        else
            echo "verify: no sha256sum or shasum on PATH" >&2
            exit 1
        fi
        echo "=== SHA-256 of installer files ==="
        _bname="$(basename "$0" 2>/dev/null || echo "")"
        _is_script_file=0
        case "$_bname" in
            sh|bash|dash|ash|zsh|-*|"") ;;
            *)
                if [ -f "$0" ]; then
                    _is_script_file=1
                fi
                ;;
        esac

        if [ "$_is_script_file" -eq 1 ]; then
            $_hash_cmd "$0" 2>/dev/null
            _dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
        else
            echo "  (streamed via pipe) install.sh"
            _dir=""
        fi

        for _f in ui.sh detect.sh repo.sh install_core.sh install_audit.sh post_install.sh uninstall.sh; do
            if [ -n "$_dir" ] && [ -f "$_dir/$_f" ]; then
                $_hash_cmd "$_dir/$_f" 2>/dev/null
            else
                _expected=""
                case "$_f" in
                    "ui.sh") _expected="af4ba64b19c76a0dcfaf9b9536ed9551a708efe2c8fa4980e9603dc292e2851c" ;;
                    "detect.sh") _expected="a293a11e01be7e0c978035ddf3795f1d5abc047658a08aef09eb5b2a0f95c01f" ;;
                    "repo.sh") _expected="27f07f8face1703802646efe7accea076068209f8c3867700c203c57785d2677" ;;
                    "install_core.sh") _expected="c4200518095f97775e7ef66700dc4083da8e604504820fc61a01472207cfbf83" ;;
                    "install_audit.sh") _expected="b118d1d1effd0814e4092c6754f5740bee22ec4dd40b742a216d94b597ae3f74" ;;
                    "post_install.sh") _expected="cb7348bbf1d4a276ce30161cdee3d4c4eb70ac4a5f8c10a0ab3d26259469a6a2" ;;
                    "uninstall.sh") _expected="b58506e67439835c1e65756c81aa75ece32d34935a2160fc42bc008a778c542a" ;;
                esac
                if [ -n "$_dir" ]; then
                    echo "$_expected  $_dir/$_f (pinned bootstrap hash)"
                else
                    echo "$_expected  $_f (pinned bootstrap hash)"
                fi
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
        if [ ! -f "$_script_path" ]; then
            echo "verify-self: file not found: $_script_path" >&2
            exit 1
        fi
        if [ "${#_expected}" -ne 64 ]; then
            echo "verify-self: expected 64-character sha256, got ${#_expected}" >&2
            exit 1
        fi
        if command -v sha256sum >/dev/null 2>&1; then
            _actual=$(sha256sum "$_script_path" 2>/dev/null | awk '{print $1}')
        else
            _actual=$(shasum -a 256 "$_script_path" 2>/dev/null | awk '{print $1}')
        fi
        _expected_lower=$(printf '%s' "$_expected" | tr '[:upper:]' '[:lower:]')
        if [ "$_actual" != "$_expected_lower" ]; then
            echo "verify-self: FAIL — expected $_expected, got $_actual" >&2
            exit 1
        fi
        echo "verify-self: OK ($_actual)"
        exit 0
        ;;
esac

# Resolve module directory: local checkout, or bootstrap from REPO_BASE (curl|sh).
# Never source from "." when executing via pipe/stdin (B5 forbidden path).
_bname="$(basename "$0" 2>/dev/null || echo "")"
_is_script_file=0
case "$_bname" in
    sh|bash|dash|ash|zsh|-*|"") ;;
    *)
        if [ -f "$0" ]; then
            _is_script_file=1
        fi
        ;;
esac

_local_checkout=0
SCRIPT_DIR=""
if [ "$_is_script_file" -eq 1 ]; then
    _candidate_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    if [ -n "$_candidate_dir" ] && [ -d "$_candidate_dir" ]; then
        _has_all=1
        for _m in $MODULES; do
            if [ ! -f "$_candidate_dir/$_m" ]; then
                _has_all=0
                break
            fi
        done
        if [ "$_has_all" -eq 1 ]; then
            SCRIPT_DIR="$_candidate_dir"
            _local_checkout=1
        fi
    fi
fi

BOOTSTRAP_TMP=""
cleanup_bootstrap() {
    if [ -n "$BOOTSTRAP_TMP" ] && [ -d "$BOOTSTRAP_TMP" ]; then
        rm -rf "$BOOTSTRAP_TMP"
    fi
}
trap cleanup_bootstrap EXIT INT TERM

# Fetch a remote file with retries on transient errors (503, 5xx, 429, network drops)
fetch_file() {
    _url="$1"
    _out="$2"
    if curl --retry-all-errors --help >/dev/null 2>&1; then
        curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "$_url" -o "$_out"
    elif curl --retry-connrefused --help >/dev/null 2>&1; then
        curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused "$_url" -o "$_out"
    else
        curl -fsSL --retry 5 --retry-delay 2 "$_url" -o "$_out"
    fi
}

if [ "$_local_checkout" -eq 0 ]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "install: helper modules missing and curl not available to bootstrap from $REPO_BASE" >&2
        exit 1
    fi
    BOOTSTRAP_TMP=$(mktemp -d)
    echo "Bootstrapping installer modules from ${REPO_BASE}…"
    for f in $MODULES; do
        fetch_file "${REPO_BASE}/${f}" "${BOOTSTRAP_TMP}/${f}" \
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
            "detect.sh") _expected_hash="a293a11e01be7e0c978035ddf3795f1d5abc047658a08aef09eb5b2a0f95c01f" ;;
            "repo.sh") _expected_hash="27f07f8face1703802646efe7accea076068209f8c3867700c203c57785d2677" ;;
            "install_core.sh") _expected_hash="c4200518095f97775e7ef66700dc4083da8e604504820fc61a01472207cfbf83" ;;
            "install_audit.sh") _expected_hash="b118d1d1effd0814e4092c6754f5740bee22ec4dd40b742a216d94b597ae3f74" ;;
            "post_install.sh") _expected_hash="cb7348bbf1d4a276ce30161cdee3d4c4eb70ac4a5f8c10a0ab3d26259469a6a2" ;;
            "uninstall.sh") _expected_hash="b58506e67439835c1e65756c81aa75ece32d34935a2160fc42bc008a778c542a" ;;
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
            fetch_file "${REPO_BASE}/${f}.sig" "${BOOTSTRAP_TMP}/${f}.sig" \
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
. "$SCRIPT_DIR/uninstall.sh"
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
    detect_shell_integration

    # Removal never needs a working channel, so it runs before the repo gate
    # and after identity — a broken repo must not block removing a stack.
    if [ "$UNINSTALL" -eq 1 ]; then
        if [ -z "$PKG_MGR" ]; then
            err "No supported package manager (need DNF, APT or PACMAN)."
            exit 1
        fi
        uninstall_stack
        return 0
    fi

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
        err "No supported package manager (need DNF, APT or PACMAN)."
        dim "  Manual installs: ${REPO_BASE}/"
        exit 1
    fi

    pause 0.4

    # --- Phase 2: repo ---
    if [ "$PKG_MGR" = "dnf" ]; then
        setup_repo_dnf
    elif [ "$PKG_MGR" = "pacman" ]; then
        setup_repo_pacman
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
    say "Previewing IdleScreen ascii for 5 seconds..."
    idlescreen preview ascii --timeout 5 || true
}

main "$@"
