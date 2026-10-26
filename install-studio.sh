#!/bin/sh
# IdleScreen Studio installer
# Usage: curl -fsSL https://idlescreen.github.io/packages/install-studio.sh | sh
#
# The helper modules live under `install-studio-lib/`. This entry point
# bootstraps them into a private temp directory and verifies each one
# against a pinned SHA-256 before sourcing it — a module is never taken
# from the current working directory, and never from an unpinned download.
#
# Install story:
#   0. Pre-flight: confirm every package we are about to ask for
#      is actually published — before touching /etc or the rpm
#      keyring as root.
#   1. Write the IdleScreen package channel (DNF or APT).
#   2. Install idle-studio + render, then idle-savers when
#      available.
#   3. Confirm render, idle-studio, ffmpeg, plugins.
# Remove: sudo dnf remove idle-studio render   (or apt remove ...)
# SPDX-License-Identifier: Apache-2.0

set -eu

REPO_BASE="${IDLESCREEN_REPO_BASE:-https://idlescreen.github.io/packages}"
MODULES="00-color.sh 10-preflight.sh 20-ffmpeg.sh 30-channel.sh 40-install.sh 50-verify.sh"

_fetch() {
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

_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "install-studio: no sha256sum or shasum available to verify modules" >&2
        exit 1
    fi
}

_expected_hash() {
    case "$1" in
        "00-color.sh") echo "2107e83f7bca0de44a6b560a4bbfb27171aca0102d776153a9a5dcdddfae5e48" ;;
        "10-preflight.sh") echo "1223c16bda0c2dfee35bfaab11d971e5aeb04834b3d02e54d7586f881d3300d0" ;;
        "20-ffmpeg.sh") echo "89d4c292950eb098ed9f89619b7c8f4fbe9deddb3cb2ff4d612a4556d228e89d" ;;
        "30-channel.sh") echo "51fa0a6957be45fb2c56f158f5a621e34a8d27abb96a325f39b9f0d18178fbee" ;;
        "40-install.sh") echo "b6f95813be67ca29920268c2e7b077869a90c12bafbbecf34cf713b1139eee38" ;;
        "50-verify.sh") echo "1203c50c36c6de718522fe437416b3d7cb31c07a77e0879eed0e3af43041b04f" ;;
        *) echo "install-studio: unknown module $1" >&2; exit 1 ;;
    esac
}

# Resolve the helper directory. A local checkout uses the sibling
# `install-studio-lib/`; a piped install has no script directory at all
# and bootstraps from the channel. The current working directory is never
# a source: a planted `install-studio-lib/` would be executed with the
# caller's privileges.
LIB_DIR=""
case "$0" in
    */*)
        _self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
        if [ -n "$_self_dir" ] && [ -f "$_self_dir/install-studio-lib/00-color.sh" ]; then
            LIB_DIR="$_self_dir/install-studio-lib"
        fi
        ;;
esac

if [ -z "$LIB_DIR" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "install-studio: helper modules missing and curl not available to bootstrap from $REPO_BASE" >&2
        exit 1
    fi
    BOOTSTRAP_TMP=$(mktemp -d)
    trap 'rm -rf "$BOOTSTRAP_TMP"' EXIT INT TERM
    echo "Bootstrapping studio installer components from ${REPO_BASE}…"
    for f in $MODULES; do
        _fetch "${REPO_BASE}/install-studio-lib/${f}" "${BOOTSTRAP_TMP}/${f}" \
            || { echo "install-studio: failed to download ${REPO_BASE}/install-studio-lib/${f}" >&2; exit 1; }
        _expected=$(_expected_hash "$f")
        _actual=$(_sha256 "${BOOTSTRAP_TMP}/${f}")
        if [ "$_expected" != "$_actual" ]; then
            echo "install-studio: hash mismatch on module ${f}!" >&2
            echo "install-studio: expected $_expected, got $_actual" >&2
            exit 1
        fi
    done
    LIB_DIR="$BOOTSTRAP_TMP"
fi

for f in $MODULES; do
    # shellcheck disable=SC1090,SC1091
    . "${LIB_DIR}/${f}"
done

main "$@"
