#!/bin/sh
# IdleScreen Installer
# Usage: curl -fsSL https://idlescreen.github.io/packages/install.sh | sh

set -eu

# ---------------------------------------------------------------------------
# Terminal style
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    ORANGE="\033[38;5;208m"
    CYAN="\033[38;5;51m"
    GREEN="\033[38;5;82m"
    YELLOW="\033[38;5;220m"
    MAGENTA="\033[38;5;213m"
    DIM="\033[38;5;242m"
    BOLD="\033[1m"
    RESET="\033[0m"
    IS_TTY=1
else
    ORANGE="" CYAN="" GREEN="" YELLOW="" MAGENTA="" DIM="" BOLD="" RESET=""
    IS_TTY=0
fi

say()  { printf '%b\n' "$*"; }
dim()  { say " ${DIM}$*${RESET}"; }
ok()   { say " ${GREEN}✔${RESET} $*"; }
warn() { say " ${YELLOW}!${RESET} $*"; }
err()  { say " ${YELLOW}ERROR:${RESET} $*"; }
step() { say ""; say " ${CYAN}${BOLD}$*${RESET}"; }
pause() {
    # shellcheck disable=SC2039
    _s="${1:-0.35}"
    if [ "$IS_TTY" -eq 1 ]; then
        sleep "$_s" 2>/dev/null || sleep 1
    fi
}

# Spinner while a background command runs (pid in $1, label in $2)
spin_while() {
    _pid="$1"
    _label="$2"
    _i=0
    if [ "$IS_TTY" -eq 0 ]; then
        wait "$_pid"
        return $?
    fi
    while kill -0 "$_pid" 2>/dev/null; do
        case $((_i % 4)) in
            0) _ch='|' ;;
            1) _ch='/' ;;
            2) _ch='-' ;;
            3) _ch='\' ;;
        esac
        printf "\r ${CYAN}%s${RESET} %s…  " "$_ch" "$_label"
        _i=$((_i + 1))
        sleep 0.1 2>/dev/null || true
    done
    wait "$_pid"
    _rc=$?
    printf '\r\033[K'
    return $_rc
}

countdown() {
    _n="${1:-3}"
    _msg="${2:-Launching installer}"
    if [ "$IS_TTY" -eq 0 ]; then
        return 0
    fi
    while [ "$_n" -gt 0 ]; do
        printf "\r ${ORANGE}${BOLD}%s${RESET} in ${BOLD}%s${RESET}…   " "$_msg" "$_n"
        sleep 1
        _n=$((_n - 1))
    done
    printf '\r\033[K'
    say " ${ORANGE}${BOLD}$_msg${RESET} ${GREEN}now.${RESET}"
}

# ---------------------------------------------------------------------------
# Open the story
# ---------------------------------------------------------------------------
clear_soft() {
    if [ "$IS_TTY" -eq 1 ] && command -v clear >/dev/null 2>&1; then
        clear 2>/dev/null || true
    fi
}

banner() {
    clear_soft
    say ""
    say "${ORANGE}${BOLD}"
    cat <<'BANNER'
        ╔══════════════════════════════════════════════════════════╗
        ║                                                          ║
        ║      ██╗██████╗ ██╗     ███████╗                         ║
        ║      ██║██╔══██╗██║     ██╔════╝                         ║
        ║      ██║██║  ██║██║     █████╗                           ║
        ║      ██║██║  ██║██║     ██╔══╝                           ║
        ║      ██║██████╔╝███████╗███████╗                         ║
        ║      ╚═╝╚═════╝ ╚══════╝╚══════╝                         ║
        ║                                                          ║
        ║   ███████╗ ██████╗██████╗ ███████╗███████╗███╗   ██╗     ║
        ║   ██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝████╗  ██║     ║
        ║   ███████╗██║     ██████╔╝█████╗  █████╗  ██╔██╗ ██║     ║
        ║   ╚════██║██║     ██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║     ║
        ║   ███████║╚██████╗██║  ██║███████╗███████╗██║ ╚████║     ║
        ║   ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝     ║
        ║                                                          ║
        ╚══════════════════════════════════════════════════════════╝
BANNER
    say "${RESET}"
    say "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    say ""
}

