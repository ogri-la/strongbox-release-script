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
    git reset --hard
    git checkout master
    git pull
else
    git clone ssh://git@github.com/ogri-la/strongbox-flatpak
fi

if [ -d la.ogri.strongbox ]; then
    git reset --hard
    git checkout master
    git pull
else
    git clone ssh://git@github.com/flathub/la.ogri.strongbox
fi

# update the list of releases in the metainfo.xml
python3 generate-metainfo.py | xmllint --format - > strongbox-flatpak/metainfo.xml

# update the checksums of the flathub description
python3 generate-flathub.py strongbox-flatpak/la.ogri.strongbox.yml.template > strongbox-flatpak/la.ogri.strongbox.yml.template

