#!/bin/bash
# fresh clones of strongbox and the downstream repositories, the remote state of the release tag,
# and this repository's commit.
# usage: release-fetch.sh <version>
source /release-script/stages/lib.sh

release="$1"

fresh_clone https://github.com/ogri-la/strongbox strongbox master
fresh_clone https://github.com/flathub/la.ogri.strongbox flathub master
fresh_clone https://aur.archlinux.org/strongbox.git aur master ssh://aur@aur.archlinux.org/strongbox.git

state strongbox.commit "$(git -C /work/strongbox rev-parse HEAD)"

# the peeled commit of the tag, or nothing when the tag does not exist yet
remote_tag=$(git -C /work/strongbox ls-remote origin "refs/tags/$release" "refs/tags/$release^{}" | sort -k2 | tail -1 | cut -f1)
state strongbox.remote-tag "$remote_tag"

# the scripts and templates rendering this release. untracked files are ignored; a new template is only
# used once `templates/plan.json`, which is tracked, refers to it.
trust_release_script
state release-script.commit "$(git -C /release-script rev-parse HEAD)"
if [ -n "$(git -C /release-script status --porcelain --untracked-files=no -- . ':(exclude)dist')" ]; then
    log WARN "this repository has uncommitted changes outside dist/; publish will refuse this build"
    state release-script.dirty true
else
    state release-script.dirty false
fi
