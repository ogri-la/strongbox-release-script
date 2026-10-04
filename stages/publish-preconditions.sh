#!/bin/bash
# checks, before any remote contact, that this repository can record the release and that the build still holds:
# on the default branch, no changes outside dist/, and the build record matching the workspace and dist/.
# usage: publish-preconditions.sh <version>
source /release-script/stages/lib.sh
trust_release_script

release="$1"
repo=/release-script

branch=$(git -C "$repo" symbolic-ref --short HEAD 2> /dev/null || echo "(detached)")
[ "$branch" = master ] || die "publish runs on this repository's default branch" "branch=$branch" "expected=master"

changed=$(git -C "$repo" status --porcelain --untracked-files=no -- . ':(exclude)dist')
[ -z "$changed" ] || die "this repository has uncommitted changes outside dist/" "files=\"$(tr '\n' ' ' <<< "$changed")\""

python3 "$RELEASE_PY" verify-record "$repo" /work "$release"
