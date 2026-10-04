#!/bin/bash
# runs inside the publish image, called by `tests/integration-publish.sh`.
# builds a workspace at /work whose remotes are local bare repositories, then runs `publish.sh` against it.
set -euo pipefail

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org

release=9.9.9
publish=/release-script/stages/publish.sh

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# a bare remote with one commit on master, and a workspace clone of it
remote_and_clone() {
    local name="$1"
    git init --quiet --bare --initial-branch master "/work/remotes/$name.git"
    git clone --quiet "/work/remotes/$name.git" "/tmp/seed-$name" 2> /dev/null
    git -C "/tmp/seed-$name" commit --quiet --allow-empty --message "upstream"
    git -C "/tmp/seed-$name" push --quiet origin HEAD:master
    git clone --quiet "/work/remotes/$name.git" "/work/$name"
}

remote_ref() {
    git --git-dir "/work/remotes/$1.git" rev-parse --verify --quiet "$2" || true
}

# given: strongbox at its release commit, and a stand-in for this repository with a rendered, uncommitted dist/
for name in strongbox release-script flathub aur; do
    remote_and_clone "$name"
done
mkdir -p /work/release-script/dist/aur
echo "pkgver=$release" > /work/release-script/dist/aur/PKGBUILD
commit=$(git -C /work/strongbox rev-parse HEAD)
cat > /work/build.json << EOF
{"sources": {"strongbox": "$commit"},
 "derived": {"flathub": "$commit", "aur": "$commit"},
 "artefacts": {}}
EOF

export BUILD_RECORD=/work/build.json
export RELEASE_SCRIPT_REPO=/work/release-script
export RELEASE_SCRIPT_REMOTE=/work/remotes/release-script.git

# pending operations are published, the release record first
"$publish" apply "$release" record tag
recorded=$(git -C /work/release-script rev-parse "refs/tags/$release^{commit}")
[ "$(remote_ref release-script "refs/tags/$release")" = "$recorded" ] || fail "this repository's tag was not pushed"
[ "$(remote_ref release-script master)" = "$recorded" ] || fail "this repository's branch was not pushed"
[ "$(git -C /work/release-script log -1 --format=%s "$recorded")" = "release $release" ] || fail "release commit has the wrong message"
git -C /work/release-script show "$recorded:dist/aur/PKGBUILD" | grep --quiet "pkgver=$release" || fail "release commit lacks dist/"
[ "$(remote_ref strongbox "refs/tags/$release")" = "$commit" ] || fail "strongbox tag was not pushed"

# a rerun skips completed operations and makes no second commit
actual=$("$publish" apply "$release" record tag 2>&1)
[ "$(grep -c 'already done, skipping' <<< "$actual")" = 2 ] || fail "rerun did not skip both operations: $actual"
[ "$(git -C /work/release-script rev-parse HEAD)" = "$recorded" ] || fail "rerun made another commit"

# a rerun after a failed push reuses the local release commit
git --git-dir /work/remotes/release-script.git tag --delete "$release" > /dev/null
"$publish" apply "$release" record
[ "$(git -C /work/release-script rev-parse HEAD)" = "$recorded" ] || fail "retry made another commit"
[ "$(remote_ref release-script "refs/tags/$release")" = "$recorded" ] || fail "retry did not push the tag"

# a release tag on another commit is a conflict, and nothing is pushed
git -C /work/strongbox commit --quiet --allow-empty --message "after the release"
git -C /work/strongbox push --quiet --force origin "HEAD:refs/tags/$release"
moved=$(remote_ref strongbox "refs/tags/$release")
if "$publish" apply "$release" tag 2> /tmp/conflict.log; then
    fail "a tag on another commit was not treated as a conflict"
fi
grep --quiet 'conflicts with the build' /tmp/conflict.log || fail "tag conflict was not reported: $(cat /tmp/conflict.log)"
[ "$(remote_ref strongbox "refs/tags/$release")" = "$moved" ] || fail "a conflicting operation changed the remote"

# this repository's tag elsewhere is a conflict
git -C /work/release-script tag --delete "$release" > /dev/null
if "$publish" apply "$release" record 2> /tmp/conflict.log; then
    fail "a release tag without a matching local commit was not treated as a conflict"
fi
grep --quiet 'conflicts with the build' /tmp/conflict.log || fail "record conflict was not reported: $(cat /tmp/conflict.log)"

echo "publish git operations: all checks passed" >&2
