#!/bin/sh
# install-studio helper: preflight_packages — confirm every package
# we are about to request is actually published, BEFORE any root
# mutation.
#
# Reading the APT index is enough to catch a name that was never
# built; both formats index the same 19-package set.
#
# Failure modes:
#   - Fetch failure (offline / DNS): warning. The install below
#     will fail cleanly on its own.
#   - Definitely-missing name: fatal. Otherwise we'd import a
#     key and write /etc sources for an install that cannot
#     succeed.

preflight_packages() {
    need_cmd curl
    _idx=$(mktemp)
    if ! curl -fsSL "${REPO_BASE}/apt/dists/stable/main/binary-amd64/Packages" -o "$_idx"; then
        warn "could not fetch the package index for a pre-flight check — continuing"
        rm -f "$_idx"
        return 0
    fi
    for _p in $ALL_PKGS; do
        if ! grep -q "^Package: ${_p}\$" "$_idx"; then
            err "package is not published in the IdleScreen channel: ${_p}"
            say "  ${DIM}index: ${REPO_BASE}/apt/dists/stable/main/binary-amd64/Packages${RESET}"
            rm -f "$_idx"
            exit 1
        fi
    done
    rm -f "$_idx"
    ok "pre-flight · all target packages are published"
}