#!/bin/bash
# checks strongbox master is the release: its declared version, its changelog and the release tag.
# usage: release-check-source.sh <version>
source /release-script/stages/lib.sh

release="$1"
commit=$(cat /work/state/strongbox.commit)
remote_tag=$(cat /work/state/strongbox.remote-tag)

cd /work/strongbox
declared=$(sed -n -E 's/^\(defproject ogri-la\/strongbox "([^"]+)".*/\1/p' project.clj)
[ "$declared" = "$release" ] \
    || die "master's project.clj does not declare this release; has the prep pull request been merged?" "declared=$declared" "release=$release"

parse-changelog CHANGELOG.md "$release" > /dev/null \
    || die "CHANGELOG.md has no section for this release" "release=$release"

if [ -n "$remote_tag" ] && [ "$remote_tag" != "$commit" ]; then
    die "the release tag already exists on another commit" "tag=$release" "tag_commit=$remote_tag" "master=$commit"
fi
log INFO "source matches the release" "release=$release" "commit=$commit" "tag=${remote_tag:-absent}"
