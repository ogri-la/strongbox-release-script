#!/bin/bash
# renders release files into /work/dist.
#   phase 1, before the build: files needing no checksums, such as the desktop files
#   phase 2, after the checksums: everything, with the artefacts' and phase 1's checksums
# usage: release-render.sh <version> <1|2>
source /release-script/stages/lib.sh

release="$1"
phase="$2"
render=(python3 "$SCRIPT_DIR/lib/render.py")

mkdir -p /work/tmp
case "$phase" in
    1)
        "${render[@]}" context "$release" "$(cat /work/state/strongbox.commit)" /work/strongbox/CHANGELOG.md parse-changelog /work/tmp/context.json
        ;;
    2)
        "${render[@]}" add-checksums /work/dist/context.json /work/release "$release" /work/tmp/context.json
        ;;
    *) die "unknown phase" "phase=$phase" ;;
esac
rm -rf /work/dist
"${render[@]}" render "$SCRIPT_DIR" /work "$phase" /work/tmp/context.json /work/dist
log INFO "rendered" "phase=$phase" "files=$(find /work/dist -type f | wc -l)"
