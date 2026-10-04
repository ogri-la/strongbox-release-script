#!/bin/bash
# publishes a verified build. each operation has a `check`, which reads remote state and prints
# 'done', 'pending' or 'conflict', and an `apply`, which performs it.
#
# usage: publish.sh plan <version>
#        publish.sh apply <version> <operation>...
#
# operations, in the order they must run:
#   record    commit dist/ to this repository's default branch, tag it, push both
#   tag       push the release tag at the built strongbox commit
#   release   create the GitHub release with the rendered notes
#   assets    upload the artefacts to the GitHub release
#   flathub   push the Flathub branch and open a pull request
#   aur       push the AUR commit to the AUR
#
# environment, overridden by the integration test:
#   BUILD_RECORD              the build record, default: dist/build.json in this repository
#   RELEASE_SCRIPT_REPO       this repository, writable for the `record` operation (default /repo, else /release-script)
#   RELEASE_SCRIPT_REMOTE     where `record` pushes, default this repository on GitHub
source /release-script/stages/lib.sh
# the AUR stage holds only the AUR key; every other stage holds the token
if [ -n "${GITHUB_TOKEN:-}" ]; then
    use_github_token
fi

OPERATIONS=(record tag release assets flathub aur)

mode="$1"
release="$2"
shift 2

BUILD_RECORD="${BUILD_RECORD:-/release-script/dist/build.json}"
RELEASE_SCRIPT_REMOTE="${RELEASE_SCRIPT_REMOTE:-https://github.com/ogri-la/strongbox-release-script}"
if [ -z "${RELEASE_SCRIPT_REPO:-}" ]; then
    if [ -d /repo/.git ]; then RELEASE_SCRIPT_REPO=/repo; else RELEASE_SCRIPT_REPO=/release-script; fi
fi
git config --global --add safe.directory "$RELEASE_SCRIPT_REPO"

record() {
    python3 "$RELEASE_PY" record-get "$BUILD_RECORD" "$@"
}

commit=$(record sources strongbox)
flathub_commit=$(record derived flathub)
aur_commit=$(record derived aur)

# prints the commit a remote ref points at, peeled for tags, or nothing
remote_ref() {
    local repo="$1" ref="$2"
    git -C "/work/$repo" ls-remote origin "$ref" "$ref^{}" | sort -k2 | tail -1 | cut -f1
}

# 'done' when the remote branch is at `target`, 'pending' when it is at `target`'s parent, else 'conflict'
branch_status() {
    local actual="$1" target="$2" repo="$3"
    if [ "$actual" = "$target" ]; then
        echo done
    elif [ "$actual" = "$(git -C "/work/$repo" rev-parse "$target^")" ]; then
        echo pending
    else
        echo conflict
    fi
}

# --- record

# the commit the local release tag points at, or nothing
local_release_commit() {
    git -C "$RELEASE_SCRIPT_REPO" rev-parse --verify --quiet "refs/tags/$release^{commit}" || true
}

check_record() {
    local remote local_commit
    remote=$(git -C "$RELEASE_SCRIPT_REPO" ls-remote "$RELEASE_SCRIPT_REMOTE" "refs/tags/$release" "refs/tags/$release^{}" | sort -k2 | tail -1 | cut -f1)
    local_commit=$(local_release_commit)
    if [ -z "$remote" ]; then
        echo pending
    elif [ "$remote" = "$local_commit" ]; then
        echo done
    else
        log WARN "this repository's release tag exists elsewhere" "tag=$release" "remote=$remote" "local=${local_commit:-absent}"
        echo conflict
    fi
}

# commits dist/ and tags it, once. a rerun reuses the tag when its dist/ matches the working tree.
apply_record() {
    local repo="$RELEASE_SCRIPT_REPO" branch
    branch=$(git -C "$repo" symbolic-ref --short HEAD)
    if [ -z "$(local_release_commit)" ]; then
        git -C "$repo" add --all -- dist
        git -C "$repo" commit --quiet --allow-empty --message "release $release" -- dist
        git -C "$repo" tag "$release"
    elif ! git -C "$repo" diff --quiet "refs/tags/$release" -- dist; then
        die "the local release tag's dist/ differs from the working tree" "tag=$release"
    fi
    git -C "$repo" push --quiet "$RELEASE_SCRIPT_REMOTE" "$branch" "refs/tags/$release"
}

# --- tag

check_tag() {
    local actual
    actual=$(remote_ref strongbox "refs/tags/$release")
    if [ -z "$actual" ]; then
        echo pending
    elif [ "$actual" = "$commit" ]; then
        echo done
    else
        log WARN "release tag points elsewhere" "tag_commit=$actual" "built=$commit"
        echo conflict
    fi
}

apply_tag() {
    git -C /work/strongbox push --quiet origin "$commit:refs/tags/$release"
}

# --- release

