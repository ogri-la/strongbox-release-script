#!/bin/bash
# generates .SRCINFO for the rendered PKGBUILD and builds the AUR package offline from the local AppImage.
# runs in the Arch image.
# usage: release-aur.sh <version>
set -euo pipefail

release="$1"
# the rendered package, so `.SRCINFO` is written into dist/ beside the PKGBUILD it describes
cd /work/dist/aur
makepkg --printsrcinfo > .SRCINFO

rm -rf /work/tmp/aur
mkdir -p /work/tmp/aur/src /work/tmp/aur/build /work/tmp/aur/pkg
# the file name `source=()` gives the AppImage, so makepkg finds it and verifies it instead of downloading
cp "/work/release/strongbox-$release-x86_64.AppImage" "/work/tmp/aur/src/strongbox-$release"
SRCDEST=/work/tmp/aur/src BUILDDIR=/work/tmp/aur/build PKGDEST=/work/tmp/aur/pkg makepkg --nodeps --noconfirm
test -f "/work/tmp/aur/pkg/strongbox-$release-1-x86_64.pkg.tar.zst"
