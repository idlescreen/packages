#!/bin/sh
# Verify that post_install.sh preserves existing user and system configuration.
set -eu

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"

cat > "$MOCKBIN/_dispatch" <<'DISPATCH'
#!/bin/sh
exit 0
DISPATCH
chmod +x "$MOCKBIN/_dispatch"
for cmd in busctl systemctl idle-daemon sudo pkexec; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$cmd"
done

# 1. Existing ~/.config/idlescreen/config.yaml is preserved without clobbering or creating a duplicate config.toml
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.config/idlescreen"
echo "custom_setting: preserved_idlescreen" > "$HOME_DIR/.config/idlescreen/config.yaml"

# Source ui functions required by post_install.sh
# shellcheck disable=SC1091
. "$REPO_ROOT/ui.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/post_install.sh"

output_log1="$TMP/awaken1.log"
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR" awaken_daemon >"$output_log1" 2>&1 || true

content=$(cat "$HOME_DIR/.config/idlescreen/config.yaml")
if ! grep -q "custom_setting: preserved_idlescreen" "$HOME_DIR/.config/idlescreen/config.yaml"; then
    echo "FAIL: ~/.config/idlescreen/config.yaml lost custom_setting! content=$content"
    exit 1
fi
if [ -f "$HOME_DIR/.config/idlescreen/config.toml" ]; then
    echo "FAIL: ~/.config/idlescreen/config.toml should not be created when config.yaml exists for daemon migration!"
    exit 1
fi
if ! grep -q "Preserving existing configuration" "$output_log1"; then
    echo "FAIL: awaken_daemon did not emit preservation notice for config.yaml!"
    exit 1
fi

# 2. Existing ~/.config/idlescreen/config.toml is preserved across runs
HOME_DIR2="$TMP/home2"
mkdir -p "$HOME_DIR2/.config/idlescreen"
printf '[general]\nidle_timeout_secs = 180\n\n[saver]\nactive = "cosmos"\n' > "$HOME_DIR2/.config/idlescreen/config.toml"

output_log2="$TMP/awaken2.log"
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR2" awaken_daemon >"$output_log2" 2>&1 || true

content2=$(cat "$HOME_DIR2/.config/idlescreen/config.toml")
if ! grep -q "idle_timeout_secs = 180" "$HOME_DIR2/.config/idlescreen/config.toml"; then
    echo "FAIL: ~/.config/idlescreen/config.toml was overwritten! content=$content2"
    exit 1
fi
if ! grep -q 'active = "cosmos"' "$HOME_DIR2/.config/idlescreen/config.toml"; then
    echo "FAIL: user active = 'cosmos' was overridden on second run! content=$content2"
    exit 1
fi
if ! grep -q "Preserving existing configuration" "$output_log2"; then
    echo "FAIL: awaken_daemon did not emit preservation notice for config.toml!"
    exit 1
fi

# 3. Fresh user home with no prior config gets default config.toml with active = "ascii"
HOME_DIR_EMPTY="$TMP/home_empty"
mkdir -p "$HOME_DIR_EMPTY"
PATH="$MOCKBIN:/usr/bin:/bin" HOME="$HOME_DIR_EMPTY" awaken_daemon >/dev/null 2>&1 || true
if [ ! -f "$HOME_DIR_EMPTY/.config/idlescreen/config.toml" ]; then
    echo "FAIL: empty home did not get ~/.config/idlescreen/config.toml!"
    exit 1
fi
if ! grep -q 'active = "ascii"' "$HOME_DIR_EMPTY/.config/idlescreen/config.toml"; then
    echo "FAIL: empty home did not get active = \"ascii\" in idlescreen config.toml!"
    exit 1
fi

echo "all config preservation checks passed"
