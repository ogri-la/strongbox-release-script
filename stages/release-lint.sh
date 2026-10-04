#!/bin/bash
# validates the rendered metainfo with appstreamcli. Flathub's own linter runs in its own stage.
source /release-script/stages/lib.sh

xmllint --noout /work/dist/flatpak/metainfo.xml || die "metainfo.xml is not well-formed XML"
# fails on errors, reports warnings and pedantic issues without failing
appstreamcli validate --no-net /work/dist/flatpak/metainfo.xml || die "metainfo.xml failed validation"