story_line() {
    say "  ${MAGENTA}›${RESET} ${DIM}$*${RESET}"
    pause 0.25
}

# ---------------------------------------------------------------------------
# Detect OS / package manager / desktop
# ---------------------------------------------------------------------------
OS_ID="unknown"
OS_NAME="Unknown Linux"
OS_LIKE=""
OS_VERSION=""
ARCH="$(uname -m 2>/dev/null || echo unknown)"
PKG_MGR=""          # dnf | apt
PKG_HOST_LABEL=""
DE_ID="unknown"     # cosmic | gnome | kde | hyprland | sway | other
DE_LABEL="Unknown"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

read_os_release() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-$NAME}"
        OS_LIKE="${ID_LIKE:-}"
        OS_VERSION="${VERSION_ID:-}"
    fi
}

detect_pkg_mgr() {
    if command -v dnf >/dev/null 2>&1 || [ -x /usr/bin/dnf ]; then
        PKG_MGR="dnf"
        case "$OS_ID" in
            fedora)   PKG_HOST_LABEL="DNF · Fedora" ;;
            rhel|centos|rocky|almalinux|ol) PKG_HOST_LABEL="DNF · RHEL family" ;;
            nobara)   PKG_HOST_LABEL="DNF · Nobara" ;;
            *)        PKG_HOST_LABEL="DNF · RPM host" ;;
        esac
    elif command -v apt-get >/dev/null 2>&1 || [ -x /usr/bin/apt-get ]; then
        PKG_MGR="apt"
        case "$OS_ID" in
            ubuntu)   PKG_HOST_LABEL="APT · Ubuntu" ;;
            debian)   PKG_HOST_LABEL="APT · Debian" ;;
            pop)      PKG_HOST_LABEL="APT · Pop!_OS" ;;
            linuxmint) PKG_HOST_LABEL="APT · Linux Mint" ;;
            elementary) PKG_HOST_LABEL="APT · elementary OS" ;;
            *)        PKG_HOST_LABEL="APT · Debian family" ;;
        esac
    else
        PKG_MGR=""
        PKG_HOST_LABEL="unsupported"
    fi
}

# Normalize desktop environment into a product profile
detect_de() {
    _xd="${XDG_CURRENT_DESKTOP:-}"
    _xs="${XDG_SESSION_DESKTOP:-}"
    _de="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    _de_lc=$(printf '%s' "$_de" | tr '[:upper:]' '[:lower:]')

    # Binary / compositor probes beat env when present
    if [ -x /usr/bin/cosmic-panel ] || [ -x /usr/bin/cosmic-comp ] \
        || printf '%s' "$_de_lc" | grep -q 'cosmic'; then
        DE_ID="cosmic"
        DE_LABEL="COSMIC Desktop"
        return
    fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
        || printf '%s' "$_de_lc" | grep -q 'hyprland'; then
        DE_ID="hyprland"
        DE_LABEL="Hyprland"
        return
    fi
    if [ -n "${SWAYSOCK:-}" ] || printf '%s' "$_de_lc" | grep -q 'sway'; then
        DE_ID="sway"
        DE_LABEL="Sway"
        return
    fi
    if printf '%s' "$_de_lc" | grep -Eq 'gnome|ubuntu:gnome|pop:gnome'; then
        DE_ID="gnome"
        DE_LABEL="GNOME"
        return
    fi
    if printf '%s' "$_de_lc" | grep -Eq 'kde|plasma'; then
        DE_ID="kde"
        DE_LABEL="KDE Plasma"
        return
    fi
    if printf '%s' "$_de_lc" | grep -q 'xfce'; then
        DE_ID="xfce"
        DE_LABEL="Xfce"
        return
    fi
    if [ -n "$_de" ]; then
        DE_ID="other"
        DE_LABEL="$_de"
    else
        DE_ID="other"
        DE_LABEL="Generic / unknown DE"
    fi
    # silence unused
    : "$_xd" "$_xs"
}

