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
    # A name we ask for can be a real package or a virtual one that another
    # package provides: idle-savers has no .deb of its own, it is provided
    # by idlescreen. Both are installable, so both count as published.
    _avail=$(mktemp)
    {
        sed -n 's/^Package:[[:space:]]*//p' "$_idx"
        sed -n 's/^Provides:[[:space:]]*//p' "$_idx" \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*(.*$//'
    } | sed 's/[[:space:]]*$//' | grep -v '^$' | sort -u > "$_avail"
    for _p in $ALL_PKGS; do
        if ! grep -qx "$_p" "$_avail"; then
            err "package is not published in the IdleScreen channel: ${_p}"
            say "  ${DIM}index: ${REPO_BASE}/apt/dists/stable/main/binary-amd64/Packages${RESET}"
            rm -f "$_idx" "$_avail"
            exit 1
        fi
    done
    rm -f "$_idx" "$_avail"
    ok "pre-flight · all target packages are published"
}