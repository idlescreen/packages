# shellcheck shell=sh
# Standalone removal for IdleScreen.
#
# `remove-product-stack.sh` in the idlescreen package only fires when the
# metapackage's %preun/prerm hook runs, so it needs a reachable package
# manager and an intact metapackage. This is the operator-facing counterpart:
# reachable directly from install.sh, able to remove a half-installed stack,
# and covering pacman (which the package hook never did).
#
# User configuration is preserved unless --purge is passed.

# Product stack + official savers. Keep in sync with
# install_honesty::PRODUCT_STACK_ON_REMOVE and remove-product-stack.sh.
UNINSTALL_PKGS="
idle-cosmic
idle-tui
idle-cli
idle-savers
idle-saver-ascii
idle-saver-aurora
idle-saver-beams
idle-saver-bursts
idle-saver-chaos
idle-saver-cosmos
idle-saver-glyphs
idle-saver-gnats
idle-saver-hearth
idle-saver-radar
idle-saver-ripple
idle-saver-storm
idle-daemon
idlescreen
idlescreen-extras
"

_u_is_desktop_uid() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1000 ]
}

# Stop and disable idlescreen and idle-daemon for every logged-in desktop session. Runs
# before and after package removal: once the unit file is gone the second
# pass is the only thing that can stop a surviving process.
uninstall_stop_user_daemons() {
    if command -v loginctl >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        loginctl list-users --no-legend 2>/dev/null | while read -r uid user _rest; do
            _u_is_desktop_uid "$uid" || continue
            [ -n "$user" ] || continue
            [ -S "/run/user/$uid/bus" ] || continue
            if command -v runuser >/dev/null 2>&1; then
                for _svc in idlescreen.service idle-daemon.service; do
                    runuser -u "$user" -- env \
                        XDG_RUNTIME_DIR="/run/user/$uid" \
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        systemctl --user stop "$_svc" 2>/dev/null || true
                    runuser -u "$user" -- env \
                        XDG_RUNTIME_DIR="/run/user/$uid" \
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        systemctl --user disable "$_svc" 2>/dev/null || true
                done
            else
                for _svc in idlescreen.service idle-daemon.service; do
                    systemctl --user --machine="${user}@" stop "$_svc" 2>/dev/null || true
                    systemctl --user --machine="${user}@" disable "$_svc" 2>/dev/null || true
                done
            fi
        done
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -x idlescreen 2>/dev/null || true
        pkill -f '/usr/bin/idlescreen daemon' 2>/dev/null || true
        pkill -x idle-daemon 2>/dev/null || true
        pkill -f '/usr/bin/idle-daemon' 2>/dev/null || true
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable idlescreen.service 2>/dev/null || true
        systemctl --user disable idle-daemon.service 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

# _u_installed <pkg> — per-manager presence check.
_u_installed() {
    case "$PKG_MGR" in
        dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
        pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
        *)      dpkg-query -W "$1" >/dev/null 2>&1 ;;
    esac
}

# Present packages only. Removing something already gone is a spurious error
# on some managers and aborts the whole transaction on others.
_u_present() {
    _u_list=""
    for _u_p in $UNINSTALL_PKGS; do
        if _u_installed "$_u_p"; then
            _u_list="$_u_list $_u_p"
        fi
    done
    printf '%s' "${_u_list# }"
}

uninstall_remove_packages() {
    _u_todo=$(_u_present)
    if [ -z "$_u_todo" ]; then
        ok "No IdleScreen packages are installed."
        return 0
    fi
    say "  ${DIM}removing:${RESET} ${BOLD}${_u_todo}${RESET}"
    # shellcheck disable=SC2086
    case "$PKG_MGR" in
        dnf)
            # --nodeps breaks the circular meta-vs-module ordering, exactly as
            # remove-product-stack.sh does: removing the brand package is an
            # explicit request to wipe the product set.
            sudo rpm -e --nodeps $_u_todo 2>/dev/null || true
            ;;
        pacman)
            # dd = --nodeps --nosave; the metapackage depends on the modules
            # it is removing in the same transaction.
            sudo pacman -Rdd --noconfirm $_u_todo 2>/dev/null || true
            ;;
        *)
            sudo dpkg --remove --force-depends $_u_todo 2>/dev/null || true
            ;;
    esac

    _u_left=$(_u_present)
    if [ -n "$_u_left" ]; then
        warn "Some packages survived removal: ${_u_left}"
        return 1
    fi
    ok "All IdleScreen packages removed."
    return 0
}