# Build package list for this OS/DE.
build_pkg_list() {
    PKGS="idle-daemon idle-cli idle-savers idle-tui"

    case "$DE_ID" in
        cosmic)
            PKGS="$PKGS idle-cosmic"
            ;;
    esac

    printf '%s\n' "$PKGS"
}

# ---------------------------------------------------------------------------
# Repo + install
# ---------------------------------------------------------------------------
REPO_BASE="https://idlescreen.github.io/packages"

setup_repo_dnf() {
    step "[2/5]  Opening the package gate  ·  RPM repository"
    story_line "Fetching signed repository manifest…"
    pause 0.3
    sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
        -o /etc/yum.repos.d/idlescreen.repo
    ok "Repo written → ${BOLD}/etc/yum.repos.d/idlescreen.repo${RESET}"
    dim "   baseurl ${REPO_BASE}/rpm  ·  gpgcheck on"
}

setup_repo_apt() {
    step "[2/5]  Opening the package gate  ·  APT repository"
    story_line "Provisioning keyring vault…"
    sudo mkdir -p /etc/apt/keyrings
    story_line "Importing IdleScreen signing key…"
    curl -fsSL "${REPO_BASE}/idlescreen-keyring.gpg" \
        | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
    story_line "Registering stable/main channel…"
    echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
        | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
    story_line "Refreshing package index (this can take a moment)…"
    if [ "$IS_TTY" -eq 1 ]; then
        sudo apt-get update -qq &
        spin_while $! "syncing APT metadata" || {
            err "apt-get update failed"
            exit 1
        }
    else
        sudo apt-get update -qq
    fi
    ok "APT channel ready"
}

install_packages() {
    _pkgs="$1"
    step "[4/5]  Deploying modules into the system"
    say "  ${DIM}manifest:${RESET} ${BOLD}${_pkgs}${RESET}"
    say ""

    countdown 3 "Package deployment"

    if [ "$PKG_MGR" = "dnf" ]; then
        story_line "Calling dnf — resolving dependencies…"
        # shellcheck disable=SC2086
        if ! sudo dnf install -y $_pkgs; then
            err "dnf install failed for: $_pkgs"
            exit 1
        fi
        story_line "Verifying RPM database…"
        if ! rpm -q idle-daemon idle-cli >/dev/null 2>&1; then
            err "idle-daemon / idle-cli missing after install"
            exit 1
        fi
        say ""
        rpm -q idle-daemon idle-cli idle-tui idle-savers 2>/dev/null | while read -r line; do
            ok "$line"
        done
        if printf '%s' "$_pkgs" | grep -q idle-cosmic; then
            rpm -q idle-cosmic 2>/dev/null | while read -r line; do
                ok "$line"
            done
        fi
    elif [ "$PKG_MGR" = "apt" ]; then
        story_line "Calling apt-get — packing the payload…"
        # shellcheck disable=SC2086
        if ! sudo apt-get install -y $_pkgs; then
            warn "Full set failed — retrying without idle-tui (older indexes)…"
            _retry="idle-daemon idle-cli idle-savers"
            if printf '%s' "$_pkgs" | grep -q idle-cosmic; then
                _retry="$_retry idle-cosmic"
            fi
            # shellcheck disable=SC2086
            if ! sudo apt-get install -y $_retry; then
                err "apt-get install failed"
                exit 1
            fi
        fi
        story_line "Verifying dpkg database…"
        if ! dpkg-query -W idle-daemon idle-cli >/dev/null 2>&1; then
            err "idle-daemon / idle-cli missing after install"
            exit 1
        fi
        say ""
        dpkg-query -W idle-daemon idle-cli idle-tui idle-savers 2>/dev/null | while read -r line; do
            ok "$line"
        done || true
        if printf '%s' "$_pkgs" | grep -q idle-cosmic; then
            dpkg-query -W idle-cosmic 2>/dev/null | while read -r line; do
                ok "$line"
            done || true
        fi
    fi
    say ""
    ok "${BOLD}Payload secured.${RESET}"
}

