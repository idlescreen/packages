#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Build idlescreen-studio metapackage (RPM + DEB) into packages/{rpm,apt}/pool.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
META="$ROOT/metapackages/idlescreen-studio"
VERSION=1.0.0
RELEASE=1

echo "==> Building idlescreen-studio ${VERSION}-${RELEASE} (noarch/all)"

DEB_ROOT=$(mktemp -d)
trap 'rm -rf "$DEB_ROOT"' EXIT
mkdir -p "$DEB_ROOT/DEBIAN" \
    "$DEB_ROOT/usr/libexec/idlescreen-studio"
install -m 0755 "$META/remove-studio-stack.sh" \
    "$DEB_ROOT/usr/libexec/idlescreen-studio/remove-studio-stack"
install -m 0755 "$META/schedule-remove-studio-stack.sh" \
    "$DEB_ROOT/usr/libexec/idlescreen-studio/schedule-remove-studio-stack"
install -m 0644 "$META/control" "$DEB_ROOT/DEBIAN/control"
install -m 0755 "$META/prerm" "$DEB_ROOT/DEBIAN/prerm"
SIZE=$(du -sk "$DEB_ROOT" | cut -f1)
if ! grep -q '^Installed-Size:' "$DEB_ROOT/DEBIAN/control"; then
    printf 'Installed-Size: %s\n' "$SIZE" >>"$DEB_ROOT/DEBIAN/control"
fi
DEB_OUT="$ROOT/apt/pool/main/idlescreen-studio_${VERSION}-${RELEASE}_all.deb"
mkdir -p "$ROOT/apt/pool/main"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_OUT"
echo "    DEB → $DEB_OUT"

RPM_OUT_DIR="$ROOT/rpm/pool"
mkdir -p "$RPM_OUT_DIR"
STAGE=$(mktemp -d)
cp -a "$META/remove-studio-stack.sh" "$META/schedule-remove-studio-stack.sh" \
    "$META/idlescreen-studio.spec" "$STAGE/"
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
cp /meta/remove-studio-stack.sh /meta/schedule-remove-studio-stack.sh /root/rpmbuild/SOURCES/
cp /meta/idlescreen-studio.spec /root/rpmbuild/SPECS/
rpmbuild -bb /root/rpmbuild/SPECS/idlescreen-studio.spec
cp /root/rpmbuild/RPMS/noarch/idlescreen-studio-${VERSION}-${RELEASE}.noarch.rpm /out/
"
rm -rf "$STAGE"
echo "    RPM → $RPM_OUT_DIR/idlescreen-studio-${VERSION}-${RELEASE}.noarch.rpm"
echo "==> Done"
