#!/bin/bash
# prepares a release of ogri-la/strongbox: a release branch with versioned files updated, and a pull request to master.
# runs on the host. every step runs in a container; nothing is pushed until the commit is reviewed and confirmed.
# usage: ./prep.sh <version> [branch]
#   branch      the branch to prepare the release from, default 'develop'
#   ASSUME_YES=1   skip the confirmation (for non-interactive runs)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$ROOT/lib/stages.sh"

release="${1:-}"
branch="${2:-develop}"
valid_version "$release" || die "usage: ./prep.sh <major.minor.patch> [branch]" "given=\"$release\""

require_docker
load_pins
load_config
ensure_images

WORKSPACE="$ROOT/work/prep-$release"
mkdir -p "$WORKSPACE"
m2_cache="${XDG_CACHE_HOME:-$HOME/.cache}/strongbox-release/m2"
mkdir -p "$m2_cache"

run_stage --name token-check --image sb-publish --network remote --secret github_token \
    -- /release-script/stages/token-check.sh ogri-la/strongbox

run_stage --name fetch --image sb-publish --network fetch \
    -- /release-script/stages/prep-fetch.sh "$branch"

kind=$(run_stage --name version-check --image sb-publish --network none \
    -- bash -c "git -C /work/strongbox tag --list | python3 /release-script/lib/release.py check-version '$release'")
log INFO "version accepted" "release=$release" "kind=$kind"

run_stage --name edit --image sb-build --network fetch --mount "$m2_cache:/home/stage/.m2" \
    -- /release-script/stages/prep-edit.sh "$release" "$kind"

run_stage --name review --image sb-publish --network none \
    -- /release-script/stages/prep-review.sh

cat >&2 << EOF

the commit above is in $WORKSPACE/strongbox, on branch '$release'.
confirming will:
  1. push branch '$release' to ogri-la/strongbox
  2. open a pull request from '$release' to 'master', unless one is already open

EOF
confirm "type '$release' to push and open the pull request:" "$release"

run_stage --name publish --image sb-publish --network remote --secret github_token \
    -- /release-script/stages/prep-publish.sh "$release"

log INFO "done" "next=\"review and merge the pull request, then run ./release.sh build $release\""
