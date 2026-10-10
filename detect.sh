# shellcheck shell=sh
# Detect OS / package manager / desktop
OS_ID="unknown"
OS_NAME="Unknown Linux"
OS_LIKE=""
OS_VERSION=""
ARCH="$(uname -m 2>/dev/null || echo unknown)"
PKG_MGR=""          # dnf | apt | pacman
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
    # Test/CI override so the mock-package-manager smoke test can exercise the
    # Arch branch on a runner whose own /etc/os-release is something else.
    if [ -n "${IDLESCREEN_OS_ID:-}" ]; then
        OS_ID="${IDLESCREEN_OS_ID}"
    fi
}

is_arch_family() {
    case "$OS_ID" in
        arch|endeavouros|garuda|cachyos|manjaro|artix|arcolinux|msys2|vanilla) return 0 ;;
    esac
    [ "$OS_LIKE" = "arch" ] && return 0
    return 1
}

detect_pkg_mgr() {
    # os-release decides, not PATH order: a Fedora host that happens to have
    # pacman installed must still install with dnf. The bare-pacman fallback
    # below only fires when neither dnf nor apt-get exists at all.
    if is_arch_family; then
        PKG_MGR="pacman"
        case "$OS_ID" in
            arch)         PKG_HOST_LABEL="PACMAN · Arch" ;;
            endeavouros)  PKG_HOST_LABEL="PACMAN · EndeavourOS" ;;
            garuda)       PKG_HOST_LABEL="PACMAN · Garuda" ;;
            cachyos)      PKG_HOST_LABEL="PACMAN · CachyOS" ;;
            *)            PKG_HOST_LABEL="PACMAN · Arch family" ;;
        esac
    elif command -v dnf >/dev/null 2>&1 || [ -x /usr/bin/dnf ]; then
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

    # No dnf/apt and no Arch-family os-release, but pacman is present: an
    # Arch host with an unusual /etc/os-release. Trust the binary.
    if [ -z "$PKG_MGR" ] && command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
        PKG_HOST_LABEL="PACMAN · ${OS_NAME}"
    fi
}

# True when a session shell owns idle timing and screen lock, and IdleScreen
# is expected to hand off to it rather than run its own idle timer.
#
# `omarchy-shell` alone is the signal. The interception shim is deliberately
# not part of the test: this runs during the identity phase, before the
# package that installs the shim has been deployed, so on a first install the
# shim is not on PATH yet. The installer only runs on hosts that are installing
# IdleScreen, so the shell's presence is sufficient.
SHELL_INTEGRATION=0

detect_shell_integration() {
    SHELL_INTEGRATION=0
    if command -v omarchy-shell >/dev/null 2>&1; then
        SHELL_INTEGRATION=1
    fi
}

detect_de() {
    _xd="${XDG_CURRENT_DESKTOP:-}"
    _xs="${XDG_SESSION_DESKTOP:-}"
    _de="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}"
    _de_lc=$(printf '%s' "$_de" | tr '[:upper:]' '[:lower:]')

    if printf '%s' "$_de_lc" | grep -q 'cosmic'; then
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
    : "$_xd" "$_xs"
}

build_pkg_list() {
    PKGS="idlescreen idlescreen-extras"

    case "$DE_ID" in
        cosmic)
            PKGS="$PKGS idle-cosmic"
            ;;
    esac

    printf '%s\n' "$PKGS"
}
