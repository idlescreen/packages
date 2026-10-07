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
"

_u_is_desktop_uid() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1000 ]
}

# Stop and disable idle-daemon for every logged-in desktop session. Runs
# before and after package removal: once the unit file is gone the second
# pass is the only thing that can stop a surviving process.
uninstall_stop_user_daemons() {
    if command -v loginctl >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        loginctl list-users --no-legend 2>/dev/null | while read -r uid user _rest; do
            _u_is_desktop_uid "$uid" || continue
            [ -n "$user" ] || continue
            [ -S "/run/user/$uid/bus" ] || continue
            if command -v runuser >/dev/null 2>&1; then
                runuser -u "$user" -- env \
                    XDG_RUNTIME_DIR="/run/user/$uid" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                    systemctl --user stop idle-daemon.service 2>/dev/null || true
                runuser -u "$user" -- env \
                    XDG_RUNTIME_DIR="/run/user/$uid" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                    systemctl --user disable idle-daemon.service 2>/dev/null || true
            else
                systemctl --user --machine="${user}@" stop idle-daemon.service 2>/dev/null || true
                systemctl --user --machine="${user}@" disable idle-daemon.service 2>/dev/null || true
            fi
        done
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -x idle-daemon 2>/dev/null || true
        pkill -f '/usr/bin/idle-daemon' 2>/dev/null || true
    fi
    if command -v systemctl >/dev/null 2>&1; then
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

# Trust anchors and channel config, all three channels.
uninstall_remove_repo_dropins() {
    sudo rm -f \
        /etc/yum.repos.d/idlescreen.repo \
        /etc/apt/sources.list.d/idlescreen.list \
        2>/dev/null || true
    sudo rm -f /etc/apt/keyrings/idlescreen-keyring.gpg 2>/dev/null || true
    sudo rm -f "${RPM_GPG_DIR}/idlescreen-key.gpg" 2>/dev/null || true
    # pacman: the sync database is the trust anchor here.
    sudo rm -rf "${PACMAN_XDG_D}" 2>/dev/null || true
    sudo rm -rf "${PACMAN_KEY_D}" 2>/dev/null || true
    # Session-shell integration shim. It lives in /usr/local/bin, outside the
    # package tree, so no package manager removes it for us. Leaving it would
    # shadow the shell's own launcher and call a daemon that is gone.
    if [ -f "$SESSION_SHIM" ]; then
        sudo rm -f "$SESSION_SHIM"
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
            "$_u_home/.local/share/idlescreen"; do
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
    ok "User and system configuration purged."
}

_u_desktop_uids() {
    if ! command -v loginctl >/dev/null 2>&1; then
        id -u
        return 0
    fi
    loginctl list-users --no-legend 2>/dev/null \
        | awk '{print $1}' | while read -r uid; do
            _u_is_desktop_uid "$uid" && printf '%s ' "$uid"
        done
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