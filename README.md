# strongbox release script

These scripts help automate the release process for [strongbox](https://github.com/ogri-la/strongbox).

## prep.sh

Prepares a release branch of strongbox for review.

1. create a release branch.
2. update references to static version numbers in the project.clj, readme.md, security.md, etc
3. updates the changelog, changing references to 'unreleased'
4. regenerates the pom.xml file
5. commits it all, pushes to release branch and opens a PR for review with a checklist of things to do.

## release.sh

Assumes `prep.sh` has been run, the changes reviewed and the PR merged into `master`.

1. tags the release
2. creates a GitHub release from the new tag
3. generates an AppImage
3. uploads the artifacts to the Github release
4. updates the Arch AUR
5. updates Flathub

## post.sh

Switches back to `develop`, merges changes from master, truncates TODO, updates project file, etc etc.
