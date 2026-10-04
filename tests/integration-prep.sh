#!/bin/bash
# integration test: `prep.sh` for a major release commits the versioned file updates, including the
# `SECURITY.md` rows, and refuses to push without a terminal. reads GitHub, changes nothing remote.
# needs network, docker and a valid `.github-token`.
# usage: tests/integration-prep.sh [major-version], default '8.0.0'
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/lib/stages.sh"

given="${1:-8.0.0}"
major="${given%%.*}"
previous=$((major - 1))
workspace="$ROOT/work/prep-$given"

fail() {
    die "$1" "test=prep" "release=$given"
}

require_docker
load_pins
ensure_images

remote_branch() {
    docker run --rm "${IMAGE_REFS[sb-publish]}" git ls-remote https://github.com/ogri-la/strongbox "refs/heads/$given"
}
[ -z "$(remote_branch)" ] || fail "branch already exists on GitHub; choose a version that has not been prepared"

if "$ROOT/prep.sh" "$given" < /dev/null 2> "$workspace.log"; then
    fail "prep pushed without a terminal"
fi
grep --quiet 'confirmation needs a terminal' "$workspace.log" || fail "prep did not stop at the confirmation: $(tail -3 "$workspace.log")"

security="$workspace/strongbox/SECURITY.md"
grep --quiet --fixed-strings "| $major.x.x   | :heavy_check_mark: |" "$security" || fail "SECURITY.md has no supported row for the new major version"
grep --quiet --fixed-strings "| $previous.x.x   | :heavy_minus_sign: |" "$security" || fail "SECURITY.md did not demote the previous major version"
[ "$(grep --count ':heavy_check_mark:' "$security")" = 1 ] || fail "SECURITY.md supports more than one major version"
grep --quiet --fixed-strings "defproject ogri-la/strongbox \"$given\"" "$workspace/strongbox/project.clj" || fail "project.clj does not declare the release"
grep --quiet "^## \[$given\] - \|^## $given - " "$workspace/strongbox/CHANGELOG.md" || fail "CHANGELOG.md has no section for the release"

[ -z "$(remote_branch)" ] || fail "branch was pushed to GitHub"

rm -rf "$workspace" "$workspace.log"
log INFO "integration test passed" "test=prep" "release=$given"
