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

set -eu

# Handle `--verify` before sourcing anything else so the user can run it
# even if the helper files are missing.
case "${1:-}" in
    --verify|-V|verify)
        _script_path="$0"
        # shellcheck disable=SC2046
        if command -v sha256sum >/dev/null 2>&1; then
            _hash_cmd="sha256sum"
        elif command -v shasum >/dev/null 2>&1; then
            _hash_cmd="shasum -a 256"
        else
            echo "verify: no sha256sum or shasum on PATH" >&2
            exit 1
        fi
        echo "=== SHA-256 of installer files ==="
        for _f in "$_script_path" \
                  "$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)/ui.sh" \
                  "$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)/detect.sh" \
                  "$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)/repo.sh" \
                  "$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)/install_core.sh" \
                  "$(cd "$(dirname "$_script_path")" 2>/dev/null && pwd || echo .)/post_install.sh"; do
            [ -f "$_f" ] && $_hash_cmd "$_f" 2>/dev/null || echo "  (missing) $_f"
        done
        echo ""
        echo "Compare these hashes against an out-of-band published copy"
        echo "(GitHub release notes, signed commit, etc.) before running."
        exit 0
        ;;
esac

# To allow local running vs remote, we need to load modules.
# When run locally via curl | sh, these files won't be present unless we download them.
# We will source relative to this script if possible.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
. "$SCRIPT_DIR/ui.sh"
. "$SCRIPT_DIR/detect.sh"
. "$SCRIPT_DIR/repo.sh"
. "$SCRIPT_DIR/install_core.sh"
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
        err "No supported package manager (need DNF or APT)."
        dim "  Arch users: see ${REPO_BASE}/  → arch/"
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

    # --- Phase 4: upgrade outdated + install missing + full re-sync ---
    install_packages "$PKGS"

    # --- Phase 5: daemon ---
    awaken_daemon

    victory "$PKGS"
}

main "$@"
