#!/bin/bash
# fails when any image or download is not pinned: images must be referenced by digest,
# checksums must be sha256, and Dockerfiles may only build `FROM` a pinned image argument.
# usage: ./check-pins.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

load_pins
failed=0
fail() {
    log ERROR "$@"
    failed=1
}

for key in "${!PINS[@]}"; do
    value="${PINS[$key]}"
    case "$key" in
        IMAGE_*) [[ "$value" =~ ^[a-z0-9./_-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] || fail "image is not pinned by digest" "pin=$key" "value=$value" ;;
        *_SHA256) [[ "$value" =~ ^[0-9a-f]{64}$ ]] || fail "checksum is not a sha256" "pin=$key" "value=$value" ;;
    esac
done

# every Dockerfile this repository owns. `work/` and the ignored clones hold other projects' files.
shopt -s nullglob
dockerfiles=("$ROOT"/Dockerfile* "$ROOT"/images/*/Dockerfile*)
scripts=("$ROOT"/*.sh "$ROOT"/lib/*.sh "$ROOT"/stages/*.sh "$ROOT"/tests/*.sh)
shopt -u nullglob

for dockerfile in "${dockerfiles[@]}"; do
    while read -r from; do
        image="${from#FROM }"
        if [[ "$image" =~ ^\$\{(IMAGE_[A-Z0-9_]+)\}$ ]]; then
            [ -n "${PINS[${BASH_REMATCH[1]}]:-}" ] || fail "Dockerfile uses an image argument missing from pins.env" "file=$dockerfile" "arg=${BASH_REMATCH[1]}"
        elif [[ ! "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
            fail "Dockerfile builds from an unpinned image" "file=$dockerfile" "image=$image"
        fi
    done < <(grep -E '^FROM ' "$dockerfile")
done

# a literal image reference after `docker run` or `docker pull` must carry a digest
while IFS=: read -r file line text; do
    if [[ ! "$text" =~ @sha256: ]]; then
        fail "script runs an unpinned image" "file=$file" "line=$line"
    fi
done < <(grep -n -E 'docker (run|pull)[^#]* [a-z0-9./_-]+:[A-Za-z0-9._-]+( |$)' "${scripts[@]}" || true)

[ "$failed" = 0 ] || exit 1
log INFO "all inputs are pinned" "pins=${#PINS[@]}" "dockerfiles=${#dockerfiles[@]}" "scripts=${#scripts[@]}"
