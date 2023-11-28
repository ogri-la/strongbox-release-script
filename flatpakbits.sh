#!/bin/bash
# updates the `strongbox-flatpak` repo, runs `makepkg` within a container.
# called after releasing Strongbox on Github.

set -eux

release="$1" # "1.2.3"

export GIT_PAGER=cat
GITHUB_TOKEN=$(cat .github-token)
export GITHUB_TOKEN

test -f parse-changelog
test -f gh
test -d strongbox
locate --regex 'xmllint$'
locate --regex 'jq$'
locate --regex 'python3$'

if [ -d strongbox-flatpak ]; then
    (
        cd strongbox-flatpak
        git reset --hard
        git checkout master
        git pull
    )
else
    git clone ssh://git@github.com/ogri-la/strongbox-flatpak
fi

# update the list of releases in the metainfo.xml
python3 generate-metainfo.py "$release" | xmllint --format - > strongbox-flatpak/metainfo.xml

# update the checksums of the flathub description
python3 generate-flathub.py "$release" > strongbox-flatpak/la.ogri.strongbox.yml

# build the flatpak
(
    cd strongbox-flatpak
    git update-index -q --refresh # even touching a tracked file report it as changed unless index is updated
    if git diff-index --quiet HEAD; then
        echo "no changes to commit"
    else
        #./build-flatpak.sh
        git add metainfo.xml la.ogri.strongbox.yml
        git commit -am "metainfo.xml, la.ogri.strongbox.yml, updated"
        git push
        git tag "$release"
        git push --tags
    fi
)

# open a PR on Flathub
rm -rf la.ogri.strongbox
git clone ssh://git@github.com/flathub/la.ogri.strongbox
(
    cd la.ogri.strongbox
    git checkout -b "$release"
    cp ../strongbox-flatpak/la.ogri.strongbox.yml .
    git commit -am "$release"
    git push --set-upstream origin "$release"
    ../gh pr create \
        --base "master" \
        --head "$release" \
        --body "" \
        --title "$release"
)

