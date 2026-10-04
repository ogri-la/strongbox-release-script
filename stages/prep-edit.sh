#!/bin/bash
# creates the release branch and commits the versioned file updates locally.
# usage: prep-edit.sh <version> <major|minor>
source /release-script/stages/lib.sh

release="$1"
kind="$2"
major_version="${release%%.*}" # '4' in '4.5.6'

cd /work/strongbox
git checkout --quiet -B "$release"

log INFO "updating project.clj"
sed --regexp-extended --in-place \
    "s/defproject ogri-la\/strongbox \"[0-9.]+-unreleased\"/defproject ogri-la\/strongbox \"$release\"/" \
    project.clj
grep --quiet --fixed-strings "defproject ogri-la/strongbox \"$release\"" project.clj \
    || die "project.clj does not declare the release after editing; expected a '-unreleased' version" "release=$release"

if [ "$kind" = major ]; then
    log INFO "updating SECURITY.md"
    grep --quiet "| $major_version.x.x" SECURITY.md || {
        sed --in-place 's/:heavy_minus_sign:/:x:               /' SECURITY.md
        sed --in-place 's/:heavy_check_mark:/:heavy_minus_sign:/' SECURITY.md
        new_section="| $major_version.x.x   | :heavy_check_mark: |"
        sed --regexp-extended --in-place "/\- \|$/a $new_section" SECURITY.md
    }
fi

grep --quiet "## $release" CHANGELOG.md || {
    log INFO "updating CHANGELOG.md"
    new_section="$release - $(date -I)" # "4.5.6 - 2020-12-31"
    sed --in-place "0,/\[Unreleased\]/s//$new_section/" CHANGELOG.md
}

log INFO "updating README.md"
# "strongbox-1.2.3-standalone.jar" => "strongbox-4.5.6-standalone.jar"
sed --in-place --regexp-extended "s/strongbox-[0-9\.]+-standalone.jar/strongbox-$release-standalone.jar/g" README.md
# "/1.2.3/" => "/4.5.6/"
sed --in-place --regexp-extended "s/\/[0-9\.]+\//\/$release\//" README.md

log INFO "updating pom.xml"
lein pom

git commit --quiet --all --message "$release"
log INFO "release branch committed locally" "branch=$release" "commit=$(git rev-parse HEAD)"
