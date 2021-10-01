#!/bin/bash
# creates a release of ogri-la/strongbox
# assumes `prep.sh` has been run and the resulting PR has been merged into `master`.
# - script does not *depend* on prep.sh script however.
# run as a regular user in Ubuntu 18.04 LTS
# this script:
# * does a clean checkout of strongbox `master` branch
# * runs the `build-linux-image.sh` script and bundles the results with checksums
# * tags the current revision of `master` and pushes to remote
# * creates a release on Github with the changelog for this release and uploads release artefacts
# * updates Arch PKGBUILD and pushes to Github mirror and AUR
set -eu # everything must pass, no unbound variables
#set -x # display commands executed

GITHUB_TOKEN=$(cat ~/.github-token)
export GITHUB_TOKEN

release="$1" # "1.2.3"

if [ ! -e parse-changelog ]; then
    echo "--- downloading 'parse-changelog' ---"
    wget https://github.com/taiki-e/parse-changelog/releases/download/v0.4.3/parse-changelog-x86_64-unknown-linux-gnu.tar.gz \
        --output-document parse-changelog.tar.gz
    tar xvzf parse-changelog.tar.gz
    rm parse-changelog.tar.gz
    echo
fi

if [ ! -e "gh" ]; then
    echo "--- downloading Github's 'gh' tool ---"
    rm -rf gh_1.14.0_linux_amd64/ gh_1.14.0_linux_amd64.tar.gz gh.tar.gz
    wget https://github.com/cli/cli/releases/download/v1.14.0/gh_1.14.0_linux_amd64.tar.gz --output-document gh.tar.gz
    tar xvzf gh.tar.gz
    mv gh_1.14.0_linux_amd64/bin/gh ./gh
    rm -rf gh_1.14.0_linux_amd64
    echo
fi

if [ ! -e "strongbox" ]; then
    echo "--- cloning strongbox ---"
    git clone ssh://git@github.com/ogri-la/strongbox strongbox
    echo
fi

(
    cd strongbox

    echo "--- cleaning strongbox ---"
    git reset --hard # revert any outstanding changes
    git clean -d --force # remove any untracked files
    rm -rf release/ # ignored .jar file may prevent directory from being deleted
    git checkout master
    git pull
    lein clean
    echo

    echo "--- tagging release ---"
    git tag "$release" --force
    git push --tags
    echo

    echo "--- creating Github release ---"
    ../gh release create "$release" \
        --title "$release" \
        --notes "$(../parse-changelog CHANGELOG.md "$release")"
    echo

    echo "--- building linux release ---"
    ./build-linux-image.sh
    mkdir ./release/
    mv ./strongbox ./target/*-standalone.jar ./release/
    rm -rf ./target/
    (
        cd release
        sha256sum strongbox > strongbox.sha256
        sha256sum "strongbox-$release-standalone.jar" > "strongbox-$release-standalone.jar.sha256"
    )
    echo
    
    echo "--- uploading release ---"
    ../gh release upload "$release" release/*
    echo
)

. archbits.sh "$release"

echo "done"
