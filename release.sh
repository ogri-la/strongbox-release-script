#!/bin/bash
# releases ogri-la/strongbox, run on the host. every step runs in a container.
#
#   ./release.sh build <version>     builds, checks and renders everything locally into dist/. needs no
#                                    credentials and changes nothing remote. replaces dist/ only on success.
#   ./release.sh publish <version>   commits dist/, tags this repository <version>, then publishes exactly what
#                                    `build` recorded, after showing the plan and asking for the version to be
#                                    typed. safe to rerun after a failure.
#   ./release.sh adopt <target>      copies a downstream repository's files ('flathub' or 'aur') into
#                                    dist/<target>, after an edit there has been moved into templates/.
#
# assumes `prep.sh` has been run and its pull request merged into master.
#   ASSUME_YES=1   skip the confirmation (for non-interactive runs)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$ROOT/lib/stages.sh"

# downstream repositories, by target name in dist/
declare -A DOWNSTREAM=(
    [flathub]=https://github.com/flathub/la.ogri.strongbox
    [aur]=https://aur.archlinux.org/strongbox.git
)

build() {
    local release="$1"
    local m2_cache="${XDG_CACHE_HOME:-$HOME/.cache}/strongbox-release/m2"
    mkdir -p "$WORKSPACE" "$m2_cache"
    rm -rf "$WORKSPACE/state" "$WORKSPACE/dist"

    run_stage --name fetch --image sb-publish --network fetch \
        -- /release-script/stages/release-fetch.sh "$release"
    run_stage --name drift --image sb-publish --network none \
        -- /release-script/stages/release-drift.sh
    run_stage --name check-source --image sb-publish --network none \
        -- /release-script/stages/release-check-source.sh "$release"
    run_stage --name render-metadata --image sb-publish --network none \
        -- /release-script/stages/release-render.sh "$release" 1
    run_stage --name build --image sb-build --network fetch --mount "$m2_cache:/home/stage/.m2" \
        -- /release-script/stages/release-build.sh "$release"
    run_stage --name glibc-floor --image sb-build --network none \
        -- /release-script/stages/release-glibc.sh "$release" "${PINS[GLIBC_CEILING]}"
    run_stage --name jre-start --image glibc-ceiling --network none --mount "$WORKSPACE/tmp/appimage/usr:/jre:ro" \
        -- sh -c "/jre/bin/java -version 2>&1 | tee /dev/stderr | grep -q '${PINS[TEMURIN_VERSION]}'"
    run_stage --name checksums --image sb-build --network none \
        -- /release-script/stages/release-checksums.sh
    run_stage --name render-packages --image sb-publish --network none \
        -- /release-script/stages/release-render.sh "$release" 2
    run_stage --name flathub-lint-manifest --image flatpak-lint --network fetch --workdir /work/dist \
        -- --exceptions manifest flathub/la.ogri.strongbox.yml
    # needs network: it checks that every URL in the metainfo resolves, and fails on warnings as Flathub's buildbot does
    run_stage --name flathub-lint-metainfo --image flatpak-lint --network fetch --workdir /work/dist \
        -- appstream flatpak/metainfo.xml
    run_stage --name metainfo-validate --image sb-publish --network none \
        -- /release-script/stages/release-lint.sh
    run_stage --name aur-package --image arch --network none \
        -- /release-script/stages/release-aur.sh "$release"
    run_stage --name downstream --image sb-publish --network none \
        -- /release-script/stages/release-downstream.sh "$release"

    # facts only the host knows
    printf '%s\n' "${PINS[IMAGE_TEMURIN]}" > "$WORKSPACE/state/image.temurin"
    printf '%s\n' "${PINS[IMAGE_UBUNTU]}" > "$WORKSPACE/state/image.ubuntu"
    printf '%s\n' "${PINS[IMAGE_GLIBC_CEILING]}" > "$WORKSPACE/state/image.glibc-ceiling"
    printf '%s\n' "${PINS[IMAGE_ARCH]}" > "$WORKSPACE/state/image.arch"
    printf '%s\n' "${PINS[IMAGE_FLATPAK_LINT]}" > "$WORKSPACE/state/image.flatpak-lint"
    image_id sb-build > "$WORKSPACE/state/image.sb-build"
    image_id sb-publish > "$WORKSPACE/state/image.sb-publish"

    run_stage --name record --image sb-publish --network none \
        -- python3 /release-script/lib/release.py write-record /release-script /work "$release"

    # every step succeeded, so the rendered files replace dist/
    rm -rf "$ROOT/dist"
    cp -a "$WORKSPACE/dist" "$ROOT/dist"

    log INFO "build complete, nothing remote was changed" "workspace=$WORKSPACE" \
        "next=\"inspect work/$release/release and 'git diff dist/', then ./release.sh publish $release\""
}

publish() {
    local release="$1"
    [ -d "$WORKSPACE" ] || die "no workspace for this release" "hint=\"run ./release.sh build $release first\""

    run_stage --name preconditions --image sb-publish --network none \
        -- /release-script/stages/publish-preconditions.sh "$release"
    run_stage --name token-check --image sb-publish --network remote --secret github_token \
        -- /release-script/stages/token-check.sh \
        ogri-la/strongbox ogri-la/strongbox-release-script flathub/la.ogri.strongbox
    require_secret aur_key
    run_stage --name plan --image sb-publish --network remote --secret github_token \
        -- /release-script/stages/publish.sh plan "$release"

    confirm "type '$release' to publish the operations above, in order:" "$release"

    run_stage --name publish-record --image sb-publish --network remote --secret github_token --mount "$ROOT:/repo" \
        -- /release-script/stages/publish.sh apply "$release" record
    run_stage --name publish-github --image sb-publish --network remote --secret github_token \
        -- /release-script/stages/publish.sh apply "$release" tag release assets flathub
    run_stage --name publish-aur --image sb-publish --network remote --secret aur_key \
        -- /release-script/stages/publish.sh apply "$release" aur

    log INFO "published" "next=\"review and merge the Flathub pull request, then follow the post-release steps in release.md\""
}

adopt() {
    local target="$1"
    [ -n "${DOWNSTREAM[$target]:-}" ] || die "unknown target" "target=$target" "targets=\"${!DOWNSTREAM[*]}\""
    mkdir -p "$WORKSPACE"
    run_stage --name fetch --image sb-publish --network fetch \
        -- bash -c "source /release-script/stages/lib.sh && fresh_clone '${DOWNSTREAM[$target]}' '$target' master"
    rm -rf "$ROOT/dist/$target"
    mkdir -p "$ROOT/dist/$target"
    cp -a "$WORKSPACE/$target/." "$ROOT/dist/$target/"
    rm -rf "$ROOT/dist/$target/.git"
    log INFO "adopted" "target=$target" "next=\"review 'git diff dist/$target' and commit it\""
}

command="${1:-}"
argument="${2:-}"
usage="usage: ./release.sh {build|publish} <major.minor.patch> | ./release.sh adopt {${!DOWNSTREAM[*]}}"
case "$command" in
    build | publish)
        valid_version "$argument" || die "$usage" "given=\"$argument\""
        WORKSPACE="$ROOT/work/$argument"
        ;;
    adopt)
        [ -n "$argument" ] || die "$usage"
        WORKSPACE="$ROOT/work/adopt"
        ;;
    *) die "$usage" ;;
esac

require_docker
load_pins
load_config
ensure_images

"$command" "$argument"
