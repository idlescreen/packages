#!/bin/sh
# test_uninstall.sh — Comprehensive test for IdleScreen uninstall / remove function
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"

cat > "$MOCKBIN/_dispatch" <<'DISPATCH'
#!/bin/sh
cmd=$(basename "$0")
case "$cmd" in
    rpm|pacman|dpkg-query|systemctl|loginctl|pkill) exit 0 ;;
    sudo)
        # In test sandbox, sudo just runs the command directly without privilege escalation
        "$@"
        exit $?
        ;;
    *) exit 0 ;;
esac
DISPATCH
chmod +x "$MOCKBIN/_dispatch"

for c in rpm pacman dpkg dpkg-query systemctl loginctl pkill sudo; do
    ln -sfn "$MOCKBIN/_dispatch" "$MOCKBIN/$c"
done

export PATH="$MOCKBIN:$PATH"

# Source ui.sh and uninstall.sh
. "$REPO_ROOT/ui.sh"
. "$REPO_ROOT/uninstall.sh"

echo "=== Test 1: uninstall_remove_repo_dropins ==="
MOCK_SYS="$TMP/sys"
mkdir -p "$MOCK_SYS/yum.repos.d" "$MOCK_SYS/apt/sources.list.d" "$MOCK_SYS/apt/keyrings" \
         "$MOCK_SYS/pki/rpm-gpg" "$MOCK_SYS/pacman.d/idlescreen" "$MOCK_SYS/pacman.d/gnupg" "$MOCK_SYS/bin"

echo "repo" > "$MOCK_SYS/yum.repos.d/idlescreen.repo"
echo "list" > "$MOCK_SYS/apt/sources.list.d/idlescreen.list"
echo "keyring" > "$MOCK_SYS/apt/keyrings/idlescreen-keyring.gpg"
echo "rpmkey" > "$MOCK_SYS/pki/rpm-gpg/idlescreen-key.gpg"
echo "rpmkey2" > "$MOCK_SYS/pki/rpm-gpg/RPM-GPG-KEY-idlescreen"
echo "pacmandb" > "$MOCK_SYS/pacman.d/idlescreen/idlescreen.db"
echo "pacmankey" > "$MOCK_SYS/pacman.d/gnupg/idlescreen.gpg"
echo "shim" > "$MOCK_SYS/bin/omarchy-launch-screensaver"

YUM_REPOS_D="$MOCK_SYS/yum.repos.d" \
APT_SOURCES_D="$MOCK_SYS/apt/sources.list.d" \
APT_KEYRINGS_D="$MOCK_SYS/apt/keyrings" \
RPM_GPG_DIR="$MOCK_SYS/pki/rpm-gpg" \
PACMAN_XDG_D="$MOCK_SYS/pacman.d/idlescreen" \
PACMAN_KEY_D="$MOCK_SYS/pacman.d/gnupg" \
SESSION_SHIM="$MOCK_SYS/bin/omarchy-launch-screensaver" \
uninstall_remove_repo_dropins

for f in "$MOCK_SYS/yum.repos.d/idlescreen.repo" \
         "$MOCK_SYS/apt/sources.list.d/idlescreen.list" \
         "$MOCK_SYS/apt/keyrings/idlescreen-keyring.gpg" \
         "$MOCK_SYS/pki/rpm-gpg/idlescreen-key.gpg" \
         "$MOCK_SYS/pki/rpm-gpg/RPM-GPG-KEY-idlescreen" \
         "$MOCK_SYS/bin/omarchy-launch-screensaver"; do
    if [ -e "$f" ]; then
        echo "FAIL: $f was not removed!"
        exit 1
    fi
done

if [ -d "$MOCK_SYS/pacman.d/idlescreen" ] || [ -d "$MOCK_SYS/pacman.d/gnupg" ]; then
    echo "FAIL: pacman repo dirs were not removed!"
    exit 1
fi
echo "ok: uninstall_remove_repo_dropins cleared all repository trust anchors and shims"

