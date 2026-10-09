#!/usr/bin/env bash
# sync_installer_checksums.sh — synchronize and verify installer module checksums
# across packages/install.sh and idlescreen.github.io/install.sh.
#
# Usage:
#   scripts/sync_installer_checksums.sh          # update checksums in-place
#   scripts/sync_installer_checksums.sh --check  # verify checksums without modifying
#
# SPDX-License-Identifier: Apache-2.0

set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
export REPO_ROOT

python3 - "$@" <<'PYEOF'
import hashlib
import os
import re
import sys

check_only = "--check" in sys.argv

repo_root = os.environ.get("REPO_ROOT")
if not repo_root:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

modules = [
    "ui.sh",
    "detect.sh",
    "repo.sh",
    "install_core.sh",
    "install_audit.sh",
    "post_install.sh",
    "uninstall.sh",
]

# 1. Compute current sha256 for each module in packages
module_hashes = {}
for mod in modules:
    path = os.path.join(repo_root, mod)
    if not os.path.exists(path):
        print(f"ERROR: Module file missing: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "rb") as f:
        module_hashes[mod] = hashlib.sha256(f.read()).hexdigest()

# 2. Check / update packages/install.sh
install_sh_path = os.path.join(repo_root, "install.sh")
if not os.path.exists(install_sh_path):
    print(f"ERROR: install.sh missing at {install_sh_path}", file=sys.stderr)
    sys.exit(1)

with open(install_sh_path, "r", encoding="utf-8") as f:
    install_sh_content = f.read()

mismatches = []
for mod, h in module_hashes.items():
    # Look for: "mod") _expected_hash="<hex>"
    pattern = rf'"{re.escape(mod)}"\)\s+_expected_hash="([a-f0-9]*)"'
    match = re.search(pattern, install_sh_content)
    if not match:
        mismatches.append(f"packages/install.sh: missing hash entry for module '{mod}'")
    elif match.group(1) != h:
        mismatches.append(
            f"packages/install.sh: hash mismatch for '{mod}' (in file: {match.group(1)}, actual: {h})"
        )

# Also check pinned hashes in --verify block if present
for mod, h in module_hashes.items():
    verify_pattern = rf'"{re.escape(mod)}"\)\s+_expected="([a-f0-9]*)"'
    match = re.search(verify_pattern, install_sh_content)
    if match and match.group(1) != h:
        mismatches.append(
            f"packages/install.sh (--verify): hash mismatch for '{mod}' (in file: {match.group(1)}, actual: {h})"
        )

# 3. Check / update idlescreen.github.io/install.sh if available
gh_io_dir = os.environ.get("IDLESCREEN_GITHUB_IO_DIR")
if not gh_io_dir:
    candidate = os.path.join(repo_root, "..", "idlescreen.github.io")
    if os.path.exists(candidate):
        gh_io_dir = os.path.abspath(candidate)

gh_io_install_sh = os.path.join(gh_io_dir, "install.sh") if gh_io_dir else None

if check_only:
    # Compute current packages/install.sh hash for checking gh_io
    with open(install_sh_path, "rb") as f:
        pkg_install_hash = hashlib.sha256(f.read()).hexdigest()

    if gh_io_install_sh and os.path.exists(gh_io_install_sh):
        with open(gh_io_install_sh, "r", encoding="utf-8") as f:
            gh_io_content = f.read()
        gh_io_match = re.search(
            r'EXPECTED_INSTALLER_HASH="(?:\$\{IDLESCREEN_INSTALLER_HASH:-)?([a-f0-9]*)\}?"',
            gh_io_content,
        )
        if not gh_io_match:
            mismatches.append(f"{gh_io_install_sh}: missing EXPECTED_INSTALLER_HASH entry")
        elif gh_io_match.group(1) != pkg_install_hash:
            mismatches.append(
                f"{gh_io_install_sh}: EXPECTED_INSTALLER_HASH mismatch "
                f"(forwarder has: {gh_io_match.group(1)}, packages/install.sh actual: {pkg_install_hash})"
            )

    if mismatches:
        print("FAIL: Checksum synchronization check failed:", file=sys.stderr)
        for m in mismatches:
            print(f"  - {m}", file=sys.stderr)
        print("\nRun 'scripts/sync_installer_checksums.sh' to synchronize.", file=sys.stderr)
        sys.exit(1)
    else:
        print("ok: all installer checksums are synchronized.")
        for mod, h in module_hashes.items():
            print(f"  {mod}: {h}")
        if gh_io_install_sh and os.path.exists(gh_io_install_sh):
            print(f"  idlescreen.github.io/install.sh forwarder -> packages/install.sh ({pkg_install_hash})")
        sys.exit(0)

# UPDATE MODE:
updated_install_sh = install_sh_content
for mod, h in module_hashes.items():
    # Update bootstrap case block
    pattern = rf'("{re.escape(mod)}"\)\s+_expected_hash=)"[a-f0-9]*"'
    updated_install_sh = re.sub(pattern, rf'\1"{h}"', updated_install_sh)
    # Update --verify case block if present
    verify_pattern = rf'("{re.escape(mod)}"\)\s+_expected=)"[a-f0-9]*"'
    updated_install_sh = re.sub(verify_pattern, rf'\1"{h}"', updated_install_sh)

if updated_install_sh != install_sh_content:
    with open(install_sh_path, "w", encoding="utf-8") as f:
        f.write(updated_install_sh)
    print(f"Updated module hashes in {install_sh_path}")
else:
    print(f"Module hashes in {install_sh_path} already current.")

# Recompute packages/install.sh hash after writing
with open(install_sh_path, "rb") as f:
    new_pkg_install_hash = hashlib.sha256(f.read()).hexdigest()
print(f"packages/install.sh SHA-256: {new_pkg_install_hash}")

# Update idlescreen.github.io/install.sh if available
if gh_io_install_sh and os.path.exists(gh_io_install_sh):
    with open(gh_io_install_sh, "r", encoding="utf-8") as f:
        gh_io_content = f.read()

    new_gh_io_content = re.sub(
        r'EXPECTED_INSTALLER_HASH=(?:"[a-f0-9]*"|"\$\{IDLESCREEN_INSTALLER_HASH:-[a-f0-9]*\}")',
        f'EXPECTED_INSTALLER_HASH="${{IDLESCREEN_INSTALLER_HASH:-{new_pkg_install_hash}}}"',
        gh_io_content,
    )
    if new_gh_io_content != gh_io_content:
        with open(gh_io_install_sh, "w", encoding="utf-8") as f:
            f.write(new_gh_io_content)
        print(f"Updated EXPECTED_INSTALLER_HASH in {gh_io_install_sh}")
    else:
        print(f"EXPECTED_INSTALLER_HASH in {gh_io_install_sh} already current.")

print("Checksum synchronization complete.")
PYEOF