awaken_daemon() {
    step "[5/5]  Awakening the idle daemon"
    story_line "Creating user config directories…"
    mkdir -p "${HOME}/.config/idle" "${HOME}/.config/idlescreen"
    story_line "Reloading user systemd units…"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
    story_line "Enabling idle-daemon.service…"
    systemctl --user enable --now idle-daemon.service 2>/dev/null || true
    pause 0.4
    if systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        ok "Daemon ${GREEN}${BOLD}active${RESET}  ·  idle-daemon.service"
    else
        warn "Daemon unit configured — start later with:"
        dim "   systemctl --user enable --now idle-daemon.service"
    fi
}

victory() {
    _pkgs="$1"
    say ""
    say "  ${GREEN}${BOLD}"
    cat <<'DONE'
        ╔══════════════════════════════════════════════════════╗
        ║                                                      ║
        ║              ✦  INSTALLATION COMPLETE  ✦             ║
        ║                                                      ║
        ║              Welcome to IdleScreen.                  ║
        ║                                                      ║
        ╚══════════════════════════════════════════════════════╝
DONE
    say "${RESET}"
    say "  ${DIM}host${RESET}     ${OS_NAME}  (${ARCH})"
    say "  ${DIM}desktop${RESET}  ${DE_LABEL}"
    say "  ${DIM}channel${RESET}  ${PKG_HOST_LABEL}"
    say "  ${DIM}modules${RESET}  ${_pkgs}"
    say ""

    case "$DE_ID" in
        cosmic)
            say "  ${ORANGE}${BOLD}COSMIC${RESET}  Panel applet is available — add IdleScreen from"
            say "           panel settings if it is not already docked."
            say ""
            ;;
        hyprland|sway)
            say "  ${CYAN}${BOLD}Compositor${RESET}  Control IdleScreen from the terminal TUI:"
            say "             ${BOLD}idlescreen tui${RESET}"
            say ""
            ;;
    esac

    say "  ${BOLD}Quick start${RESET}"
    say "    ${CYAN}idlescreen tui${RESET}        interactive dashboard"
    say "    ${CYAN}idlescreen status${RESET}     daemon + saver state"
    say "    ${CYAN}idlescreen preview beams${RESET}  try an effect"
    say "    ${CYAN}idlescreen doctor${RESET}     system diagnostics"
    say ""
    say "  ${DIM}docs  ${RESET}https://idlescreen.github.io"
    say "  ${DIM}pkgs  ${RESET}${REPO_BASE}/"
    say "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    say ""
}

# ---------------------------------------------------------------------------
# Main narrative
# ---------------------------------------------------------------------------
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

    # --- Phase 3: plan ---
    step "[3/5]  Composing the install plan"
    PKGS=$(build_pkg_list)
    story_line "Matching desktop profile → ${BOLD}${DE_LABEL}${RESET}"
    case "$DE_ID" in
        cosmic)
            say "  ${GREEN}→${RESET} COSMIC detected — including ${BOLD}idle-cosmic${RESET} panel applet"
            ;;
        hyprland)
            say "  ${GREEN}→${RESET} Hyprland detected — daemon + TUI + full saver set"
            ;;
        sway)
            say "  ${GREEN}→${RESET} Sway detected — daemon + TUI + full saver set"
            ;;
        gnome)
            say "  ${GREEN}→${RESET} GNOME detected — daemon + TUI + full saver set"
            ;;
        kde)
            say "  ${GREEN}→${RESET} KDE Plasma detected — daemon + TUI + full saver set"
            ;;
        *)
            say "  ${GREEN}→${RESET} Generic / other DE — core package set"
            ;;
    esac
    say "  ${GREEN}→${RESET} Always:     idle-daemon  idle-cli  idle-savers  idle-tui"
    if printf '%s' "$PKGS" | grep -q idle-cosmic; then
        say "  ${GREEN}→${RESET} Plus:       idle-cosmic"
    fi
    say ""
    say "  ${BOLD}Will install:${RESET} ${CYAN}${PKGS}${RESET}"
    pause 0.5

    # --- Phase 4: install ---
    install_packages "$PKGS"

    # --- Phase 5: daemon ---
    awaken_daemon

    victory "$PKGS"
}

main "$@"
