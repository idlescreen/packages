#!/bin/sh
# IdleScreen Rust Installer Bootstrapper
# Usage: curl -fsSL https://idlescreen.github.io/packages/install.sh | sh

set -e

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo " 🌌 Downloading IdleScreen Rust Installer..."
curl -fsSL "https://idlescreen.github.io/packages/bin/install" -o "$TMP_DIR/idlescreen-installer"
chmod +x "$TMP_DIR/idlescreen-installer"

# Launch native Rust installer binary attached to terminal TTY
exec "$TMP_DIR/idlescreen-installer" "$@" < /dev/tty
