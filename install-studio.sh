#!/bin/sh
# IdleScreen Studio installer
# Usage: curl -fsSL https://idlescreen.github.io/packages/install-studio.sh | sh
#
# Install story:
#   1. Write the IdleScreen package channel (DNF or APT).
#   2. Install metapackage idlescreen-studio (pulls idle-studio + render).
#   3. Install idle-savers when available (plugins).
#   4. Confirm render, idle-studio, ffmpeg, plugins.
# Remove: sudo dnf remove idlescreen-studio  (also removes idle-studio + render)
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
# Product metapackage (Requires idle-studio + render).
META="idlescreen-studio"
# Plugins for effect names.
SAVERS="idle-savers"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "need command: $1"
        exit 1
    }
}

is_dnf() { command -v dnf >/dev/null 2>&1 || [ -x /usr/bin/dnf ]; }
is_apt() { command -v apt-get >/dev/null 2>&1 || [ -x /usr/bin/apt-get ]; }

have_ffmpeg() {
    [ -x /usr/bin/ffmpeg ] || command -v ffmpeg >/dev/null 2>&1
}

ensure_ffmpeg() {
    if have_ffmpeg; then
        ok "ffmpeg → $(command -v ffmpeg 2>/dev/null || echo /usr/bin/ffmpeg)"
        return 0
    fi
    step "  Installing an ffmpeg package"
    if [ "$PKG" = "dnf" ]; then
        if sudo dnf install -y ffmpeg-free 2>/dev/null; then
            ok "installed ffmpeg-free"
        elif sudo dnf install -y ffmpeg 2>/dev/null; then
            ok "installed ffmpeg"
        else
            warn "could not install ffmpeg-free or ffmpeg — encodes need /usr/bin/ffmpeg"
            return 1
        fi
    else
        if sudo apt-get install -y ffmpeg 2>/dev/null; then
            ok "installed ffmpeg"
        else
            warn "could not install ffmpeg — encodes need the ffmpeg package"
            return 1
        fi
    fi
    have_ffmpeg
}

main() {
    say ""
    say "${ORANGE}${BOLD}IdleScreen Studio installer${RESET}"
    say "${DIM}  installs metapackage ${META} (idle-studio + render)${RESET}"
    say "${DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    step "[1/4]  Package manager"
    if is_dnf; then
        PKG=dnf
        ok "DNF · RPM host"
    elif is_apt; then
        PKG=apt
        ok "APT · Debian family"
    else
        err "need DNF or APT — ${REPO_BASE}/"
        exit 1
    fi

    step "[2/4]  IdleScreen package channel"
    if [ "$PKG" = "dnf" ]; then
        need_cmd curl
        need_cmd sudo
        sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
            -o /etc/yum.repos.d/idlescreen.repo
        ok "repo → /etc/yum.repos.d/idlescreen.repo"
        say "  ${DIM}baseurl ${REPO_BASE}/rpm · package gpgcheck=1 · repo_gpgcheck=0${RESET}"
        sudo dnf clean all --repo=idlescreen >/dev/null 2>&1 || true
        sudo rm -rf /var/cache/libdnf5/idlescreen-* 2>/dev/null || true
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
            || sudo dnf --setopt=idlescreen.metadata_expire=0 makecache --repo=idlescreen >/dev/null 2>&1 \
            || warn "metadata refresh soft-failed — install will still try the channel"
    else
        need_cmd curl
        need_cmd sudo
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" \
            | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
        ok "keyring → /etc/apt/keyrings/idlescreen-keyring.gpg"
        echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
            | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
        ok "source → /etc/apt/sources.list.d/idlescreen.list"
        sudo apt-get update -qq
        ok "APT index updated"
    fi

    step "[3/4]  Packages"
    say "  ${DIM}installing:${RESET} ${BOLD}${META}${RESET}  (pulls idle-studio + render)"
    say "  ${DIM}plugins:${RESET}   ${SAVERS}"
    if [ "$PKG" = "dnf" ]; then
        if ! sudo dnf install -y --refresh --setopt=idlescreen.metadata_expire=0 "$META" $SAVERS; then
            if ! sudo dnf install -y --refresh --setopt=idlescreen.metadata_expire=0 "$META"; then
                err "dnf could not install: $META"
                say "  ${DIM}If checksum errors: sudo dnf clean all && sudo rm -rf /var/cache/libdnf5/idlescreen-*${RESET}"
                exit 1
            fi
            warn "idle-savers not installed this run — effect names need plugins on disk"
        fi
    else
        if ! sudo apt-get install -y "$META" $SAVERS; then
            if ! sudo apt-get install -y "$META"; then
                err "apt-get could not install: $META"
                exit 1
            fi
            warn "idle-savers not installed this run — effect names need plugins on disk"
        fi
    fi
    ensure_ffmpeg || true

    step "[4/4]  Check"
    if rpm -q idlescreen-studio >/dev/null 2>&1 || dpkg-query -W idlescreen-studio >/dev/null 2>&1; then
        ok "metapackage idlescreen-studio present"
    else
        warn "metapackage idlescreen-studio not queried (ok if check tools differ)"
    fi
    if command -v render >/dev/null 2>&1; then
        ok "render → $(command -v render)"
    else
        err "render missing after install"
        exit 1
    fi
    if command -v idle-studio >/dev/null 2>&1; then
        ok "idle-studio → $(command -v idle-studio)"
    else
        err "idle-studio missing after install"
        exit 1
    fi
    if have_ffmpeg; then
        ok "ffmpeg on PATH"
    else
        warn "no ffmpeg yet — install ffmpeg-free (Fedora) or ffmpeg before encoding"
    fi
    if [ -d /usr/libexec/idle/screensavers ] \
        && ls /usr/libexec/idle/screensavers/*.so >/dev/null 2>&1; then
        _n=$(ls /usr/libexec/idle/screensavers/*.so 2>/dev/null | wc -l)
        ok "plugins: ${_n} under /usr/libexec/idle/screensavers"
    else
        warn "no plugins under /usr/libexec/idle/screensavers — install idle-savers"
    fi
    if render -e beams --duration 1s --dry-run >/dev/null 2>&1; then
        ok "render dry-run: beams · 1s"
    else
        warn "render dry-run did not complete (plugins or runtime)"
    fi

    say ""
    say "  ${GREEN}${BOLD}Install finished${RESET}"
    say "  ${DIM}open${RESET}     ${CYAN}idle-studio${RESET}"
    say "  ${DIM}export${RESET}   ${CYAN}render -e beams --duration 10s -o ~/Videos/beams.mkv${RESET}"
    if [ "$PKG" = "dnf" ]; then
        say "  ${DIM}remove${RESET}   ${CYAN}sudo dnf remove idlescreen-studio${RESET}"
        say "            ${DIM}# also removes idle-studio + render${RESET}"
    else
        say "  ${DIM}remove${RESET}   ${CYAN}sudo apt remove idlescreen-studio${RESET}"
        say "            ${DIM}# also removes idle-studio + render${RESET}"
    fi
    say "  ${DIM}docs${RESET}     https://idlescreen.github.io/#studio"
    say "  ${DIM}pkgs${RESET}     ${REPO_BASE}/"
    say ""
}

main "$@"
