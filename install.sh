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
# Modular packages + product metapackage `idlescreen` (so install/remove by brand name works).
build_pkg_list() {
    PKGS="idle-daemon idle-cli idle-savers idle-tui idlescreen"

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
    story_line "Writing IdleScreen DNF repo file…"
    pause 0.3
    sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
        -o /etc/yum.repos.d/idlescreen.repo
    ok "Repo written → ${BOLD}/etc/yum.repos.d/idlescreen.repo${RESET}"
    # Truth: packages are GPG-checked (gpgcheck=1); repo metadata itself is not
    # signed (repo_gpgcheck=0 in the .repo file).
    dim "   baseurl ${REPO_BASE}/rpm  ·  package gpgcheck=1  ·  repo_gpgcheck=0"
    story_line "Refreshing IdleScreen channel metadata…"
    sudo dnf clean metadata --repo=idlescreen >/dev/null 2>&1 || true
    _meta_ok=0
    if [ "$IS_TTY" -eq 1 ]; then
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 &
        if spin_while $! "syncing DNF metadata"; then
            _meta_ok=1
        elif sudo dnf makecache --refresh >/dev/null 2>&1; then
            _meta_ok=1
        fi
    else
        if sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
            || sudo dnf makecache --refresh >/dev/null 2>&1; then
            _meta_ok=1
        fi
    fi
    if [ "$_meta_ok" -eq 1 ]; then
        ok "DNF metadata refreshed for this session"
    else
        warn "Could not refresh DNF metadata — install will still try the channel"
    fi
}

setup_repo_apt() {
    step "[2/5]  Opening the package gate  ·  APT repository"
    story_line "Creating /etc/apt/keyrings if needed…"
    sudo mkdir -p /etc/apt/keyrings
    story_line "Downloading IdleScreen APT signing keyring…"
    if ! curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" \
        | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null; then
        err "Could not download APT keyring from ${REPO_BASE}/apt/idlescreen-keyring.gpg"
        exit 1
    fi
    ok "Keyring → ${BOLD}/etc/apt/keyrings/idlescreen-keyring.gpg${RESET}"
    story_line "Writing APT source list (stable/main, signed-by keyring)…"
    echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
        | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
    story_line "Running apt-get update…"
    if [ "$IS_TTY" -eq 1 ]; then
        sudo apt-get update -qq &
        spin_while $! "syncing APT metadata" || {
            err "apt-get update failed"
            exit 1
        }
    else
        sudo apt-get update -qq
    fi
    ok "APT index updated with IdleScreen source"
}

# True when version string $1 is older than $2 (sort -V). Equal → false.
version_is_older() {
    _a="$1"
    _b="$2"
    if [ -z "$_a" ] || [ -z "$_b" ]; then
        return 1
    fi
    if [ "$_a" = "$_b" ]; then
        return 1
    fi
    _first=$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | head -n 1)
    [ "$_first" = "$_a" ]
}

rpm_installed_ver() {
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null || true
}

rpm_available_ver() {
    # DNF5 uses --queryformat; older dnf used --qf. Prefer IdleScreen repo.
    _pkg="$1"
    _v=""
    # shellcheck disable=SC2086
    for _fmt_flag in "--queryformat=%{version}-%{release}\n" "--qf=%{version}-%{release}"; do
        _v=$(dnf -q repoquery --repo=idlescreen --latest-limit=1 \
            "$_fmt_flag" "$_pkg" 2>/dev/null | head -n 1 | tr -d '\r')
        # Reject empty or unexpanded format strings (dnf5 ignoring unknown flags).
        if [ -n "$_v" ] && ! printf '%s' "$_v" | grep -q '%{'; then
            printf '%s' "$_v"
            return 0
        fi
        _v=$(dnf -q repoquery --latest-limit=1 \
            "$_fmt_flag" "$_pkg" 2>/dev/null | head -n 1 | tr -d '\r')
        if [ -n "$_v" ] && ! printf '%s' "$_v" | grep -q '%{'; then
            printf '%s' "$_v"
            return 0
        fi
    done
    # Last resort: parse NEVRA from default output (name-epoch:ver-rel.arch or name-ver-rel.arch).
    _nevra=$(dnf -q repoquery --repo=idlescreen --latest-limit=1 "$_pkg" 2>/dev/null | head -n 1)
    if [ -z "$_nevra" ]; then
        _nevra=$(dnf -q repoquery --latest-limit=1 "$_pkg" 2>/dev/null | head -n 1)
    fi
    if [ -n "$_nevra" ]; then
        # Strip arch (.x86_64 / .noarch), then take version-release after name.
        _base=${_nevra%.*}
        _vr=$(printf '%s' "$_base" | sed -E 's/^[a-z0-9+._-]+-([0-9].*)$/\1/; t; s/^[a-z0-9+._-]+:([0-9].*)$/\1/')
        # Handle epoch: name-0:2.4.0-1
        _vr=$(printf '%s' "$_vr" | sed -E 's/^[0-9]+://')
        printf '%s' "$_vr"
        return 0
    fi
    printf ''
}