echo "=== Test 2: uninstall_purge_user_data ==="
TEST_HOME="$TMP/userhome"
mkdir -p "$TEST_HOME/.config/idlescreen" \
         "$TEST_HOME/.config/idle" \
         "$TEST_HOME/.config/trance" \
         "$TEST_HOME/.local/share/idlescreen" \
         "$TEST_HOME/.local/state/idlescreen" \
         "$TEST_HOME/.cache/idlescreen"

echo "config" > "$TEST_HOME/.config/idlescreen/config.toml"
echo "migrated" > "$TEST_HOME/.config/idlescreen/config.yaml.migrated"
echo "idle" > "$TEST_HOME/.config/idle/config.yaml"
echo "cache" > "$TEST_HOME/.cache/idlescreen/cache.dat"

HOME="$TEST_HOME" uninstall_purge_user_data

for d in "$TEST_HOME/.config/idlescreen" \
         "$TEST_HOME/.config/idle" \
         "$TEST_HOME/.config/trance" \
         "$TEST_HOME/.local/share/idlescreen" \
         "$TEST_HOME/.local/state/idlescreen" \
         "$TEST_HOME/.cache/idlescreen"; do
    if [ -d "$d" ]; then
        echo "FAIL: User data directory $d was not purged!"
        exit 1
    fi
done
echo "ok: uninstall_purge_user_data cleared all user configuration and caches"

echo "=== Test 3: remove-product-stack.sh remove_user_data ==="
IDLESCREEN_ROOT=$(cd -- "$REPO_ROOT/../idlescreen" && pwd)
TEST_HOME2="$TMP/userhome2"
mkdir -p "$TEST_HOME2/.config/idlescreen" "$TEST_HOME2/.cache/idlescreen"
echo "toml" > "$TEST_HOME2/.config/idlescreen/config.toml"
echo "dat" > "$TEST_HOME2/.cache/idlescreen/data.bin"

# Run remove_user_data with mock home
(
    # Source only the functions from remove-product-stack.sh
    # shellcheck disable=SC1090
    sed -n '/^remove_user_data()/,/^}/p' "$IDLESCREEN_ROOT/libexec/remove-product-stack.sh" > "$TMP/rm_user_data.sh"
    . "$TMP/rm_user_data.sh"
    HOME="$TEST_HOME2" remove_user_data
)

if [ -d "$TEST_HOME2/.config/idlescreen" ] || [ -d "$TEST_HOME2/.cache/idlescreen" ]; then
    echo "FAIL: remove-product-stack.sh did not clean up $TEST_HOME2/.config/idlescreen!"
    exit 1
fi
echo "ok: remove-product-stack.sh successfully purges user configurations and caches"

echo "=== Test 4: idlescreen/rpm/postun.sh scriptlet ==="
TEST_HOME3="$TMP/userhome3"
mkdir -p "$TEST_HOME3/.config/idlescreen" "$TEST_HOME3/.cache/idlescreen"
echo "toml" > "$TEST_HOME3/.config/idlescreen/config.toml"
echo "dat" > "$TEST_HOME3/.cache/idlescreen/data.bin"

# Upgrade scenario ($1 == 1): must NOT delete user files
HOME="$TEST_HOME3" sh "$IDLESCREEN_ROOT/rpm/postun.sh" 1
if [ ! -f "$TEST_HOME3/.config/idlescreen/config.toml" ]; then
    echo "FAIL: postun.sh deleted config on upgrade (\$1 == 1)!"
    exit 1
fi
echo "ok: postun.sh preserves config on package upgrade (\$1 == 1)"

# Erase scenario ($1 == 0): MUST delete user files
HOME="$TEST_HOME3" sh "$IDLESCREEN_ROOT/rpm/postun.sh" 0
if [ -d "$TEST_HOME3/.config/idlescreen" ] || [ -d "$TEST_HOME3/.cache/idlescreen" ]; then
    echo "FAIL: postun.sh did not delete config on package erase (\$1 == 0)!"
    exit 1
fi
echo "ok: postun.sh purges config and cache on package erase (\$1 == 0)"

echo "=== ALL UNINSTALL TESTS PASSED ==="
exit 0
