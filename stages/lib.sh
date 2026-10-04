# helpers for stage scripts, which run inside the release images. sourced, not executed.
# the workspace is mounted at /work and this repository, read-only, at /release-script.

set -euo pipefail

SCRIPT_DIR=/release-script
RELEASE_PY="$SCRIPT_DIR/lib/release.py"

declare -A LOG_LEVELS=([DEBUG]=10 [INFO]=20 [WARN]=30 [ERROR]=40)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

log() {
    local level="$1" msg="$2"
    shift 2
    if [ "${LOG_LEVELS[$level]}" -lt "${LOG_LEVELS[$LOG_LEVEL]:-20}" ]; then
        return 0
    fi
    local line pair
    printf -v line 'level=%s msg="%s"' "$level" "$msg"
    for pair in "$@"; do
        line+=" $pair"
    done
    printf '%s\n' "$line" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

# records one fact about the build in /work/state, for the build record
state() {
    mkdir -p /work/state
    printf '%s\n' "$2" > "/work/state/$1"
}

# clones `url` into /work/`dir` over https, replacing anything already there.
# `pushurl`, when given, is where pushes go; fetching never needs a credential.
fresh_clone() {
    local url="$1" dir="$2" branch="${3:-}" pushurl="${4:-}"
    rm -rf "/work/$dir"
    local args=(--quiet)
    [ -n "$branch" ] && args+=(--branch "$branch")
    git clone "${args[@]}" "$url" "/work/$dir"
    if [ -n "$pushurl" ]; then
        git -C "/work/$dir" config remote.origin.pushurl "$pushurl"
    fi
    log INFO "cloned" "repo=$dir" "commit=$(git -C "/work/$dir" rev-parse HEAD)"
}

# lets git authenticate to github.com with `GITHUB_TOKEN`, through gh. only remote stages have the token.
use_github_token() {
    [ -n "${GITHUB_TOKEN:-}" ] || die "this stage needs GITHUB_TOKEN but was not given it"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="credential.https://github.com.helper"
    export GIT_CONFIG_VALUE_0='!gh auth git-credential'
}

# git refuses to read a repository owned by another user unless trusted; stages run as the owner,
# but the mount point differs from the path the repository was created at.
trust_release_script() {
    git config --global --add safe.directory /release-script
}
