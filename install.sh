#!/bin/sh
# IdleScreen Installer Bootstrapper
# Usage: curl -fsSL https://idlescreen.github.io/packages/install.sh | sh

set -e

# ANSI Color Tokens
ORANGE="\033[38;5;208m"
CYAN="\033[38;5;51m"
GREEN="\033[38;5;82m"
YELLOW="\033[38;5;220m"
DIM="\033[38;5;242m"
BOLD="\033[1m"
RESET="\033[0m"

echo ""
echo "${ORANGE}"
echo "  ___    _ _      ____  ___ ___  ___  ___ _  _"
echo " |_ _|__| | | ___/ ___|/ __/ _ \| _ \/ __| \| |"
echo "  | |/ _\` | |/ _ \___ \ (_|  __/|   / (__| .\` |"
echo " |___\__,_|_|_|\___|___/\___\___|_|_\\___|_|\_|"
echo "${RESET}"
echo " ${BOLD}High-Performance Ambient Screensavers for Wayland${RESET}"
echo " ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# Phase 1: Environment Audit
echo " ${CYAN}[1/4]${RESET} ${BOLD}Auditing System Environment...${RESET}"
DESKTOP="${XDG_CURRENT_DESKTOP:-Wayland Desktop}"
ARCH="$(uname -m)"
IS_DNF=0
IS_APT=0
IS_COSMIC=0

if [ -f /usr/bin/dnf ]; then
    IS_DNF=1
    echo "       ├─ Package Host:  ${GREEN}DNF (Fedora / RHEL / Rocky)${RESET}"
elif [ -f /usr/bin/apt-get ]; then
    IS_APT=1
    echo "       ├─ Package Host:  ${GREEN}APT (Debian / Ubuntu / Pop!_OS)${RESET}"
else
    echo "       └─ ${YELLOW}Unsupported package manager.${RESET}"
    exit 1
fi

case "$DESKTOP" in
    *COSMIC*|*cosmic*) IS_COSMIC=1 ;;
esac
if [ -f /usr/bin/cosmic-panel ]; then
    IS_COSMIC=1
fi

if [ "$IS_COSMIC" -eq 1 ]; then
    echo "       └─ Environment:   ${GREEN}COSMIC DE (Applet Integration Enabled)${RESET}"
else
    echo "       └─ Environment:   ${GREEN}${DESKTOP}${RESET}"
fi

echo ""
# Phase 2: Repository Integration
echo " ${CYAN}[2/4]${RESET} ${BOLD}Connecting Repository & Cryptographic Keys...${RESET}"
if [ "$IS_DNF" -eq 1 ]; then
    echo "       ├─ Fetching GPG Keyring & DNF Repository Manifest..."
    sudo curl -fsSL "https://idlescreen.github.io/packages/rpm/idlescreen.repo" -o "/etc/yum.repos.d/idlescreen.repo"
    echo "       └─ ${GREEN}Repository configured at /etc/yum.repos.d/idlescreen.repo${RESET}"
elif [ "$IS_APT" -eq 1 ]; then
    echo "       ├─ Provisioning APT keyring folder..."
    sudo mkdir -p /etc/apt/keyrings
    echo "       ├─ Fetching GPG signing key..."
    curl -fsSL "https://idlescreen.github.io/packages/idlescreen-keyring.gpg" | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
    echo "       ├─ Adding APT repository source list..."
    echo 'deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] https://idlescreen.github.io/packages/apt/ stable main' | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
    echo "       └─ Updating package index..."
    sudo apt-get update
fi

echo ""
# Phase 3: Package Installation
echo " ${CYAN}[3/4]${RESET} ${BOLD}Deploying IdleScreen Core Engine & Modules...${RESET}"
if [ "$IS_DNF" -eq 1 ]; then
    if [ "$IS_COSMIC" -eq 1 ]; then
        echo "       ├─ Executing dnf install idlescreen idle-cosmic..."
        sudo dnf install -y idlescreen idle-cosmic
    else
        echo "       ├─ Executing dnf install idlescreen..."
        sudo dnf install -y idlescreen
    fi
    echo "       └─ ${GREEN}Core engine binaries & visual modules installed.${RESET}"
elif [ "$IS_APT" -eq 1 ]; then
    if [ "$IS_COSMIC" -eq 1 ]; then
        echo "       ├─ Executing apt-get install idlescreen idle-cosmic..."
        sudo apt-get install -y idlescreen idle-cosmic
    else
        echo "       ├─ Executing apt-get install idlescreen..."
        sudo apt-get install -y idlescreen
    fi
    echo "       └─ ${GREEN}Core engine binaries & visual modules installed.${RESET}"
fi

echo ""
# Phase 4: Service Provisioning & Systemd Activation
echo " ${CYAN}[4/4]${RESET} ${BOLD}Provisioning User Configuration & Daemon Unit...${RESET}"
mkdir -p "$HOME/.config/idle" "$HOME/.config/idlescreen"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user reset-failed idle-daemon.service 2>/dev/null || true
systemctl --user enable --now idle-daemon.service 2>/dev/null || true

if systemctl --user is-active --quiet idle-daemon.service; then
    echo "       └─ Systemd Service: ${GREEN}Active & Running (idle-daemon.service)${RESET}"
else
    echo "       └─ Systemd Service: ${YELLOW}Configured (idle-daemon.service)${RESET}"
fi

echo ""
echo " ${GREEN}${BOLD}✓ Installation Complete! Welcome to IdleScreen.${RESET}"
echo " ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
if [ "$IS_COSMIC" -eq 1 ]; then
    echo " ${ORANGE}📱 COSMIC Desktop Integration:${RESET} Native Applet Enabled"
fi
echo ""
echo " ${BOLD}Quick Start Commands:${RESET}"
echo "   ${CYAN}idlescreen tui${RESET}       Launch live interactive terminal UI dashboard"
echo "   ${CYAN}idlescreen status${RESET}    Check active screensaver & daemon status"
echo "   ${CYAN}idlescreen doctor${RESET}    Run system health & Wayland diagnostic check"
echo ""
