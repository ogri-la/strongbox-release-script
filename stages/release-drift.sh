#!/bin/bash
# compares each downstream repository with `dist/<target>` as committed at this repository's HEAD,
# which is what was last pushed to it.
# usage: release-drift.sh
source /release-script/stages/lib.sh
trust_release_script

drifted=0
for target in flathub aur; do
    expected="/work/tmp/drift/$target"
    rm -rf "$expected"
    mkdir -p "$expected"
    if ! git -C /release-script archive HEAD -- "dist/$target" 2> /dev/null | tar -x -C "$expected" --strip-components 2; then
        die "no committed baseline for this target" "target=$target" "hint=\"run ./release.sh adopt $target, review and commit dist/$target\""
    fi
    if ! python3 "$SCRIPT_DIR/lib/render.py" compare "$expected" "/work/$target"; then
        log ERROR "the downstream repository differs from what was last pushed to it" "target=$target"
        drifted=1
    fi
done
rm -rf /work/tmp/drift

[ "$drifted" = 0 ] || die "downstream repositories were edited outside this repository" \
    "hint=\"move each edit into templates/, then run ./release.sh adopt <target>, review git diff dist/<target> and commit\""
log INFO "no downstream drift"
