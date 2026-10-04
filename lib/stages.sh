# stage runner for the host-side pipelines. sourced after `lib/common.sh`.
#
# a stage is a record, given to `run_stage` as flags:
#
#   stage = { name, image, network, secrets, mounts, command }
#     image    ∈ { sb-build, sb-publish, glibc-ceiling, arch, flatpak-lint }
#     network  ∈ { none, fetch, remote }   'fetch' reads public remotes, 'remote' may write to them
#     secrets  ⊆ { github_token, aur_key } only allowed when network is 'remote'
#
# each stage is one `docker run --rm` as the host user, with a throwaway home directory,
# this repository read-only at /release-script and the release workspace at /work.

declare -A IMAGE_REFS # image name => reference given to `docker run`

# --- images

# prints a tag derived from the image's files, the shared files and the pins, so a change to any rebuilds it
image_tag() {
    local name="$1"
    local digest
    digest=$(cat "$ROOT/pins.env" "$ROOT/images/$name"/* "$ROOT/images/common"/* | sha256sum)
    printf 'strongbox-release/%s:%s' "$name" "${digest:0:12}"
}

build_image() {
    local name="$1" tag="$2"
    local args=() key
    for key in "${!PINS[@]}"; do
        args+=(--build-arg "$key=${PINS[$key]}")
    done
    log INFO "building image" "image=$tag"
    docker build --quiet "${args[@]}" --tag "$tag" --file "$ROOT/images/$name/Dockerfile" "$ROOT/images" > /dev/null \
        || die "image build failed" "image=$name"
}

# builds missing images and fills `IMAGE_REFS`
ensure_images() {
    local name tag
    for name in sb-build sb-publish; do
        tag=$(image_tag "$name")
        if ! docker image inspect "$tag" > /dev/null 2>&1; then
            build_image "$name" "$tag"
        fi
        IMAGE_REFS[$name]="$tag"
    done
    IMAGE_REFS[glibc-ceiling]="${PINS[IMAGE_GLIBC_CEILING]}"
    IMAGE_REFS[arch]="${PINS[IMAGE_ARCH]}"
    IMAGE_REFS[flatpak-lint]="${PINS[IMAGE_FLATPAK_LINT]}"
    log DEBUG "images ready" "sb-build=${IMAGE_REFS[sb-build]}" "sb-publish=${IMAGE_REFS[sb-publish]}"
}

# prints the image ID of a built image, for the build record
image_id() {
    docker image inspect --format '{{.Id}}' "${IMAGE_REFS[$1]}"
}

# --- secrets

require_secret() {
    case "$1" in
        github_token) [ -s "$GITHUB_TOKEN_FILE" ] || die "GitHub token file is missing or empty" "path=$GITHUB_TOKEN_FILE" ;;
        aur_key) [ -r "$AUR_KEY_FILE" ] || die "AUR ssh key is missing or unreadable" "path=$AUR_KEY_FILE" ;;
        *) die "unknown secret" "secret=$1" ;;
    esac
}

# --- stages

# usage: run_stage --name N --image I --network none|fetch|remote [--secret S]... [--mount SRC:DST[:ro]]...
#                  [--workdir DIR] [--stdin] -- COMMAND...
run_stage() {
    local name="" image="" network="" workdir="/work" stdin=0
    local secrets=() mounts=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --image) image="$2"; shift 2 ;;
            --network) network="$2"; shift 2 ;;
            --secret) secrets+=("$2"); shift 2 ;;
            --mount) mounts+=("$2"); shift 2 ;;
            --workdir) workdir="$2"; shift 2 ;;
            --stdin) stdin=1; shift ;;
            --) shift; break ;;
            *) die "unknown stage option" "option=$1" ;;
        esac
    done

    # validate the record before anything runs
    [ -n "$name" ] || die "stage has no name"
    [ -n "${IMAGE_REFS[$image]:-}" ] || die "stage has an unknown image" "stage=$name" "image=$image"
    case "$network" in none | fetch | remote) ;; *) die "stage has an unknown network" "stage=$name" "network=$network" ;; esac
    if [ ${#secrets[@]} -gt 0 ] && [ "$network" != remote ]; then
        die "only remote stages may hold secrets" "stage=$name" "network=$network"
    fi
    [ $# -gt 0 ] || die "stage has no command" "stage=$name"
    [ -n "${WORKSPACE:-}" ] || die "no workspace selected" "stage=$name"

    local args=(
        --rm
        --user "$(id -u):$(id -g)"
        --tmpfs /home/stage:exec,mode=1777
        --env HOME=/home/stage
        --env GIT_TERMINAL_PROMPT=0
        --env LOG_LEVEL
        --env GIT_AUTHOR_NAME --env GIT_AUTHOR_EMAIL --env GIT_COMMITTER_NAME --env GIT_COMMITTER_EMAIL
        --volume "$ROOT:/release-script:ro"
        --volume "$WORKSPACE:/work"
        --workdir "$workdir"
    )
    [ "$network" = none ] && args+=(--network none)
    [ "$stdin" = 1 ] && args+=(--interactive)

    local mount
    for mount in "${mounts[@]}"; do
        args+=(--volume "$mount")
    done

    # the token is passed by name, so its value never appears in a process list
    local secret github_token=""
    for secret in "${secrets[@]}"; do
        require_secret "$secret"
        case "$secret" in
            github_token)
                github_token=$(tr -d '\r\n' < "$GITHUB_TOKEN_FILE")
                args+=(--env GITHUB_TOKEN)
                ;;
            aur_key)
                args+=(
                    --volume "$AUR_KEY_FILE:/secrets/aur:ro"
                    --env "GIT_SSH_COMMAND=ssh -i /secrets/aur -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/release-script/known_hosts"
                )
                ;;
        esac
    done

    log INFO "stage started" "stage=$name" "image=$image" "network=$network" "secrets=${secrets[*]:-none}"
    local rc=0
    GITHUB_TOKEN="$github_token" docker run "${args[@]}" "${IMAGE_REFS[$image]}" "$@" || rc=$?
    if [ "$rc" -ne 0 ]; then
        die "stage failed" "stage=$name" "exit=$rc"
    fi
    log INFO "stage finished" "stage=$name"
}
