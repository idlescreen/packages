# Post-install daemon and victory
# Returns 0 if unit active and session bus name is claimed.
_bus_name_up() {
    busctl --user --timeout=1 status io.github.idlescreen.Idle >/dev/null 2>&1
}

_daemon_ready() {
    systemctl --user is-active --quiet idle-daemon.service 2>/dev/null && _bus_name_up
}

# Patch known-bad activation line from older packages (dbus-broker rejects User=session).
_fix_dbus_activation_file() {
    _f="/usr/share/dbus-1/services/io.github.idlescreen.Idle.service"
    [ -f "$_f" ] || return 0
    if grep -q '^User=session$' "$_f" 2>/dev/null; then
        story_line "Fixing invalid User=session in D-Bus activation file…"
        if command -v sudo >/dev/null 2>&1; then
            sudo sed -i '/^User=session$/d' "$_f" 2>/dev/null || true
        fi
    fi
}

awaken_daemon() {
    step "[5/5]  Starting the idle user service"
    story_line "Ensuring ${HOME}/.config/idle exists (daemon config dir)…"
    mkdir -p "${HOME}/.config/idle" "${HOME}/.config/idlescreen"
    # Leftover atomic-write temps confuse nothing useful and clutter the dir.
    rm -f "${HOME}/.config/idle"/config.tmp.* 2>/dev/null || true

    _fix_dbus_activation_file

    # Package %post may still be finishing; give user units a moment.
    sleep 0.3

    story_line "Reloading user systemd units…"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user reset-failed idle-daemon.service 2>/dev/null || true

    # Always enable so the unit starts with the graphical session next login.
    story_line "systemctl --user enable idle-daemon.service…"
    systemctl --user enable idle-daemon.service 2>/dev/null || true

    # Clean restart: upgrade can leave a dying process holding the bus name.
    story_line "systemctl --user restart idle-daemon.service…"
    _start_out=$(systemctl --user restart idle-daemon.service 2>&1) || true
    if ! systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        warn "restart not active yet — stop + start…"
        [ -n "$_start_out" ] && dim "   ${_start_out}"
        systemctl --user stop idle-daemon.service 2>/dev/null || true
        sleep 0.4
        systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
        _start_out=$(systemctl --user start idle-daemon.service 2>&1) || true
        [ -n "$_start_out" ] && dim "   ${_start_out}"
    fi

    # Wait for Type=dbus to claim io.github.idlescreen.Idle.
    _i=0
    while [ "$_i" -lt 30 ]; do
        if _daemon_ready; then
            break
        fi
        sleep 0.2
        _i=$((_i + 1))
    done

    if _daemon_ready; then
        ok "idle-daemon.service is ${GREEN}${BOLD}active${RESET} (D-Bus name claimed)"
        return 0
    fi

    # Fallback: direct spawn only if nothing owns the name (unit race).
    if ! _bus_name_up && command -v idle-daemon >/dev/null 2>&1; then
        warn "user unit not ready — trying one-shot idle-daemon spawn…"
        idle-daemon daemon >/dev/null 2>&1 &
        sleep 0.8
        systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
        systemctl --user start idle-daemon.service 2>/dev/null || true
        sleep 0.5
    fi

    if _daemon_ready || _bus_name_up; then
        ok "idle-daemon is up (bus/service)"
        return 0
    fi

    warn "idle-daemon D-Bus service is not ready."
    dim "   Packages may still be installed. Diagnose with:"
    dim "   systemctl --user status idle-daemon.service"
    dim "   journalctl --user -u idle-daemon.service -n 30 --no-pager"
    dim "   or: idlescreen doctor --fix"
    if command -v systemctl >/dev/null 2>&1; then
        dim "   unit: $(systemctl --user is-active idle-daemon.service 2>&1 || true)"
        dim "   $(systemctl --user status idle-daemon.service --no-pager -l 2>&1 | head -n 8 | tr '\n' ' ')"
    fi
    journalctl --user -u idle-daemon.service -n 12 --no-pager 2>/dev/null \
        | while IFS= read -r _line; do dim "   ${_line}"; done || true
}

victory() {
    _pkgs="$1"
    say ""
    # Idempotent: re-runs re-audit whatever is on disk now, so the JSONL log
    # records the post-install state even when the deploy phase was a no-op.
    if command -v audit_installed_plugins >/dev/null 2>&1; then
        audit_installed_plugins
    fi
    # Per Sprint 09 A09-H11: end-of-install should leave the user with a
    # working preview, not a banner. Best-effort: try the first detected
    # saver; if the daemon is up and idle is enabled, run a 5-second
    # preview so the user sees the tool actually working. Non-blocking:
    # any failure here is just a hint, not an error.
    if [ -z "${MISSING_AFTER:-}" ] \
        && command -v idlescreen >/dev/null 2>&1 \
        && systemctl --user is-active --quiet idle-daemon.service 2>/dev/null; then
        _first_saver=$(find /usr/libexec/idle/screensavers -maxdepth 1 -name 'libscreensaver_*.so' 2>/dev/null \
            | head -n1 | xargs -I{} basename {} .so 2>/dev/null \
            | sed 's/^libscreensaver_//')
        if [ -n "${_first_saver:-}" ]; then
            say ""
            say "${DIM}Demonstrating ${_first_saver} for 5 seconds …${RESET}"
            say "${DIM}(press any key to skip)${RESET}"
            say ""
            if command -v timeout >/dev/null 2>&1; then
                timeout 5 idlescreen preview "$_first_saver" >/dev/null 2>&1 || true
            else
                idlescreen preview "$_first_saver" >/dev/null 2>&1 &
                _prev=$!
                sleep 5
                kill "$_prev" 2>/dev/null || true
            fi
        fi
    fi
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
    say "    ${CYAN}idlescreen enable${RESET}     enable daemon"
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
