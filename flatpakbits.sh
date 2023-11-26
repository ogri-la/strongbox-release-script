#!/bin/bash
# updates the `strongbox-flatpak` repo, runs `makepkg` within a container.
# called after releasing Strongbox on Github.

set -eux

test -f parse-changelog
test -d strongbox
locate --regex 'xmllint$'
locate --regex 'jq$'
locate --regex 'python3$'

release="$1" # "1.2.3"

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
python3 generate-metainfo.py | xmllint --format - > strongbox-flatpak/metainfo.xml

# update the checksums of the flathub description
python3 generate-flathub.py "$release" > strongbox-flatpak/la.ogri.strongbox.yml

# build the flatpak
(
    cd strongbox-flatpak
    #./build-flatpak.sh

    git add metainfo.xml la.ogri.strongbox.yml
    git ci -am "metainfo.xml, la.ogri.strongbox.yml, updated"
    git push
    git tag "$release"
    git push --tags
)

# open a PR on Flathub
if [ -d la.ogri.strongbox ]; then
    (
        cd la.ogri.strongbox
        git reset --hard
        git checkout master
        git pull
    )
else
    git clone ssh://git@github.com/flathub/la.ogri.strongbox
fi

(
    cd la.ogri.strongbox
    #git checkout -b "$release"
    cp ../strongbox-flatpak/la.ogri.strongbox.yml .
    #git ci -am "$release"
    #git push --set-upstream origin "$release"
    #../gh pr create \
    #    --base "master" \
    #    --head "$release" \
    #    --title "$release"
)

