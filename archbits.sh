#!/bin/bash
# updates the `pkgbuild`, runs `makepkg` within a container.
# called after releasing Strongbox on Github.

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
    ../parse-changelog ../strongbox/CHANGELOG.md "$release" > changelog
    echo >> changelog
    sed --in-place --regexp-extended "s/pkgver=.+/pkgver=$release/" PKGBUILD
    sed --in-place --regexp-extended "s/pkgrel=.+/pkgrel=1/" PKGBUILD

    strongbox_sha256=$(cut -d " " -f 1 "../strongbox/release/strongbox-$release-x86_64.AppImage.sha256")
    strongbox_desktop_sha256=$(sha256sum strongbox.desktop | cut -d " " -f 1)
    sed --in-place --regexp-extended "s/strongbox_sha256=.+/strongbox_sha256=\"$strongbox_sha256\"/" PKGBUILD
    sed --in-place --regexp-extended "s/strongbox_desktop_sha256=.+/strongbox_desktop_sha256=\"$strongbox_desktop_sha256\"/" PKGBUILD

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
