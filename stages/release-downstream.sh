#!/bin/bash
# replaces the files in each downstream clone with the rendered files for that target, and commits locally.
# usage: release-downstream.sh <version>
source /release-script/stages/lib.sh

release="$1"

# replaces every file except .git in a clone with the files in a rendered target directory
replace_files() {
    local clone="$1" rendered="$2"
    find "$clone" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -a "$rendered/." "$clone/"
    git -C "$clone" add --all
}

git -C /work/flathub checkout --quiet -b "$release"
replace_files /work/flathub /work/dist/flathub
git -C /work/flathub commit --quiet --message "$release"

replace_files /work/aur /work/dist/aur
git -C /work/aur commit --quiet --message "release $release"

python3 "$SCRIPT_DIR/lib/render.py" compare /work/dist/flathub /work/flathub > /dev/null || die "flathub clone differs from dist/flathub"
python3 "$SCRIPT_DIR/lib/render.py" compare /work/dist/aur /work/aur > /dev/null || die "aur clone differs from dist/aur"

state flathub.commit "$(git -C /work/flathub rev-parse HEAD)"
state aur.commit "$(git -C /work/aur rev-parse HEAD)"
log INFO "downstream commits prepared"
