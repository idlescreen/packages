#!/bin/sh
# install-studio helper: colour variables + the say/ok/warn/err/step
# print helpers used by every other sibling.
#
# Colours are guarded by a TTY check + NO_COLOR / TERM=dumb so the
# installer stays quiet in CI logs and `curl | sh` invocations
# from a redirecting shell. The fallback is empty strings — the
# print helpers still format correctly.

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    ORANGE="\033[38;5;208m"
    CYAN="\033[38;5;51m"
    GREEN="\033[38;5;82m"
    YELLOW="\033[38;5;220m"
    DIM="\033[38;5;242m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    ORANGE="" CYAN="" GREEN="" YELLOW="" DIM="" BOLD="" RESET=""
fi

say()  { printf '%b\n' "$*"; }
ok()   { say " ${GREEN}✔${RESET} $*"; }
warn() { say " ${YELLOW}!${RESET} $*"; }
err()  { say " ${YELLOW}ERROR:${RESET} $*"; }
step() { say ""; say " ${CYAN}${BOLD}$*${RESET}"; }

# Shared constants used by every sibling. Kept here because the
# colour-setup page is the natural single-source for the
# installer-wide variables — anything that needs the repo URL or
# the pinned signing-key fingerprint already pulls the colours.
REPO_BASE="${IDLESCREEN_REPO_BASE:-https://idlescreen.github.io/packages}"
STUDIO_PKGS="idle-studio render"
SAVERS="idle-savers"
ALL_PKGS="$STUDIO_PKGS $SAVERS"
# Pinned signing-key fingerprints — the package-channel trust
# anchors are verified out-of-band so a compromised Pages origin
# cannot swap them.
RPM_KEY_FPR="3D2D670DBD9BD94D7B2D23D356ED99E8C0243160"
APT_KEY_FPR="549E73C9BC9229C786E538E2FBD8FC52C7817DD2"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "need command: $1"
        exit 1
    }
}

is_dnf() { command -v dnf >/dev/null 2>&1 || [ -x /usr/bin/dnf ]; }
is_apt() { command -v apt-get >/dev/null 2>&1 || [ -x /usr/bin/apt-get ]; }