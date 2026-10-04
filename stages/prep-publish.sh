#!/bin/bash
# pushes the release branch and opens a pull request to master, unless one is already open.
# usage: prep-publish.sh <version>
source /release-script/stages/lib.sh
use_github_token

release="$1"
repo=ogri-la/strongbox

cd /work/strongbox
git push --quiet --set-upstream origin "$release"

existing=$(gh pr list --repo "$repo" --head "$release" --base master --state open --json url --jq '.[0].url // empty')
if [ -n "$existing" ]; then
    log INFO "pull request already open, not creating another" "url=$existing"
    exit 0
fi

url=$(gh pr create --repo "$repo" --base master --head "$release" --title "$release" \
    --body-file /release-script/strongbox--pr-template.md)
log INFO "pull request opened" "url=$url"
