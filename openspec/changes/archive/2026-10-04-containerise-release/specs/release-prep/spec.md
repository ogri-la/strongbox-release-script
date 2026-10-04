## Purpose

Prepares a release branch of strongbox: validates the requested version, updates versioned files, and opens a pull request for review, with all edits inspectable locally before anything is pushed.

## ADDED Requirements

### Requirement: Version is validated before any edit
`./prep.sh <version> [branch]` SHALL accept a `major.minor.patch` version and an optional source branch (default `develop`). It SHALL reject the version before editing any file if it is malformed, or not strictly greater than the highest existing `major.minor.patch` tag.

#### Scenario: Version lower than last release
- **WHEN** the last release tag is `7.7.0` and `./prep.sh 7.6.0` is run
- **THEN** the pipeline exits non-zero, stating that `7.6.0` is less than `7.7.0`, and no files are modified

#### Scenario: Version equal to last release
- **WHEN** the last release tag is `7.7.0` and `./prep.sh 7.7.0` is run
- **THEN** the pipeline exits non-zero, stating that the versions are equal

#### Scenario: Malformed version
- **WHEN** `./prep.sh 7.8` is run
- **THEN** the pipeline exits non-zero before cloning anything

#### Scenario: Double-digit major version
- **WHEN** the last release is `9.4.0` and `./prep.sh 10.0.0` is run
- **THEN** the version is accepted and treated as a major release

### Requirement: Versioned files are updated
Prep SHALL create a branch named `<version>` from the source branch, and update:
- `project.clj`: the `-unreleased` version becomes `<version>`.
- `CHANGELOG.md`: the `[Unreleased]` heading becomes `<version> - <ISO date>`.
- `README.md`: any references to a versioned standalone jar or release path use `<version>`.
- `SECURITY.md`, for major releases only: a row for the new major version is added and older rows are demoted.
- `pom.xml`: regenerated.

All changes SHALL be committed to the local branch.

#### Scenario: Minor release
- **WHEN** `./prep.sh 7.8.0` is run against a `develop` whose `project.clj` says `7.8.0-unreleased`
- **THEN** the local branch `7.8.0` has a single commit updating `project.clj`, `CHANGELOG.md` and `pom.xml`, plus `README.md` if it has versioned references, and `SECURITY.md` is unchanged

#### Scenario: Major release
- **WHEN** `./prep.sh 8.0.0` is run and `SECURITY.md` has no `8.x.x` row
- **THEN** `SECURITY.md` gains an `8.x.x` supported row, and the previously supported row is demoted

### Requirement: Local review before push
After committing, prep SHALL show the commit's diff and a summary of the remote operations it is about to perform (branch push, PR creation). It SHALL require explicit confirmation before performing them. Declining SHALL leave the remotes untouched and the local branch in the workspace.

#### Scenario: Declined
- **WHEN** the user declines at the confirmation prompt
- **THEN** no branch is pushed, no PR is created, and the workspace keeps the prepared commit

#### Scenario: Non-interactive run
- **WHEN** prep runs without a terminal and without an explicit confirmation flag
- **THEN** it stops before any remote operation

### Requirement: Pull request is opened
After confirmation, prep SHALL push the branch and open a pull request from `<version>` to `master`, titled `<version>`, using `strongbox--pr-template.md` as its body.

#### Scenario: Confirmed
- **WHEN** the user confirms
- **THEN** the branch `<version>` exists on `ogri-la/strongbox`, and an open PR from `<version>` to `master` exists with the template's checklist

#### Scenario: PR already exists
- **WHEN** an open PR from `<version>` to `master` already exists
- **THEN** prep reports the existing PR URL and does not create a second one
