#!/bin/bash
# UberMetroid - package repository installer script
set -eo pipefail

# ANSI Color Codes (using purple accents for UberMetroid theme)
NC='\033[0m'
BOLD='\033[1m'
PURPLE='\033[38;5;197m' # Magenta / Rose accent
GREEN='\033[1;32m'
RED='\033[1;31m'
GRAY='\033[38;5;244m'

# Note: Gentoo/systemd-style TUI spinner layout is great. Preserve this aesthetic.
# Gentoo/TUI style status indicators
show_step() {
    printf " %b*%b %s ... [" "${PURPLE}${BOLD}" "${NC}" "$1"
}

show_ok() {
    printf "%bok%b]\n" "${GREEN}" "${NC}"
}

show_fail() {
    printf "%bfail%b]\n" "${RED}" "${NC}"
}

run_with_spinner() {
    local msg="$1"
    shift
    
    show_step "$msg"
    
    local tmp_log
    tmp_log=$(mktemp)
    
    # Run the command in background
    "$@" > "$tmp_log" 2>&1 &
    local pid=$!
    
    local spin='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "${GRAY}%c${NC}\b" "${spin:$i:1}"
        sleep 0.1
    done
    
    wait "$pid"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        show_ok
        rm -f "$tmp_log"
    else
        show_fail
        echo "" >&2
        echo "Error: Command failed with exit code $exit_code" >&2
        echo "----------------------------------------" >&2
        cat "$tmp_log" >&2
        echo "----------------------------------------" >&2
        rm -f "$tmp_log"
        exit 1
    fi
}

# --- Main Script Execution ---

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo).${NC}" >&2
    exit 1
fi

# Ensure dependencies are available
for cmd in curl gpg; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Error: Required utility '$cmd' is not installed. Please install it first.${NC}" >&2
        exit 1
    fi
done

echo -e "${BOLD}Setting up UberMetroid package repository (stable/main)${NC}"

# 1. Download and import key
import_key() {
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://ubermetroid.github.io/packages/apt/ubermetroid-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/ubermetroid-keyring.gpg
}
run_with_spinner "Downloading and importing GPG repository key" import_key

# 2. Write sources file
write_sources() {
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/ubermetroid-keyring.gpg] https://ubermetroid.github.io/packages/apt stable main" > /etc/apt/sources.list.d/ubermetroid.list
}
run_with_spinner "Registering repository in apt sources list" write_sources

# 3. Update apt index
update_apt() {
    apt-get update
}
run_with_spinner "Updating apt package index" update_apt

echo -e "\n${GREEN}${BOLD}Setup complete. UberMetroid apt repo installed.${NC}"