apt_installed_ver() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

apt_candidate_ver() {
    # apt-cache policy: "  Candidate: 2.3.6-1"
    apt-cache policy "$1" 2>/dev/null \
        | awk '/Candidate:/ { print $2; exit }' \
        | grep -v '^(none)$' || true
}

# Survey installed IdleScreen modules vs channel; set UPGRADE_PKGS / INSTALL_PKGS / CURRENT_PKGS.
survey_modules() {
    _pkgs="$1"
    UPGRADE_PKGS=""
    INSTALL_PKGS=""
    CURRENT_PKGS=""
    UPGRADE_COUNT=0
    INSTALL_COUNT=0
    CURRENT_COUNT=0

    step "[3/5]  Composing the install plan"
    story_line "Desktop profile → ${BOLD}${DE_LABEL}${RESET}"
    # Package set is the same on every DE except COSMIC (+idle-cosmic). Do not
    # imply Hyprland/GNOME get “more” than generic — that would be false.
    say "  ${GREEN}→${RESET} Core stack (all DEs): ${BOLD}idle-daemon idle-cli idle-savers idle-tui idlescreen${RESET}"
    say "  ${DIM}    idlescreen = product metapackage (install|remove by brand name)${RESET}"
    case "$DE_ID" in
        cosmic)
            say "  ${GREEN}→${RESET} COSMIC: also ${BOLD}idle-cosmic${RESET} (panel applet package)"
            ;;
        *)
            say "  ${GREEN}→${RESET} ${DE_LABEL}: no extra DE-specific packages"
            ;;
    esac
    say ""
    story_line "Surveying what is already on this host (installed vs channel)…"
    say "  ${DIM}plan:${RESET} ${BOLD}${_pkgs}${RESET}"
    say ""

    for _pkg in $_pkgs; do
        _inst=""
        _cand=""
        if [ "$PKG_MGR" = "dnf" ]; then
            if rpm -q "$_pkg" >/dev/null 2>&1; then
                _inst=$(rpm_installed_ver "$_pkg")
                _cand=$(rpm_available_ver "$_pkg")
            fi
        else
            if dpkg-query -W "$_pkg" >/dev/null 2>&1; then
                _inst=$(apt_installed_ver "$_pkg")
                _cand=$(apt_candidate_ver "$_pkg")
            fi
        fi

        if [ -z "$_inst" ]; then
            say "  ${ORANGE}○${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}not installed${RESET}  →  ${CYAN}install${RESET}"
            INSTALL_PKGS="${INSTALL_PKGS} ${_pkg}"
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
        elif [ -n "$_cand" ] && version_is_older "$_inst" "$_cand"; then
            say "  ${YELLOW}↑${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}${_inst}${RESET}  →  ${GREEN}${_cand}${RESET}  ${ORANGE}upgrade${RESET}"
            UPGRADE_PKGS="${UPGRADE_PKGS} ${_pkg}"
            UPGRADE_COUNT=$((UPGRADE_COUNT + 1))
        else
            if [ -n "$_cand" ]; then
                say "  ${GREEN}✔${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}${_inst}${RESET}  ${GREEN}matches channel${RESET}"
            else
                say "  ${GREEN}✔${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}${_inst}${RESET}  ${DIM}(installed; channel version unknown)${RESET}"
            fi
            CURRENT_PKGS="${CURRENT_PKGS} ${_pkg}"
            CURRENT_COUNT=$((CURRENT_COUNT + 1))
        fi
    done

    # trim leading spaces
    UPGRADE_PKGS=$(printf '%s' "$UPGRADE_PKGS" | sed 's/^ *//')
    INSTALL_PKGS=$(printf '%s' "$INSTALL_PKGS" | sed 's/^ *//')
    CURRENT_PKGS=$(printf '%s' "$CURRENT_PKGS" | sed 's/^ *//')

    say ""
    if [ "$UPGRADE_COUNT" -gt 0 ]; then
        say "  ${ORANGE}${BOLD}Survey: ${UPGRADE_COUNT} outdated module(s)${RESET} — will attempt upgrade to channel."
    fi
    if [ "$INSTALL_COUNT" -gt 0 ]; then
        say "  ${CYAN}${BOLD}Survey: ${INSTALL_COUNT} missing module(s)${RESET} — will attempt install."
    fi
    if [ "$UPGRADE_COUNT" -eq 0 ] && [ "$INSTALL_COUNT" -eq 0 ]; then
        say "  ${GREEN}${BOLD}Survey: planned modules look current${RESET} — will still re-sync (dnf/apt may no-op)."
    fi
    say "  ${BOLD}Will request:${RESET} ${CYAN}${_pkgs}${RESET}"
    pause 0.5
}

