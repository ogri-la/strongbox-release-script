#!/bin/bash
# generate release artefacts for strongbox
set -eu

release="$1" # "1.2.3"

# strongbox is required
test -d strongbox

rm -rf ./release
mkdir ./release

if [ ! -d strongbox-appimage ]; then
    git clone https://github.com/ogri-la/strongbox-appimage
else
    (
        cd strongbox-appimage
        git reset --hard
        git checkout master
        git pull
    )
fi

cp strongbox-appimage/build-appimage.sh ./
./build-appimage.sh
rm ./build-appimage.sh

mv ./strongbox.appimage "./release/strongbox-$release-x86_64.AppImage" # "strongbox.appimage" => "strongbox-7.0.1-x86_64.AppImage"
mv "./strongbox/target/strongbox-$release-standalone.jar" ./release/

(
    cd release
    sha256sum "strongbox-$release-x86_64.AppImage" > "strongbox-$release-x86_64.AppImage.sha256"
    sha256sum "strongbox-$release-standalone.jar" > "strongbox-$release-standalone.jar.sha256"
)