check_release() {
    if gh release view "$release" --repo ogri-la/strongbox --json tagName > /dev/null 2>&1; then
        echo done
    else
        echo pending
    fi
}

apply_release() {
    gh release create "$release" --repo ogri-la/strongbox --verify-tag \
        --title "$release" --notes-file /work/dist/release-notes.md > /dev/null
}

# --- assets

# prints 'name<TAB>sha256' for each asset already uploaded, using GitHub's digest or downloading the asset
remote_assets() {
    local name digest
    gh api "repos/ogri-la/strongbox/releases/tags/$release" --jq '.assets[] | [.name, (.digest // "")] | @tsv' 2>/dev/null \
        | while IFS=$'\t' read -r name digest; do
            if [ -z "$digest" ]; then
                digest="sha256:$(gh release download "$release" --repo ogri-la/strongbox --pattern "$name" --output - | sha256sum | cut -d' ' -f1)"
            fi
            printf '%s\t%s\n' "$name" "${digest#sha256:}"
        done
}

check_assets() {
    local remote name expected actual missing=0
    remote=$(remote_assets)
    for name in $(record artefacts | jq -r 'keys[]'); do
        expected=$(record artefacts "$name")
        actual=$(awk -F'\t' -v n="$name" '$1 == n {print $2}' <<< "$remote")
        if [ -z "$actual" ]; then
            missing=1
        elif [ "$actual" != "$expected" ]; then
            log WARN "uploaded asset differs from the build" "asset=$name" "uploaded=$actual" "built=$expected"
            echo conflict
            return
        fi
    done
    [ "$missing" = 1 ] && echo pending || echo done
}

apply_assets() {
    local remote name files=()
    remote=$(remote_assets)
    for name in $(ls /work/release); do
        awk -F'\t' -v n="$name" '$1 == n {found=1} END {exit !found}' <<< "$remote" || files+=("/work/release/$name")
    done
    gh release upload "$release" --repo ogri-la/strongbox "${files[@]}"
}

# --- flathub

# prints the url of the pull request from the release branch, or nothing. `state` is 'open' or 'merged'.
flathub_pr() {
    gh pr list --repo flathub/la.ogri.strongbox --head "$release" --state "$1" --json url --jq '.[0].url // empty'
}

# a merged pull request is done even when Flathub has since deleted its branch
check_flathub() {
    local branch
    if [ -n "$(flathub_pr merged)" ]; then
        echo done
        return
    fi
    branch=$(remote_ref flathub "refs/heads/$release")
    if [ -n "$branch" ] && [ "$branch" != "$flathub_commit" ]; then
        log WARN "the Flathub branch exists on another commit" "branch=$release" "remote=$branch" "built=$flathub_commit"
        echo conflict
    elif [ -n "$branch" ] && [ -n "$(flathub_pr open)" ]; then
        echo done
    else
        echo pending
    fi
}

apply_flathub() {
    local base url
    git -C /work/flathub push --quiet origin "$flathub_commit:refs/heads/$release"
    url=$(flathub_pr open)
    if [ -z "$url" ]; then
        base=$(gh api repos/flathub/la.ogri.strongbox --jq .default_branch)
        url=$(gh pr create --repo flathub/la.ogri.strongbox --base "$base" --head "$release" --title "$release" --body "")
    fi
    log INFO "Flathub pull request" "url=$url"
}

# --- aur

check_aur() {
    local aur
    aur=$(branch_status "$(remote_ref aur refs/heads/master)" "$aur_commit" aur)
    if [ "$aur" = conflict ]; then
        log WARN "the AUR has moved since the build"
    fi
    echo "$aur"
}

apply_aur() {
    [ -r /secrets/aur ] || die "the AUR operation needs the AUR key, run it in a stage given 'aur_key'"
    git -C /work/aur push --quiet origin "$aur_commit:refs/heads/master"
}

# ---

plan() {
    local operation status conflicts=0
    printf '\n%-9s %s\n' operation status >&2
    for operation in "${OPERATIONS[@]}"; do
        status=$("check_$operation")
        printf '%-9s %s\n' "$operation" "$status" >&2
        [ "$status" = conflict ] && conflicts=1
    done
    printf '\n' >&2
    [ "$conflicts" = 0 ] || die "remote state conflicts with the build; resolve it before publishing"
}

apply() {
    local operation status
    for operation in "$@"; do
        status=$("check_$operation")
        case "$status" in
            done) log INFO "already done, skipping" "operation=$operation" ;;
            conflict) die "remote state conflicts with the build" "operation=$operation" ;;
            pending)
                log INFO "publishing" "operation=$operation"
                "apply_$operation"
                status=$("check_$operation")
                [ "$status" = done ] || die "operation did not take effect" "operation=$operation" "status=$status"
                log INFO "published" "operation=$operation"
                ;;
        esac
    done
}

case "$mode" in
    plan) plan ;;
    apply) apply "$@" ;;
    *) die "unknown mode" "mode=$mode" ;;
esac