install_packages() {
    _pkgs="$1"
    step "[4/5]  Deploying modules into the system"
    say "  ${DIM}manifest:${RESET} ${BOLD}${_pkgs}${RESET}"
    say ""

    if [ "${UPGRADE_COUNT:-0}" -gt 0 ]; then
        countdown 3 "Module upgrade"
    elif [ "${INSTALL_COUNT:-0}" -gt 0 ]; then
        countdown 3 "Package deployment"
    else
        countdown 3 "Channel re-sync"
    fi

    if [ "$PKG_MGR" = "dnf" ]; then
        # Explicit upgrade path first so older installs are never skipped.
        if [ -n "${UPGRADE_PKGS:-}" ]; then
            story_line "Raising outdated IdleScreen modules to the current channel…"
            # shellcheck disable=SC2086
            if ! sudo dnf upgrade -y --refresh $UPGRADE_PKGS; then
                warn "dnf upgrade reported issues — continuing with install re-sync…"
            fi
        fi
        if [ -n "${INSTALL_PKGS:-}" ]; then
            story_line "Seating new IdleScreen modules…"
            # shellcheck disable=SC2086
            if ! sudo dnf install -y --refresh $INSTALL_PKGS; then
                err "dnf install failed for: $INSTALL_PKGS"
                exit 1
            fi
        fi
        # Full set re-sync: installs missing + upgrades any remaining lag.
        story_line "Re-syncing the full IdleScreen set against the channel…"
        # shellcheck disable=SC2086
        if ! sudo dnf upgrade -y --refresh $_pkgs; then
            warn "dnf upgrade (full set) soft-failed — trying install…"
        fi
        # shellcheck disable=SC2086
        if ! sudo dnf install -y --refresh $_pkgs; then
            err "dnf install failed for: $_pkgs"
            exit 1
        fi
        story_line "Verifying RPM database…"
        if ! rpm -q idle-daemon idle-cli >/dev/null 2>&1; then
            err "idle-daemon / idle-cli missing after install — dnf did not install packages"
            exit 1
        fi
        if ! rpm -q idlescreen >/dev/null 2>&1; then
            # Soft on older channels without the metapackage, but try once more.
            warn "Product package idlescreen missing — installing metapackage…"
            sudo dnf install -y --refresh idlescreen 2>/dev/null || true
        fi
        if ! rpm -q idlescreen >/dev/null 2>&1; then
            warn "idlescreen metapackage not on channel yet; modular idle-* packages are installed."
            warn "Remove with:  sudo dnf remove idle-daemon idle-cli idle-savers idle-tui idle-cosmic"
        fi
        say ""
        _missing=0
        for _pkg in $_pkgs; do
            if rpm -q "$_pkg" >/dev/null 2>&1; then
                ok "$(rpm -q "$_pkg")"
            else
                warn "$_pkg not present after deploy"
                # Metapackage may lag; modular core must exist.
                case "$_pkg" in
                    idle-daemon|idle-cli) _missing=1 ;;
                esac
            fi
        done
        if [ "$_missing" -ne 0 ]; then
            err "Core packages missing after dnf install — aborting"
            exit 1
        fi
    elif [ "$PKG_MGR" = "apt" ]; then
        if [ -n "${UPGRADE_PKGS:-}" ]; then
            story_line "Raising outdated IdleScreen modules to the current channel…"
            # shellcheck disable=SC2086
            if ! sudo apt-get install -y --only-upgrade $UPGRADE_PKGS; then
                warn "apt only-upgrade soft-failed — continuing with full install…"
            fi
        fi
        if [ -n "${INSTALL_PKGS:-}" ]; then
            story_line "Seating new IdleScreen modules…"
            # shellcheck disable=SC2086
            if ! sudo apt-get install -y $INSTALL_PKGS; then
                warn "Partial install failed — retrying core set…"
            fi
        fi
        story_line "Re-syncing the full IdleScreen set against the channel…"
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
        for _pkg in $_pkgs; do
            if dpkg-query -W "$_pkg" >/dev/null 2>&1; then
                ok "$(dpkg-query -W -f='${Package} ${Version}' "$_pkg")"
            else
                warn "$_pkg not present after deploy"
            fi
        done
    fi
    # Legacy dual-icon cleanup (pre-rename CosmicAppletIdle + idle-cli desktop).
    # Safe no-ops when files already gone; package post scripts do the same.
    story_line "Scrubbing legacy dual-icon desktop leftovers…"
    sudo rm -f \
        /usr/share/applications/com.system76.CosmicAppletIdle.desktop \
        /usr/share/icons/hicolor/scalable/apps/com.system76.CosmicAppletIdle-symbolic.svg \
        /usr/share/icons/hicolor/scalable/status/com.system76.CosmicAppletIdle-symbolic.svg \
        /usr/share/applications/idlescreen.desktop \
        2>/dev/null || true
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        sudo gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    # Post-deploy truth: recount what is actually installed now.
    PRESENT_COUNT=0
    MISSING_AFTER=""
    for _pkg in $_pkgs; do
        if [ "$PKG_MGR" = "dnf" ]; then
            if rpm -q "$_pkg" >/dev/null 2>&1; then
                PRESENT_COUNT=$((PRESENT_COUNT + 1))
            else
                MISSING_AFTER="${MISSING_AFTER} ${_pkg}"
            fi
        else
            if dpkg-query -W "$_pkg" >/dev/null 2>&1; then
                PRESENT_COUNT=$((PRESENT_COUNT + 1))
            else
                MISSING_AFTER="${MISSING_AFTER} ${_pkg}"
            fi
        fi
    done
    MISSING_AFTER=$(printf '%s' "$MISSING_AFTER" | sed 's/^ *//')
    PLANNED_COUNT=0
    for _ in $_pkgs; do
        PLANNED_COUNT=$((PLANNED_COUNT + 1))
    done

    say ""
    if [ -z "$MISSING_AFTER" ]; then
        ok "${BOLD}Deploy finished — all ${PRESENT_COUNT} planned package(s) present.${RESET}"
    else
        warn "Deploy finished — ${PRESENT_COUNT}/${PLANNED_COUNT} planned package(s) present."
        warn "Missing: ${MISSING_AFTER}"
    fi
}

