#!/bin/bash
# finds the highest glibc version any shared object in the AppImage requires, including those inside its jar,
# and fails above the ceiling. leaves the extracted AppImage in /work/tmp/appimage for the JRE start check.
# usage: release-glibc.sh <version> <ceiling>
source /release-script/stages/lib.sh

release="$1"
ceiling="$2"

rm -rf /work/tmp
mkdir -p /work/tmp/jar-natives
cd /work/tmp
"/work/release/strongbox-$release-x86_64.AppImage" --appimage-extract > /dev/null
mv squashfs-root appimage
unzip -q -o appimage/usr/app.jar '*.so' -d jar-natives

objects=$(find appimage jar-natives -type f -name '*.so*' -exec sh -c 'file -b "$1" | grep -q "^ELF" && echo "$1"' _ {} \;)
[ -n "$objects" ] || die "no shared objects found in the AppImage"

result=$(
    for object in $objects; do
        echo "== $object"
        objdump -T "$object"
    done | python3 "$RELEASE_PY" glibc-floor "$ceiling"
)
floor="${result%% *}"
worst="${result#* }"
state glibc.floor "$floor"
state glibc.worst "$worst"
state glibc.ceiling "$ceiling"
log INFO "glibc floor within ceiling" "floor=$floor" "worst=$worst" "ceiling=$ceiling" "objects=$(wc -w <<< "$objects")"
