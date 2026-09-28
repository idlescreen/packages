#!/bin/sh
# install-studio helper: verify the install landed + emit the
# "open / export / remove / docs" footer.
#
# We don't `require` render / idle-studio to be present — a partial
# install with the savers on a different host is still useful —
# but we DO fail loudly when render or idle-studio is missing
# after install_packages(), because the rest of the footer
# (`export`) won't work without them.

verify_install() {
    for _p in $STUDIO_PKGS; do
        if rpm -q "$_p" >/dev/null 2>&1 || dpkg-query -W "$_p" >/dev/null 2>&1; then
            ok "package ${_p} present"
        else
            warn "package ${_p} not queried (ok if check tools differ)"
        fi
    done
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
    set -- /usr/libexec/idle/screensavers/*.so
    if [ -d /usr/libexec/idle/screensavers ] && [ -e "$1" ]; then
        _n=$#
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
        say "  ${DIM}remove${RESET}   ${CYAN}sudo dnf remove ${STUDIO_PKGS}${RESET}"
        say "            ${DIM}# also removes idle-savers if you drop it${RESET}"
    else
        say "  ${DIM}remove${RESET}   ${CYAN}sudo apt remove ${STUDIO_PKGS}${RESET}"
        say "            ${DIM}# also removes idle-savers if you drop it${RESET}"
    fi
    say "  ${DIM}docs${RESET}     https://idlescreen.github.io/#studio"
    say "  ${DIM}pkgs${RESET}     ${REPO_BASE}/"
    say ""
}

main() {
    say ""
    say "${ORANGE}${BOLD}IdleScreen Studio installer${RESET}"
    say "${DIM}  installs ${STUDIO_PKGS} and ${SAVERS}${RESET}"
    say "${DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    step "[1/5]  Package manager"
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

    step "[2/5]  Pre-flight"
    preflight_packages

    step "[3/5]  IdleScreen package channel"
    write_channel

    step "[4/5]  Packages"
    install_packages

    step "[5/5]  Check"
    verify_install
}