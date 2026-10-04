#!/bin/bash
# integration test: `release.sh build` succeeds with no credentials, passes the drift check against the committed
# baseline, renders dist/, writes a valid record whose checksums agree with the files, and leaves every remote it
# reads unchanged. a build that fails leaves dist/ as it was.
# dist/ is restored afterwards, so the test leaves the working tree as it found it.
# slow: clones, compiles strongbox and builds an AppImage. needs network and docker.
# usage: tests/integration-build.sh [version], default is the last released version
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/lib/stages.sh"

given="${1:-7.7.0}"

require_docker
load_pins
ensure_images

saved=$(mktemp -d)
cp -a "$ROOT/dist" "$saved/dist"
restore() {
    rm -rf "$ROOT/dist"
    cp -a "$saved/dist" "$ROOT/dist"
    rm -rf "$saved"
}
trap restore EXIT

fail() {
    die "$1" "test=build" "release=$given"
}

# runs a command in the publish image with this repository and the release's workspace mounted
in_publish_image() {
    docker run --rm --user "$(id -u):$(id -g)" --tmpfs /home/stage:exec,mode=1777 --env HOME=/home/stage \
        --volume "$ROOT:/release-script:ro" --volume "$ROOT/work/$given:/work" --workdir /work \
        "${IMAGE_REFS[sb-publish]}" "$@"
}

# every ref of every remote the release touches, sorted
remote_state() {
    docker run --rm "${IMAGE_REFS[sb-publish]}" sh -c '
        for url in https://github.com/ogri-la/strongbox https://github.com/ogri-la/strongbox-release-script \
            https://github.com/flathub/la.ogri.strongbox https://aur.archlinux.org/strongbox.git; do
            git ls-remote "$url" | sed "s|^|$url |"
        done' | sort
}

dist_state() {
    find "$ROOT/dist" -type f -print0 | sort -z | xargs -0 sha256sum
}

expected=$(remote_state)

# a build that fails leaves dist/ unchanged: master does not declare 0.0.1, so check-source fails
before=$(dist_state)
if GITHUB_TOKEN_FILE=/nonexistent AUR_KEY_FILE=/nonexistent "$ROOT/release.sh" build 0.0.1 2> /dev/null; then
    fail "a build of a version master does not declare succeeded"
fi
[ "$before" = "$(dist_state)" ] || fail "a failed build changed dist/"
rm -rf "$ROOT/work/0.0.1"

GITHUB_TOKEN_FILE=/nonexistent AUR_KEY_FILE=/nonexistent "$ROOT/release.sh" build "$given"

for path in context.json build.json release-notes.md aur/PKGBUILD aur/.SRCINFO aur/changelog aur/strongbox.desktop \
    aur/.gitignore flathub/la.ogri.strongbox.yml flatpak/metainfo.xml flatpak/strongbox.desktop flatpak/strongbox.svg \
    appimage/strongbox.desktop; do
    [ -f "$ROOT/dist/$path" ] || fail "dist/$path was not rendered"
done
if grep -rq '{{' "$ROOT/dist"; then
    fail "a rendered file still holds a placeholder"
fi
in_publish_image python3 /release-script/lib/release.py verify-record /release-script /work "$given"
in_publish_image sh -c 'cd release && sha256sum --check --quiet *.sha256'

actual=$(remote_state)
[ "$expected" = "$actual" ] || fail "remote state changed during a build"

log INFO "integration test passed" "test=build" "release=$given"
