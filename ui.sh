# Terminal style and Open the story
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
