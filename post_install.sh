# Post-install daemon and victory
awaken_daemon() {
    step "[5/5]  Starting the idle user service"
    story_line "Ensuring ${HOME}/.config/idle exists (daemon config dir)…"
    mkdir -p "${HOME}/.config/idle" "${HOME}/.config/idlescreen"

    story_line "Reloading user systemd units…"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed idle-daemon.service 2>/dev/null || true

    # Always enable so the unit starts with the graphical session next login.
    story_line "systemctl --user enable idle-daemon.service…"
    systemctl --user enable idle-daemon.service 2>/dev/null || true

    story_line "systemctl --user start idle-daemon.service…"
    if ! systemctl --user start idle-daemon.service 2>/dev/null; then
        warn "start returned non-zero — retrying once…"
        sleep 0.5
        systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
        systemctl --user start idle-daemon.service 2>/dev/null || true
    fi

    # Wait briefly for Type=dbus to claim the bus name.
    _i=0
    while [ "$_i" -lt 25 ]; do
        if systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
            break
        fi
        sleep 0.2
        _i=$((_i + 1))
    done

    if systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        ok "idle-daemon.service is ${GREEN}${BOLD}active${RESET} (user session)"
        return 0
    fi

    # Fallback: direct spawn if unit still dead (unit file race / session quirks).
    warn "user unit not active — trying direct idle-daemon spawn…"
    if command -v idle-daemon >/dev/null 2>&1; then
        idle-daemon daemon >/dev/null 2>&1 &
        sleep 0.6
    fi

    if systemctl --user is-active --quiet idle-daemon.service 2>/dev/null \
        || busctl --user status io.github.idlescreen.Idle >/dev/null 2>&1; then
        ok "idle-daemon is up (bus/service)"
        return 0
    fi

    warn "idle-daemon.service is not active right now."
    dim "   Packages may still be installed. Start with:"
    dim "   systemctl --user enable --now idle-daemon.service"
    dim "   or: idlescreen doctor --fix"
    dim "   (requires a logged-in user session with systemd --user)"
    if command -v systemctl >/dev/null 2>&1; then
        dim "   last status: $(systemctl --user is-active idle-daemon.service 2>&1 || true)"
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
    _v_inner=54
    _v_label="✦  ${_banner_title}  ✦"
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
        say "    ${DIM}# idlescreen 2.6+ also removes modules, savers, idle-cosmic, repo drop-in${RESET}"
    else
        say "    ${CYAN}sudo apt remove idlescreen${RESET}"
        say "    ${DIM}# idlescreen 2.6+ also removes modules, savers, idle-cosmic, APT list drop-in${RESET}"
    fi
    say ""
    say "  ${DIM}docs  ${RESET}https://idlescreen.github.io"
    say "  ${DIM}pkgs  ${RESET}${REPO_BASE}/"
    say "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    say ""
}
