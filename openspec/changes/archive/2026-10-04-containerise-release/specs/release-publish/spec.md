## Purpose

Publishes an already built and verified release to GitHub, the AUR and Flathub, in a fixed order, after explicit confirmation, and safely rerunnable after a partial failure.

## ADDED Requirements

### Requirement: Publish requires a valid build
`./release.sh publish <version>` SHALL refuse to run unless the workspace has a build record for `<version>` that validates against its schema. Each artefact's current checksum SHALL equal the recorded checksum, and each derived repository's HEAD SHALL equal its recorded commit.

#### Scenario: No build
- **WHEN** `./release.sh publish 7.8.0` is run before `./release.sh build 7.8.0`
- **THEN** it exits non-zero without contacting any remote

#### Scenario: Artefact altered after build
- **WHEN** the AppImage in the workspace no longer matches its recorded checksum
- **THEN** publish exits non-zero, naming the file, without contacting any remote

### Requirement: Publish shows its plan and requires confirmation
Before any remote operation, publish SHALL list every remote operation it will perform, in order, marking those already complete. It SHALL require the user to confirm by typing the version. Without that confirmation it SHALL perform no remote operation.

#### Scenario: Confirmation typed incorrectly
- **WHEN** the user types anything other than the exact version
- **THEN** publish exits without contacting any remote for writing

### Requirement: Remote operations run in dependency order
Publish SHALL perform the following in order, stopping at the first failure:
1. push the tag `<version>` at the recorded strongbox commit
2. create the GitHub release `<version>` with the extracted release notes
3. upload the four artefacts to that release
4. push the `strongbox-flatpak` commit and tag it `<version>`
5. push the Flathub branch and open a PR to its default branch
6. push the AUR commit to the AUR and to the `ogri-la/strongbox-pkgbuild` mirror

Operations 4–6 SHALL NOT run unless operation 3 has completed, because their manifests reference URLs created by operations 2–4.

#### Scenario: Upload fails
- **WHEN** operation 3 fails because of a network error
- **THEN** publish exits non-zero, and operations 4–6 have not been performed

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
