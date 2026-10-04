#!/bin/bash
# validates the rendered metainfo with appstreamcli. Flathub's own linter runs in its own stage.
source /release-script/stages/lib.sh

xmllint --noout /work/dist/flatpak/metainfo.xml || die "metainfo.xml is not well-formed XML"
# appstreamcli exits non-zero on warnings as well as errors. only errors ('E:' lines) fail the build;
# warnings and infos are shown. Flathub's own linter, in its own stage, decides what Flathub rejects.
rc=0
output=$(appstreamcli validate --no-net /work/dist/flatpak/metainfo.xml 2>&1) || rc=$?
printf '%s\n' "$output"
case "$rc" in
    0 | 3) ;;
    *) die "appstreamcli did not run" "exit=$rc" ;;
esac
if grep --quiet '^E:' <<< "$output"; then
    die "metainfo.xml failed validation"
fi
[ "$rc" = 0 ] || log WARN "metainfo.xml has validation warnings, not failing the build"
