#!/bin/bash
# integration test: the git operations of `stages/publish.sh` against throwaway local remotes.
# covers the record and tag operations: pending to done, skipping completed work on a rerun,
# and stopping on conflicts. touches no real remote; the GitHub operations are not covered.
# usage: tests/integration-publish.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$ROOT/lib/stages.sh"

require_docker
load_pins
ensure_images

docker run --rm --user "$(id -u):$(id -g)" \
    --tmpfs /home/stage:exec,mode=1777 --env HOME=/home/stage \
    --tmpfs /work:exec,mode=1777 \
    --env GIT_TERMINAL_PROMPT=0 --env GITHUB_TOKEN=unused \
    --volume "$ROOT:/release-script:ro" \
    "${IMAGE_REFS[sb-publish]}" bash /release-script/tests/publish-git-ops.sh

log INFO "integration test passed" "test=publish"