awaken_daemon() {
    step "[5/5]  Starting the idle user service"
    story_line "Ensuring ${HOME}/.config/idle exists (daemon config dir)…"
    mkdir -p "${HOME}/.config/idle"
    story_line "Reloading user systemd units…"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
    story_line "systemctl --user enable --now idle-daemon.service…"
    if systemctl --user enable --now idle-daemon.service 2>/dev/null; then
        :
    else
        warn "enable --now returned non-zero (may need a graphical user session)"
    fi
    pause 0.4
    if systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        ok "idle-daemon.service is ${GREEN}${BOLD}active${RESET} (user session)"
    else
        warn "idle-daemon.service is not active right now."
        dim "   Packages may still be installed. Start later with:"
        dim "   systemctl --user enable --now idle-daemon.service"
        dim "   (requires a logged-in user session with systemd --user)"
    fi
}

victory() {
    _pkgs="$1"
    say ""
    if [ -z "${MISSING_AFTER:-}" ] && systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        _banner_title="INSTALL FINISHED"
        _banner_note="packages present · daemon active"
    elif [ -z "${MISSING_AFTER:-}" ]; then
        _banner_title="PACKAGES INSTALLED"
        _banner_note="daemon not active yet — see notes above"
    else
        _banner_title="INSTALL PARTIAL"
        _banner_note="some planned packages missing — see list above"
    fi
    # Victory box: 54-col inner, title centered (not left-padded %-20s — that
    # left the right ✦ floating and looked broken). Match format_victory_box.
    _v_inner=54
    _v_label="✦  ${_banner_title}  ✦"
    # bash ${#} counts characters under a UTF-8 locale (✦ is one char each).
    _v_llen=${#_v_label}
    _v_pad=$((_v_inner - _v_llen))
    if [ "$_v_pad" -lt 0 ]; then
        _v_body=$(printf '%s' "$_v_label" | cut -c1-"$_v_inner")
    else
        _v_left=$((_v_pad / 2))
        _v_right=$((_v_pad - _v_left))
        _v_body=$(printf '%*s%s%*s' "$_v_left" '' "$_v_label" "$_v_right" '')
    fi
    say "  ${GREEN}${BOLD}"
    # Hardcoded borders (54 ═) — avoid tr with multi-byte box chars.
    say "        ╔══════════════════════════════════════════════════════╗"
    say "        ║                                                      ║"
    printf '        ║%s║\n' "$_v_body"
    say "        ║                                                      ║"
    say "        ╚══════════════════════════════════════════════════════╝"
    say "${RESET}"
    say "  ${DIM}note${RESET}     ${_banner_note}"
    say "  ${DIM}host${RESET}     ${OS_NAME}  (${ARCH})"
    say "  ${DIM}desktop${RESET}  ${DE_LABEL}"
    say "  ${DIM}channel${RESET}  ${PKG_HOST_LABEL}"
    say "  ${DIM}plan${RESET}     ${_pkgs}"
    if [ -n "${PRESENT_COUNT:-}" ] && [ -n "${PLANNED_COUNT:-}" ]; then
        say "  ${DIM}present${RESET}  ${PRESENT_COUNT}/${PLANNED_COUNT} planned package(s) on the system now"
    fi
    if [ "${UPGRADE_COUNT:-0}" -gt 0 ]; then
        say "  ${DIM}survey${RESET}   ${UPGRADE_COUNT} were outdated before deploy (upgrade was requested)"
    fi
    if [ "${INSTALL_COUNT:-0}" -gt 0 ]; then
        say "  ${DIM}survey${RESET}   ${INSTALL_COUNT} were missing before deploy (install was requested)"
    fi
    if [ -n "${MISSING_AFTER:-}" ]; then
        say "  ${YELLOW}missing${RESET}  ${MISSING_AFTER}"
    fi
    say ""

    case "$DE_ID" in
        cosmic)
            if [ "$PKG_MGR" = "dnf" ] && rpm -q idle-cosmic >/dev/null 2>&1; then
                say "  ${ORANGE}${BOLD}COSMIC${RESET}  Package ${BOLD}idle-cosmic${RESET} is installed."
                say "           Add the applet from panel settings if it is not docked yet."
            elif [ "$PKG_MGR" = "apt" ] && dpkg-query -W idle-cosmic >/dev/null 2>&1; then
                say "  ${ORANGE}${BOLD}COSMIC${RESET}  Package ${BOLD}idle-cosmic${RESET} is installed."
                say "           Add the applet from panel settings if it is not docked yet."
            else
                say "  ${ORANGE}${BOLD}COSMIC${RESET}  idle-cosmic was planned but is not installed."
            fi
            say ""
            ;;
        hyprland|sway)
            say "  ${CYAN}${BOLD}Compositor${RESET}  Control IdleScreen from the terminal:"
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
    say "  ${BOLD}Remove${RESET}"
    if [ "$PKG_MGR" = "dnf" ]; then
        say "    ${CYAN}sudo dnf remove idlescreen${RESET}"
        say "    ${DIM}# full wipe of modular packages if needed:${RESET}"
        say "    ${DIM}sudo dnf remove idle-daemon idle-cli idle-savers idle-tui idle-cosmic${RESET}"
    else
        say "    ${CYAN}sudo apt remove idlescreen${RESET}"
        say "    ${DIM}# full wipe if needed:${RESET}"
        say "    ${DIM}sudo apt remove idle-daemon idle-cli idle-savers idle-tui idle-cosmic${RESET}"
    fi
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
