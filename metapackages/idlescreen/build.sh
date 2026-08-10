#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Build idlescreen metapackage (RPM + DEB) into packages/{rpm,apt}/pool.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
META="$ROOT/metapackages/idlescreen"
# Single source of truth: DEBIAN/control Version field (must match this build).
VERSION=3.0.3
RELEASE=1
CONTROL_VER=$(awk -F': ' '/^Version:/{print $2; exit}' "$META/control")
if [ "$CONTROL_VER" != "${VERSION}-${RELEASE}" ]; then
    echo "ERROR: control Version ($CONTROL_VER) != build ${VERSION}-${RELEASE}" >&2
    exit 1
fi
SPEC_VER=$(awk '/^Version:/{print $2; exit}' "$META/idlescreen.spec")
if [ "$SPEC_VER" != "$VERSION" ]; then
    echo "ERROR: spec Version ($SPEC_VER) != build $VERSION" >&2
    exit 1
fi

echo "==> Building idlescreen ${VERSION}-${RELEASE} (noarch/all)"

# --- DEB ---
DEB_ROOT=$(mktemp -d)
trap 'rm -rf "$DEB_ROOT"' EXIT
mkdir -p "$DEB_ROOT/DEBIAN" \
    "$DEB_ROOT/usr/libexec/idlescreen"
install -m 0755 "$META/remove-product-stack.sh" \
    "$DEB_ROOT/usr/libexec/idlescreen/remove-product-stack"
install -m 0755 "$META/schedule-remove-stack.sh" \
    "$DEB_ROOT/usr/libexec/idlescreen/schedule-remove-stack"
install -m 0644 "$META/control" "$DEB_ROOT/DEBIAN/control"
# prerm runs while package files still exist (postrm is too late for our scripts).
install -m 0755 "$META/prerm" "$DEB_ROOT/DEBIAN/prerm"
# Installed-Size in KiB
SIZE=$(du -sk "$DEB_ROOT" | cut -f1)
# Rewrite control with Installed-Size if not present
if ! grep -q '^Installed-Size:' "$DEB_ROOT/DEBIAN/control"; then
    printf 'Installed-Size: %s\n' "$SIZE" >>"$DEB_ROOT/DEBIAN/control"
fi
DEB_OUT="$ROOT/apt/pool/main/idlescreen_${VERSION}-${RELEASE}_all.deb"
mkdir -p "$ROOT/apt/pool/main"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_OUT"
echo "    DEB → $DEB_OUT"

# --- RPM via podman (rpmbuild may be missing on the host) ---
RPM_OUT_DIR="$ROOT/rpm/pool"
mkdir -p "$RPM_OUT_DIR"
# Stage sources in a world-readable temp dir (Synology/SELinux mounts can
# block :ro bind-mounts from the home tree inside rootful/rootless podman).
STAGE=$(mktemp -d)
cp -a "$META/remove-product-stack.sh" "$META/schedule-remove-stack.sh" \
    "$META/idlescreen.spec" "$STAGE/"
chmod -R a+rX "$STAGE"
podman run --rm \
    --security-opt label=disable \
    -v "$STAGE:/meta:ro" \
    -v "$RPM_OUT_DIR:/out:z" \
    registry.fedoraproject.org/fedora:41 \
    bash -c "
set -euo pipefail
dnf install -y -q rpm-build
mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
cp /meta/remove-product-stack.sh /meta/schedule-remove-stack.sh /root/rpmbuild/SOURCES/
cp /meta/idlescreen.spec /root/rpmbuild/SPECS/
rpmbuild -bb /root/rpmbuild/SPECS/idlescreen.spec
cp /root/rpmbuild/RPMS/noarch/idlescreen-${VERSION}-${RELEASE}.noarch.rpm /out/
"
rm -rf "$STAGE"
echo "    RPM → $RPM_OUT_DIR/idlescreen-${VERSION}-${RELEASE}.noarch.rpm"
echo "==> Done"
