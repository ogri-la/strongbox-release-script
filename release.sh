#!/bin/bash
# creates a release of ogri-la/strongbox
# assumes `prep.sh` has been run and the resulting PR has been merged into `master`.
# assumes it is being run under Ubuntu 18.04 LTS
# run as a regular user.
# this script:
# * does a clean checkout of strongbox `master` branch
# * runs the `build-linux-image.sh` script and bundles the results with checksums
# * tags the current revision of `master` and pushes to remote
# * creates a release on Github with the changelog for this release and uploads release artefacts
# * updates Arch PKGBUILD and pushes to Github mirror and AUR
set -eu # everything must pass, no unbound variables
#set -x # display commands executed

export GITHUB_TOKEN=$(cat .github-token)

release="$1" # "1.2.3"

if [ ! -e parse-changelog ]; then
    wget https://github.com/taiki-e/parse-changelog/releases/download/v0.4.3/parse-changelog-x86_64-unknown-linux-gnu.tar.gz \
        --output-document parse-changelog.tar.gz
    tar xvzf parse-changelog.tar.gz
    rm parse-changelog.tar.gz
fi

(
    cd strongbox

    echo "cleaning strongbox"
    git reset --hard # revert any outstanding changes
    git clean -d --force # remove any untracked files
    rm -rf release/ # ignored .jar file may prevent directory from being deleted
    git checkout master
    git pull
    lein clean
    echo "---"

    echo "building linux release"
    ./build-linux-image.sh
    mkdir ./release/
    mv ./strongbox ./target/*-standalone.jar ./release/
    rm -rf ./target/
    (
        cd release
        sha256sum strongbox > strongbox.sha256
        sha256sum "strongbox-$release-standalone.jar" > "strongbox-$release-standalone.jar.sha256"
    )
    echo "---"

    echo "tagging release"
    git tag "$release" --force
    git push --tags
    echo "---"
    
    echo "creating Github release"
    ../gh release create "$release" \
        --title "$release" \
        --notes "$(../parse-changelog CHANGELOG.md "$release")"
    ../gh release upload "$release" release/*
    echo "---"
)

if [ ! -e strongbox-pkgbuild ]; then
    git clone ssh://git@github.com/ogri-la/strongbox-pkgbuild
fi

(
    cd strongbox-pkgbuild

    echo "cleaning strongbox-pkgbuild"
    git reset --hard # revert any outstanding changes
    git clean -d --force # remove any untracked files
    git pull
    echo "---"

    echo "updating PKGBUILD"

    # ...

    echo "---"

)


echo "done"
