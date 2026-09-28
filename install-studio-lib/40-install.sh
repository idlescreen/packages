#!/bin/sh
# install-studio helper: install the package set.
#
# Two attempts: ALL_PKGS (studio + savers) first, fall back to
# STUDIO_PKGS only. The fallback keeps the install useful even
# when idle-savers isn't yet published for a new architecture.

install_packages() {
    say "  ${DIM}installing:${RESET} ${BOLD}${STUDIO_PKGS}${RESET}"
    say "  ${DIM}plugins:${RESET}   ${SAVERS}"
        # SC2086: the split is the point. This is a POSIX `sh` script,
        # so there are no arrays; ALL_PKGS / STUDIO_PKGS are
        # space-separated package lists that the package manager must
        # receive as separate arguments. Quoting them would install one
        # package literally named "idle-studio render".
    if [ "$PKG" = "dnf" ]; then
        # shellcheck disable=SC2086
        if ! sudo dnf install --refresh --setopt=idlescreen.metadata_expire=0 $ALL_PKGS; then
            # shellcheck disable=SC2086
            if ! sudo dnf install --refresh --setopt=idlescreen.metadata_expire=0 $STUDIO_PKGS; then
                err "dnf could not install: ${STUDIO_PKGS}"
                say "  ${DIM}If checksum errors: sudo dnf clean all --repo=idlescreen${RESET}"
                exit 1
            fi
            warn "idle-savers not installed this run — effect names need plugins on disk"
        fi
    else
        # shellcheck disable=SC2086
        if ! sudo apt-get install -y $ALL_PKGS; then
            # shellcheck disable=SC2086
            if ! sudo apt-get install -y $STUDIO_PKGS; then
                err "apt-get could not install: ${STUDIO_PKGS}"
                exit 1
            fi
            warn "idle-savers not installed this run — effect names need plugins on disk"
        fi
    fi
    ensure_ffmpeg || true
}