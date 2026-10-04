prerequisites: bash, docker (`sudo systemctl start docker`), `.github-token`, `~/.ssh/aur`

`.github-token` is a classic token with the `repo` scope. GitHub revokes tokens it
considers stale, even ones without an expiry, so `prep.sh` and `release.sh publish`
check it first. if it is rejected, issue a new one at https://github.com/settings/tokens

cd strongbox-release-script
git pull
./prep.sh <version>
    review the diff, type the version to push the branch and open the PR
review PR
merge

./release.sh build <version>
    changes nothing remote
    if it stops on drift: move the downstream edit into templates/, then
        ./release.sh adopt <flathub|aur>, review git diff dist/<target>, commit, build again
inspect:
    work/<version>/release/          run the AppImage, check the jar
    git diff dist/                   everything that will be pushed, against the last release
    work/<version>/flathub, aur      one local commit each
merge any branch into master, publish runs on master
./release.sh publish <version>
    shows the plan, type the version to publish
    commits dist/ as 'release <version>' and tags this repository <version> first
    if it fails partway, fix the cause and run it again. finished steps are skipped

open https://github.com/flathub/la.ogri.strongbox
review PR
merge
wait for buildbot to succeed

cd /path/to/strongbox
git checkout master
git pull
git checkout develop
git merge master
lein clean

truncate TODO
update CHANGELOG with new sections from bottom
update project.clj with incremented version and "-unreleased"
update this doc with anything new

maintenance:
    pins.env holds every image digest and tool checksum. ./check-pins.sh checks them
    python3 -m unittest discover -s tests
    tests/integration-build.sh <version>    slow, builds the version strongbox's master declares, changes nothing remote
    tests/integration-prep.sh     prepares a major release locally, changes nothing remote
    tests/integration-publish.sh  publishes to throwaway local git remotes
    work/ can be deleted at any time after a release is published

updating pins (when a base or tool reaches end of support, or before a release):
    image:  docker pull <name>:<tag>
            docker image inspect <name>:<tag> --format '{{index .RepoDigests 0}}'
            write <name>:<tag>@sha256:<digest> to the IMAGE_ line, and update its support end date
    tool:   take the sha256 from the release's checksums file or the GitHub API asset 'digest',
            or download it and run sha256sum. update the _VERSION and _SHA256 lines together
    Temurin: TEMURIN_VERSION must match JAVA_RUNTIME_VERSION in the new image, the image build checks this
    then:   ./check-pins.sh
            tests/integration-build.sh <version>, which also re-checks the glibc floor and the JRE start
    images are rebuilt automatically when pins.env or images/ change
