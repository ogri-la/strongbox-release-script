#!/bin/bash
# updates the pkgbuild, runs makepkg within a container
# calling after releasing strongbox on github

set -eux

release="$1" # "1.2.3"

# strongbox is required
test -d strongbox

echo "--- cloning strongbox-pkgbuild ---"
rm -rf strongbox-pkgbuild
export GIT_SSH_COMMAND='ssh -i /home/vagrant/.ssh/aur'
git clone ssh://aur@aur.archlinux.org/strongbox.git strongbox-pkgbuild
(
    cd strongbox-pkgbuild
    git remote add github ssh://git@github.com/ogri-la/strongbox-pkgbuild
    echo

    echo "--- updating PKGBUILD ---"
    sed --in-place --regexp-extended "s/pkgver=.+/pkgver=$release/" PKGBUILD
    sed --in-place --regexp-extended "s/pkgrel=.+/pkgrel=1/" PKGBUILD

    sha256=$(cut -d " " -f 1 ../strongbox/release/strongbox.sha256)
    sed --in-place --regexp-extended "s/sha256sums=.+./sha256sums=(\"$sha256\")/" PKGBUILD

    sudo systemctl start docker
    sudo docker build . \
        --file ../Dockerfile \
        --tag arch-linux-make-pkg
    sudo docker run \
        --rm \
        arch-linux-make-pkg \
        makepkg --printsrcinfo > .SRCINFO

    git commit -am "release $release"
    git push
    git push github
    echo
)
