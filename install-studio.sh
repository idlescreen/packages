#!/bin/sh
# IdleScreen Studio installer — offline render Director (TUI) + render capability.
# Usage: curl -fsSL https://idlescreen.github.io/packages/install-studio.sh | sh
#
# Installs: idle-studio (Requires: render; recommends idle-savers + ffmpeg).
# Does NOT install the desktop screensaver stack (use install.sh for that).
# SPDX-License-Identifier: Apache-2.0

set -eu

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    ORANGE="\033[38;5;208m"
    CYAN="\033[38;5;51m"
    GREEN="\033[38;5;82m"
    YELLOW="\033[38;5;220m"
    DIM="\033[38;5;242m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    ORANGE="" CYAN="" GREEN="" YELLOW="" DIM="" BOLD="" RESET=""
fi

say()  { printf '%b\n' "$*"; }
ok()   { say " ${GREEN}✔${RESET} $*"; }
warn() { say " ${YELLOW}!${RESET} $*"; }
err()  { say " ${YELLOW}ERROR:${RESET} $*"; }
step() { say ""; say " ${CYAN}${BOLD}$*${RESET}"; }

REPO_BASE="https://idlescreen.github.io/packages"
# Product packages (order: capability then UI).
PKGS="render idle-studio"
# Strongly recommended for real encodes (plugins + ffmpeg encoder stack).
RECOMMENDS="idle-savers"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "need command: $1"
        exit 1
    }
}

is_dnf() { command -v dnf >/dev/null 2>&1 || [ -x /usr/bin/dnf ]; }
is_apt() { command -v apt-get >/dev/null 2>&1 || [ -x /usr/bin/apt-get ]; }

main() {
    say ""
    say "${ORANGE}${BOLD}IdleScreen Studio installer${RESET}"
    say "${DIM}  offline render · TUI Director · not the desktop screensaver stack${RESET}"
    say "${DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    step "[1/4]  Package manager"
    if is_dnf; then
        PKG=dnf
        ok "DNF · RPM host"
    elif is_apt; then
        PKG=apt
        ok "APT · Debian family"
    else
        err "need DNF or APT — see ${REPO_BASE}/"
        exit 1
    fi

    step "[2/4]  Opening the IdleScreen package channel"
    if [ "$PKG" = "dnf" ]; then
        need_cmd curl
        need_cmd sudo
        sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
            -o /etc/yum.repos.d/idlescreen.repo
        ok "/etc/yum.repos.d/idlescreen.repo"
        say "  ${DIM}package gpgcheck=1 · repo_gpgcheck=0${RESET}"
        sudo dnf clean metadata --repo=idlescreen >/dev/null 2>&1 || true
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
            || sudo dnf makecache --refresh >/dev/null 2>&1 \
            || warn "metadata refresh soft-failed — install will still try"
    else
        need_cmd curl
        need_cmd sudo
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" \
            | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
        ok "APT keyring"
        echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
            | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
        sudo apt-get update -qq
        ok "APT index updated"
    fi

    step "[3/4]  Installing Studio + render"
    say "  ${DIM}plan:${RESET} ${BOLD}${PKGS}${RESET}"
    say "  ${DIM}also:${RESET} ${RECOMMENDS} (plugins for effect discovery)"
    if [ "$PKG" = "dnf" ]; then
        # shellcheck disable=SC2086
        if ! sudo dnf install -y --refresh $PKGS $RECOMMENDS; then
            warn "install with savers failed — trying core only ($PKGS)"
            # shellcheck disable=SC2086
            sudo dnf install -y --refresh $PKGS || {
                err "dnf install failed for: $PKGS"
                exit 1
            }
        fi
    else
        # shellcheck disable=SC2086
        if ! sudo apt-get install -y $PKGS $RECOMMENDS; then
            warn "install with savers failed — trying core only ($PKGS)"
            # shellcheck disable=SC2086
            sudo apt-get install -y $PKGS || {
                err "apt-get install failed for: $PKGS"
                exit 1
            }
        fi
    fi

    step "[4/4]  Verifying"
    if command -v render >/dev/null 2>&1; then
        ok "render → $(command -v render)"
    else
        err "render not on PATH after install"
        exit 1
    fi
    if command -v idle-studio >/dev/null 2>&1; then
        ok "idle-studio → $(command -v idle-studio)"
    else
        err "idle-studio not on PATH after install"
        exit 1
    fi
    if command -v ffmpeg >/dev/null 2>&1; then
        ok "ffmpeg available (needed for real encodes)"
    else
        warn "ffmpeg not found — install ffmpeg for AV1 export"
    fi
    if [ -d /usr/libexec/idle/screensavers ] \
        && ls /usr/libexec/idle/screensavers/*.so >/dev/null 2>&1; then
        _n=$(ls /usr/libexec/idle/screensavers/*.so 2>/dev/null | wc -l)
        ok "saver plugins: ${_n} under /usr/libexec/idle/screensavers"
    else
        warn "no saver plugins found — install idle-savers for effect names"
    fi
    if render -e beams --duration 1s --dry-run >/dev/null 2>&1; then
        ok "render dry-run (beams 1s) ok"
    else
        warn "render dry-run failed (plugins missing?)"
    fi

    say ""
    say "  ${GREEN}${BOLD}Studio ready${RESET}"
    say "  ${DIM}note${RESET}     desktop screensaver is separate: install.sh / idlescreen"
    say "  ${DIM}open${RESET}     ${CYAN}idle-studio${RESET}     (TUI Director — no args)"
    say "  ${DIM}export${RESET}   ${CYAN}render -e beams --duration 10s -o ~/Videos/beams.mkv${RESET}"
    say "  ${DIM}remove${RESET}   ${CYAN}sudo dnf remove idle-studio render${RESET}"
    say "            ${DIM}# or: sudo apt remove idle-studio render${RESET}"
    say "  ${DIM}docs${RESET}     https://idlescreen.github.io/#studio"
    say "  ${DIM}pkgs${RESET}     ${REPO_BASE}/"
    say ""
}

main "$@"