# Fallback UI helpers if invoked outside install.sh
command -v say >/dev/null 2>&1 || say() { printf '%s\n' "$*"; }
command -v ok >/dev/null 2>&1 || ok() { printf '[OK] %s\n' "$*"; }
command -v step >/dev/null 2>&1 || step() { printf '==> %s\n' "$*"; }
command -v banner >/dev/null 2>&1 || banner() { :; }
command -v story_line >/dev/null 2>&1 || story_line() { printf '%s\n' "$*"; }
command -v dim >/dev/null 2>&1 || dim() { printf '%s\n' "$*"; }
command -v warn >/dev/null 2>&1 || warn() { printf '[WARN] %s\n' "$*"; }

# Trust anchors and channel config, all three channels.
uninstall_remove_repo_dropins() {
    _u_yum_d="${YUM_REPOS_D:-${IDLESCREEN_YUM_REPOS_D:-/etc/yum.repos.d}}"
    _u_apt_src_d="${APT_SOURCES_D:-${IDLESCREEN_APT_SOURCES_D:-/etc/apt/sources.list.d}}"
    _u_apt_key_d="${APT_KEYRINGS_D:-${IDLESCREEN_APT_KEYRINGS_D:-/etc/apt/keyrings}}"
    _u_rpm_gpg_d="${RPM_GPG_DIR:-${IDLESCREEN_RPM_GPG_DIR:-/etc/pki/rpm-gpg}}"
    _u_pacman_xdg_d="${PACMAN_XDG_D:-${IDLESCREEN_PACMAN_XDG_D:-/etc/pacman.d/idlescreen}}"
    _u_pacman_key_d="${PACMAN_KEY_D:-${IDLESCREEN_PACMAN_KEY_D:-/etc/pacman.d/gnupg}}"
    _u_shim="${SESSION_SHIM:-${IDLESCREEN_SESSION_SHIM:-/usr/local/bin/omarchy-launch-screensaver}}"

    sudo rm -f \
        "$_u_yum_d/idlescreen.repo" \
        "$_u_apt_src_d/idlescreen.list" \
        2>/dev/null || true
    sudo rm -f "$_u_apt_key_d/idlescreen-keyring.gpg" 2>/dev/null || true
    sudo rm -f "$_u_rpm_gpg_d/idlescreen-key.gpg" "$_u_rpm_gpg_d/RPM-GPG-KEY-idlescreen"* 2>/dev/null || true
    # pacman: the sync database is the trust anchor here.
    sudo rm -rf "$_u_pacman_xdg_d" 2>/dev/null || true
    sudo rm -rf "$_u_pacman_key_d" 2>/dev/null || true
    # Session-shell integration shim. It lives in /usr/local/bin, outside the
    # package tree, so no package manager removes it for us. Leaving it would
    # shadow the shell's own launcher and call a daemon that is gone.
    if [ -f "$_u_shim" ]; then
        sudo rm -f "$_u_shim"
        ok "Session-shell integration shim removed."
    fi
    ok "Repository drop-ins and trust anchors removed."
}

uninstall_prune_dirs() {
    sudo rmdir /usr/libexec/idle/screensavers 2>/dev/null || true
    sudo rmdir /usr/libexec/idle 2>/dev/null || true
    sudo rmdir /usr/lib/idle 2>/dev/null || true
    sudo rmdir /usr/libexec/idlescreen 2>/dev/null || true
    sudo rmdir /usr/share/idlescreen 2>/dev/null || true
}

