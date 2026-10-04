# release-publish Specification

## Purpose

Publishes an already built and verified release to GitHub, the AUR and Flathub, in a fixed order, after explicit confirmation, and safely rerunnable after a partial failure.

## Requirements

### Requirement: Publish requires a valid build
`./release.sh publish <version>` SHALL refuse to run unless `dist/` has a build record for `<version>` that validates against its schema. Each artefact's current checksum SHALL equal the recorded checksum, and each derived repository's HEAD SHALL equal its recorded commit. Each derived repository's files SHALL equal the files in `dist/`.

#### Scenario: No build
- **WHEN** `./release.sh publish 7.8.0` is run before `./release.sh build 7.8.0`
- **THEN** it exits non-zero without contacting any remote

#### Scenario: Artefact altered after build
- **WHEN** the AppImage in the workspace no longer matches its recorded checksum
- **THEN** publish exits non-zero, naming the file, without contacting any remote

#### Scenario: Rendered file edited after build
- **WHEN** `dist/flatpak/metainfo.xml` was edited after the build
- **THEN** publish exits non-zero, naming the file, without contacting any remote

### Requirement: Publish shows its plan and requires confirmation
Before any remote operation, publish SHALL list every remote operation it will perform, in order, marking those already complete. It SHALL require the user to confirm by typing the version. Without that confirmation it SHALL perform no remote operation.

#### Scenario: Confirmation typed incorrectly
- **WHEN** the user types anything other than the exact version
- **THEN** publish exits without contacting any remote for writing

### Requirement: Remote operations run in dependency order
Publish SHALL perform the following in order, stopping at the first failure:
1. push this repository's release commit and its tag `<version>`
2. push the tag `<version>` at the recorded strongbox commit
3. create the GitHub release `<version>` with the rendered release notes
4. upload the four artefacts to that release
5. push the Flathub branch and open a PR to its default branch
6. push the AUR commit to the AUR

Operations 5 and 6 SHALL NOT run unless operation 4 has completed. Their files reference the artefacts uploaded by operation 4, and the metadata files at this repository's tag pushed by operation 1.

#### Scenario: Upload fails
- **WHEN** operation 4 fails because of a network error
- **THEN** publish exits non-zero, and operations 5 and 6 have not been performed

#### Scenario: Release record pushed first
- **WHEN** operation 2 fails
- **THEN** tag `<version>` of this repository already records what the release is publishing, and a rerun continues from operation 2

### Requirement: Publish is idempotent and resumable
Before each operation, publish SHALL check whether its effect already exists remotely. It SHALL skip an operation whose effect exists and matches the build record. It SHALL stop without changing anything if an effect exists and does not match.

#### Scenario: Rerun after partial failure
- **WHEN** a previous publish completed operations 1–3 and failed at 4
- **AND** publish is run again
- **THEN** operations 1–3 are reported as already complete and skipped, and publishing continues from operation 4

#### Scenario: Remote asset differs
- **WHEN** the GitHub release already has a `strongbox-7.8.0-x86_64.AppImage` asset whose checksum differs from the build record
- **THEN** publish stops, reporting both checksums, and does not replace the asset

#### Scenario: Flathub PR already open
- **WHEN** an open PR from branch `7.8.0` exists on `flathub/la.ogri.strongbox`
- **THEN** publish reports its URL and does not open another

### Requirement: Publish does not rebuild
Publish SHALL transmit only the artefacts and commits recorded by the build. It SHALL NOT compile, regenerate, or re-derive anything.

#### Scenario: Catalogue changed upstream
- **WHEN** the upstream catalogue changed between build and publish
- **THEN** the uploaded jar is byte-identical to the jar recorded at build time

### Requirement: Published releases are tagged in this repository
Publish SHALL commit `dist/` to this repository's default branch with the message `release <version>`, and tag that commit `<version>`. The tag SHALL be pushed before any other remote operation. The tagged commit SHALL contain the scripts, templates and rendered files that produced the release. Publish SHALL refuse to run if this repository is not on its default branch, or if its working tree has changes outside `dist/`.

#### Scenario: Release traced to this repository
- **WHEN** `7.8.0` has been published
- **THEN** tag `7.8.0` of this repository holds the `dist/` files that were pushed to Flathub and the AUR, and the templates and scripts that rendered them

#### Scenario: Uncommitted template change
- **WHEN** a template has uncommitted changes and `./release.sh publish 7.8.0` is run
- **THEN** publish exits non-zero without contacting any remote, naming the changed file

#### Scenario: Not on the default branch
- **WHEN** this repository is on a branch other than its default branch
- **THEN** publish exits non-zero without contacting any remote
