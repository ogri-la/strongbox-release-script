# strongbox release script

These scripts help automate the release process for [strongbox](https://github.com/ogri-la/strongbox).

They run on the host and need only `bash`, coreutils and `docker`. Every step runs in a short-lived container
built from pinned images (see `pins.env`). Repositories are cloned fresh for each release into
`work/`, and credentials are given only to the steps that write to a remote.

Packaging files are rendered from `templates/` into `dist/`, with every version, URL and checksum
written out in full, in the way `makepkg` renders a `PKGBUILD`. `publish` commits `dist/` and tags this
repository `<version>`, so each strongbox release maps to a tag here showing what was generated and pushed.
The Flathub and AUR repositories hold only copies of files in `dist/`.

See `release.md` for the full checklist.

## prep.sh

    ./prep.sh <version> [branch]

Prepares a release branch of strongbox for review.

1. checks the GitHub token.
2. clones strongbox at `branch` (default `develop`) and checks the version is greater than the last release.
3. creates a release branch, updates `project.clj`, `CHANGELOG.md`, `README.md`, `SECURITY.md` (major releases) and regenerates `pom.xml`.
4. shows the commit and asks for the version to be typed.
5. pushes the branch and opens a PR against `master`.

## release.sh build

    ./release.sh build <version>

Assumes the prep PR has been merged into `master`. Changes nothing remote and uses no credentials.

1. clones strongbox, the Flathub repository and the AUR package.
2. checks the Flathub and AUR repositories still hold what was last pushed to them (see "drift" below).
3. checks `master` declares the version, the changelog has it, and any existing tag points at `master`.
4. builds the uberjar, and the AppImage with `appimage/build-appimage.sh` and a JRE from the pinned Temurin 17 JDK.
5. checks no shared object in the AppImage needs a glibc newer than `GLIBC_CEILING`, and that its JRE starts on that glibc.
6. renders `templates/` with the version and the artefacts' checksums.
7. runs Flathub's linter on the manifest and metainfo, and builds the AUR package offline from the local AppImage.
8. copies the rendered files into the Flathub and AUR clones as local commits.
9. writes `dist/build.json`, a record of every input and output, then replaces `dist/` with the rendered files.

A build that fails leaves `dist/` unchanged. Review `git diff dist/` before publishing.

## drift and release.sh adopt

    ./release.sh adopt {flathub|aur}

`build` stops if a downstream repository differs from what was last pushed to it, for example when a
Flathub contributor changes the runtime. Move the change into `templates/`, then run `adopt` to copy the
downstream files into `dist/<target>`, review `git diff dist/<target>` and commit. `adopt` changes nothing remote.

## release.sh publish

    ./release.sh publish <version>

Publishes exactly what `build` recorded. Runs on `master`, with no uncommitted changes outside `dist/`.
Checks the record still matches the workspace and `dist/`, checks the GitHub token, shows what will be
done and asks for the version to be typed. Then, in order:

1. commits `dist/` as `release <version>`, tags this repository `<version>`, and pushes both.
2. tags the strongbox release.
3. creates the GitHub release.
4. uploads the artefacts.
5. opens a PR on Flathub. Its manifest fetches `dist/flatpak/` at this repository's tag.
6. updates the AUR.

Steps already done are skipped, so it can be rerun after a failure. It stops without changing
anything when remote state differs from the build.

## tests

    python3 -m unittest discover -s tests
    ./check-pins.sh
    tests/integration-build.sh <version>
    tests/integration-prep.sh
    tests/integration-publish.sh

## retired repositories

`ogri-la/strongbox-flatpak`, `ogri-la/strongbox-pkgbuild` and `ogri-la/strongbox-appimage` are no longer
used. Their content is now in `templates/`, `dist/` and `appimage/`.
