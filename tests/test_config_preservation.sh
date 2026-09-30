#!/bin/sh
# Verify that post_install.sh preserves existing user and system configuration.
set -eu

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"

cat > "$MOCKBIN/_dispatch" <<'DISPATCH'
#!/bin/sh
exit 0
DISPATCH
chmod +x "$MOCKBIN/_dispatch"
for cmd in busctl systemctl idle-daemon; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$cmd"
done

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.config/idlescreen"
echo "custom_setting: preserved_idlescreen" > "$HOME_DIR/.config/idlescreen/config.yaml"

# Source ui functions required by post_install.sh
# shellcheck disable=SC1091
. "$REPO_ROOT/ui.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/post_install.sh"

# Run awaken_daemon with HOME pointed at our test home
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR" awaken_daemon >/dev/null 2>&1 || true

# Assert ~/.config/idlescreen/config.yaml still contains custom_setting
content=$(cat "$HOME_DIR/.config/idlescreen/config.yaml")
if [ "$content" != "custom_setting: preserved_idlescreen" ]; then
    echo "FAIL: ~/.config/idlescreen/config.yaml was overwritten! content=$content"
    exit 1
fi

# Assert ~/.config/idle/config.yaml was synced from idlescreen without clobbering
idle_content=$(cat "$HOME_DIR/.config/idle/config.yaml")
if [ "$idle_content" != "custom_setting: preserved_idlescreen" ]; then
    echo "FAIL: ~/.config/idle/config.yaml was not preserved from idlescreen! content=$idle_content"
    exit 1
fi

# Modify idle config, run awaken_daemon again, ensure neither is clobbered
echo "user_custom_edit: 123" > "$HOME_DIR/.config/idle/config.yaml"
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR" awaken_daemon >/dev/null 2>&1 || true

idle_content2=$(cat "$HOME_DIR/.config/idle/config.yaml")
if [ "$idle_content2" != "user_custom_edit: 123" ]; then
    echo "FAIL: ~/.config/idle/config.yaml was clobbered on second run!"
    exit 1
fi

# Fresh user home with only ~/.config/idle/config.yaml
HOME_DIR2="$TMP/home2"
mkdir -p "$HOME_DIR2/.config/idle"
echo "custom_setting: preserved_idle" > "$HOME_DIR2/.config/idle/config.yaml"

output_log="$TMP/awaken.log"
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR2" awaken_daemon >"$output_log" 2>&1 || true

content2=$(cat "$HOME_DIR2/.config/idle/config.yaml")
if [ "$content2" != "custom_setting: preserved_idle" ]; then
    echo "FAIL: ~/.config/idle/config.yaml was overwritten! content=$content2"
    exit 1
fi
synced_idlescreen=$(cat "$HOME_DIR2/.config/idlescreen/config.yaml")
if [ "$synced_idlescreen" != "custom_setting: preserved_idle" ]; then
    echo "FAIL: ~/.config/idlescreen/config.yaml was not synced from idle! content=$synced_idlescreen"
    exit 1
fi

if ! grep -q "Preserving existing configuration" "$output_log"; then
    echo "FAIL: awaken_daemon did not emit preservation notice!"
    exit 1
fi

# Fresh home seeded from system config if present
if [ -f "/etc/xdg/idlescreen/config.yaml" ] || [ -f "/etc/idlescreen/config.yaml" ]; then
    HOME_DIR3="$TMP/home3"
    mkdir -p "$HOME_DIR3"
    output_log3="$TMP/awaken3.log"
    PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR3" awaken_daemon >"$output_log3" 2>&1 || true
    if [ ! -f "$HOME_DIR3/.config/idlescreen/config.yaml" ] && [ ! -f "$HOME_DIR3/.config/idle/config.yaml" ]; then
        echo "FAIL: system config was not seeded into empty user home!"
        exit 1
    fi
    if ! grep -q "Preserving existing configuration" "$output_log3"; then
        echo "FAIL: awaken_daemon did not emit preservation notice for system config!"
        exit 1
    fi
fi

echo "all config preservation checks passed"
