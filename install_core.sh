# Install logic
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
            warn "Product package idlescreen missing — installing metapackage…"
            if ! sudo dnf install -y --refresh idlescreen; then
                err "failed to install idlescreen metapackage"
                exit 1
            fi
        fi
        if ! rpm -q idlescreen >/dev/null 2>&1; then
            err "idlescreen metapackage still missing after install — aborting"
            exit 1
        fi
        say ""
        _missing=0
        for _pkg in $_pkgs; do
            if rpm -q "$_pkg" >/dev/null 2>&1; then
                ok "$(rpm -q "$_pkg")"
            else
                err "$_pkg not present after deploy"
                _missing=1
            fi
        done
        if [ "$_missing" -ne 0 ]; then
            err "Planned packages missing after dnf install — aborting"
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
            err "apt-get install failed for planned set: $_pkgs"
            exit 1
        fi
        story_line "Verifying dpkg database…"
        if ! dpkg-query -W idle-daemon idle-cli >/dev/null 2>&1; then
            err "idle-daemon / idle-cli missing after install"
            exit 1
        fi
        say ""
        _missing=0
        for _pkg in $_pkgs; do
            if dpkg-query -W "$_pkg" >/dev/null 2>&1; then
                ok "$(dpkg-query -W -f='${Package} ${Version}' "$_pkg")"
            else
                err "$_pkg not present after deploy"
                _missing=1
            fi
        done
        if [ "$_missing" -ne 0 ]; then
            err "Planned packages missing after apt install — aborting"
            exit 1
        fi
    fi
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

    # Record what actually landed on disk, including capability declarations.
    if command -v audit_installed_plugins >/dev/null 2>&1; then
        audit_installed_plugins
    fi
}
