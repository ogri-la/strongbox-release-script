#!/bin/bash
# builds an AppImage of strongbox with a custom JRE, in the current directory.
# from ogri-la/strongbox-appimage at 5119f26. Copyright © Torkus 2023 - present, AGPL-3.0.
# usage: build-appimage.sh <path-to-strongbox> <desktop-file> <output>
#   desktop-file   the rendered `dist/appimage/strongbox.desktop`
#   expects `appimagetool` on PATH, with its runtime pinned (see `images/sb-build/appimagetool`)
set -eu

path_to_strongbox="$1"
desktop_file="$2"
output="$3"
test -d "$path_to_strongbox"
test -f "$desktop_file"
script_dir="$(dirname "$(realpath "$0")")"

custom_jre_dir="$(realpath custom-jre)"
rm -rf "$custom_jre_dir"

echo "--- building custom JRE ---"

# compress=1 'constant string sharing' compresses better with AppImage than compress=2 'zip', 52MB -> 45MB
# - https://docs.oracle.com/en/java/javase/19/docs/specs/man/jlink.html#plugin-compress
jlink \
    --add-modules "java.sql,java.naming,java.desktop,jdk.unsupported,jdk.crypto.ec" \
    --output "$custom_jre_dir" \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=1

# needed when built using Ubuntu as libjvm.so is *huge*
# doesn't seem to hurt to strip the other .so files.
find "$custom_jre_dir" -name "*.so" -print0 | xargs -0 strip --preserve-dates --strip-unneeded

du -sh "$custom_jre_dir"

echo
echo "--- building app ---"
(
    cd "$path_to_strongbox"
    lein clean
    rm -f resources/full-catalogue.json
    wget https://raw.githubusercontent.com/ogri-la/strongbox-catalogue/master/full-catalogue.json \
        --quiet \
        --directory-prefix resources
    lein uberjar
    cp ./target/*-standalone.jar "$custom_jre_dir/app.jar"
)

echo
echo "--- building AppImage ---"
rm -rf ./AppDir
mkdir AppDir
mv "$custom_jre_dir" AppDir/usr
cp "$desktop_file" AppDir/strongbox.desktop
cp "$script_dir/AppRun" AppDir/
cp "$path_to_strongbox/resources/strongbox.svg" "$path_to_strongbox/resources/strongbox.png" AppDir/
du -sh AppDir/
rm -f "$output"
ARCH=x86_64 appimagetool AppDir/ "$output"
du -sh "$output"

echo
echo "--- cleaning up ---"
rm -rf AppDir

echo
echo "done."
