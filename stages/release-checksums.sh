#!/bin/bash
# writes a sha256sum-format checksum file beside each artefact.
source /release-script/stages/lib.sh

cd /work/release
for artefact in *.jar *.AppImage; do
    sha256sum "$artefact" > "$artefact.sha256"
done
sha256sum --check --quiet *.sha256
log INFO "checksums written" "files=$(ls | wc -l)"
