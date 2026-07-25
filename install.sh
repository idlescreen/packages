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
    story_line "Fetching signed repository manifest…"
    pause 0.3
    sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
        -o /etc/yum.repos.d/idlescreen.repo
    ok "Repo written → ${BOLD}/etc/yum.repos.d/idlescreen.repo${RESET}"
    dim "   baseurl ${REPO_BASE}/rpm  ·  gpgcheck on"
    story_line "Refreshing IdleScreen channel metadata (so older builds are not left behind)…"
    # Force a fresh view of the channel; ignore soft failures and fall back.
    sudo dnf clean metadata --repo=idlescreen >/dev/null 2>&1 || true
    if [ "$IS_TTY" -eq 1 ]; then
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 &
        spin_while $! "syncing DNF metadata" || {
            sudo dnf makecache --refresh >/dev/null 2>&1 || true
        }
    else
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
            || sudo dnf makecache --refresh >/dev/null 2>&1 \
            || true
    fi
    ok "DNF channel metadata current"
}

setup_repo_apt() {
    step "[2/5]  Opening the package gate  ·  APT repository"
    story_line "Provisioning keyring vault…"
    sudo mkdir -p /etc/apt/keyrings
    story_line "Importing IdleScreen signing key…"
    curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" \
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
    say "  ${GREEN}→${RESET} Product:    idlescreen  ${DIM}(metapackage — dnf/apt install|remove idlescreen)${RESET}"
    if printf '%s' "$_pkgs" | grep -q idle-cosmic; then
        say "  ${GREEN}→${RESET} Plus:       idle-cosmic"
    fi
    say ""
    story_line "Surveying what is already on this host…"
    say "  ${DIM}manifest:${RESET} ${BOLD}${_pkgs}${RESET}"
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
                say "  ${GREEN}✔${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}${_inst}${RESET}  ${GREEN}current${RESET}"
            else
                say "  ${GREEN}✔${RESET} ${BOLD}${_pkg}${RESET}  ${DIM}${_inst}${RESET}  ${DIM}(no channel version yet)${RESET}"
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
        say "  ${ORANGE}${BOLD}Found ${UPGRADE_COUNT} outdated IdleScreen module(s)${RESET} — will raise to channel."
    fi
    if [ "$INSTALL_COUNT" -gt 0 ]; then
        say "  ${CYAN}${BOLD}Found ${INSTALL_COUNT} missing module(s)${RESET} — will install."
    fi
    if [ "$UPGRADE_COUNT" -eq 0 ] && [ "$INSTALL_COUNT" -eq 0 ]; then
        say "  ${GREEN}${BOLD}All planned modules already current${RESET} — will still re-sync with the channel."
    fi
    say "  ${BOLD}Will ensure:${RESET} ${CYAN}${_pkgs}${RESET}"
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
    say ""
    if [ "${UPGRADE_COUNT:-0}" -gt 0 ]; then
        ok "${BOLD}Payload secured — outdated modules raised.${RESET}"
    else
        ok "${BOLD}Payload secured.${RESET}"
    fi
}

awaken_daemon() {
    step "[5/5]  Awakening the idle daemon"
    story_line "Creating user config directories…"
    mkdir -p "${HOME}/.config/idle"
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
        ║             ✦  INSTALLATION COMPLETE  ✦              ║
        ║                                                      ║
        ╚══════════════════════════════════════════════════════╝
DONE
    say "${RESET}"
    say "  ${DIM}host${RESET}     ${OS_NAME}  (${ARCH})"
    say "  ${DIM}desktop${RESET}  ${DE_LABEL}"
    say "  ${DIM}channel${RESET}  ${PKG_HOST_LABEL}"
    say "  ${DIM}modules${RESET}  ${_pkgs}"
    if [ "${UPGRADE_COUNT:-0}" -gt 0 ]; then
        say "  ${DIM}raised${RESET}   ${GREEN}${UPGRADE_COUNT}${RESET} outdated module(s) upgraded to channel"
    fi
    if [ "${INSTALL_COUNT:-0}" -gt 0 ]; then
        say "  ${DIM}seated${RESET}   ${CYAN}${INSTALL_COUNT}${RESET} new module(s) installed"
    fi
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
