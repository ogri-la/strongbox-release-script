#!/bin/bash
# builds the uberjar and AppImage with `appimage/build-appimage.sh`, then names them for the release.
# usage: release-build.sh <version>
source /release-script/stages/lib.sh

release="$1"

rm -rf /work/release /work/tmp/appimage-build
mkdir -p /work/release /work/tmp/appimage-build
(
    cd /work/tmp/appimage-build
    "$SCRIPT_DIR/appimage/build-appimage.sh" /work/strongbox /work/dist/appimage/strongbox.desktop \
        "/work/release/strongbox-$release-x86_64.AppImage"
)
rm -rf /work/tmp/appimage-build
mv "/work/strongbox/target/strongbox-$release-standalone.jar" /work/release/ \
    || die "the uberjar is not named for this release" "expected=strongbox-$release-standalone.jar"

state catalogue.sha256 "$(sha256sum /work/strongbox/resources/full-catalogue.json | cut -d' ' -f1)"
state jdk.version "$(sed -n -E 's/^JAVA_RUNTIME_VERSION="(.+)"$/\1/p' "$JAVA_HOME/release")"
log INFO "artefacts built" "dir=/work/release"