# Opt-in only. Wipes config for the invoking user and every other desktop
# session, which is exactly why it is not the default.
uninstall_purge_user_data() {
    story_line "Purging user configuration…"
    _u_uids="$(_u_desktop_uids)"
    for _u_uid in $_u_uids; do
        _u_home=$(getent passwd "$_u_uid" 2>/dev/null | cut -d: -f6)
        [ -n "$_u_home" ] || continue
        for _u_d in \
            "$_u_home/.config/idlescreen" \
            "$_u_home/.config/idle" \
            "$_u_home/.config/trance" \
            "$_u_home/.local/share/idlescreen" \
            "$_u_home/.local/state/idlescreen" \
            "$_u_home/.cache/idlescreen"; do
            if [ -d "$_u_d" ]; then
                say "  ${DIM}rm -rf${RESET} ${BOLD}${_u_d}${RESET}"
                sudo rm -rf "$_u_d" 2>/dev/null || true
            fi
        done
    done
    if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
        for _u_d in \
            "$HOME/.config/idlescreen" \
            "$HOME/.config/idle" \
            "$HOME/.config/trance" \
            "$HOME/.local/share/idlescreen" \
            "$HOME/.local/state/idlescreen" \
            "$HOME/.cache/idlescreen"; do
            if [ -d "$_u_d" ]; then
                say "  ${DIM}rm -rf${RESET} ${BOLD}${_u_d}${RESET}"
                sudo rm -rf "$_u_d" 2>/dev/null || true
            fi
        done
    fi
    for _h in /home/*; do
        [ -d "$_h" ] || continue
        for _u_d in \
            "$_h/.config/idlescreen" \
            "$_h/.config/idle" \
            "$_h/.config/trance" \
            "$_h/.local/share/idlescreen" \
            "$_h/.local/state/idlescreen" \
            "$_h/.cache/idlescreen"; do
            if [ -d "$_u_d" ]; then
                say "  ${DIM}rm -rf${RESET} ${BOLD}${_u_d}${RESET}"
                sudo rm -rf "$_u_d" 2>/dev/null || true
            fi
        done
    done
    for _u_d in /etc/xdg/idlescreen /etc/idlescreen /etc/idle; do
        if [ -d "$_u_d" ]; then
            say "  ${DIM}rm -rf${RESET} ${BOLD}${_u_d}${RESET}"
            sudo rm -rf "$_u_d" 2>/dev/null || true
        fi
    done
    sudo rm -rf /run/user/*/idlescreen* /tmp/idlescreen* /var/tmp/idlescreen* 2>/dev/null || true
    ok "User and system configuration purged."
}

_u_desktop_uids() {
    _u_list=""
    if command -v loginctl >/dev/null 2>&1; then
        for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
            _u_is_desktop_uid "$uid" && _u_list="$_u_list $uid"
        done
    fi
    if [ -n "${SUDO_USER:-}" ]; then
        _suid=$(id -u "$SUDO_USER" 2>/dev/null || true)
        _u_is_desktop_uid "$_suid" && _u_list="$_u_list $_suid"
    fi
    _cuid=$(id -u 2>/dev/null || true)
    _u_is_desktop_uid "$_cuid" && _u_list="$_u_list $_cuid"
    if command -v getent >/dev/null 2>&1; then
        for uid in $(getent passwd 2>/dev/null | awk -F: '$3 >= 1000 && $3 < 60000 {print $3}'); do
            _u_list="$_u_list $uid"
        done
    fi
    # shellcheck disable=SC2086
    printf '%s\n' $_u_list 2>/dev/null | sort -u | tr '\n' ' '
}

uninstall_stack() {
    banner
    story_line "Removing IdleScreen from ${OS_NAME}…"
    say ""

    step "[1/3]  Stopping the idle daemon"
    uninstall_stop_user_daemons

    step "[2/3]  Removing packages"
    uninstall_remove_packages || true

    story_line "Removing repository configuration…"
    uninstall_remove_repo_dropins
    uninstall_prune_dirs

    step "[3/3]  Final sweep"
    # Units are gone by now; this is what actually stops a surviving process.
    uninstall_stop_user_daemons

    if [ "${UNINSTALL_PURGE:-0}" -eq 1 ]; then
        uninstall_purge_user_data
    else
        say ""
        dim "User configuration kept. Re-run with --purge to remove it."
    fi

    say ""
    ok "${BOLD}IdleScreen removed.${RESET}"
    dim "  Reinstall: curl -fsSL https://idlescreen.github.io/install.sh | sh"
    say ""
}

if [ "${0##*/}" = "uninstall.sh" ]; then
    _script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    if [ -f "$_script_dir/ui.sh" ]; then
        # shellcheck disable=SC1091
        . "$_script_dir/ui.sh"
    fi
    if [ -f "$_script_dir/detect.sh" ]; then
        # shellcheck disable=SC1091
        . "$_script_dir/detect.sh"
    fi
    for _arg in "$@"; do
        case "$_arg" in
            --purge) UNINSTALL_PURGE=1 ;;
        esac
    done
    OS_NAME="${OS_NAME:-$(uname -s 2>/dev/null || echo "Linux")}"
    if [ -z "${PKG_MGR:-}" ]; then
        if command -v dnf >/dev/null 2>&1; then
            PKG_MGR="dnf"
        elif command -v pacman >/dev/null 2>&1; then
            PKG_MGR="pacman"
        else
            PKG_MGR="apt"
        fi
    fi
    uninstall_stack
fi