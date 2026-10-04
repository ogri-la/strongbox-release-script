# release-environment Specification

## Purpose

Defines the runtime contract for every release pipeline: what the host must provide, how stages are isolated, which inputs are pinned, and how credentials reach the stages that need them.

## Requirements

### Requirement: Host prerequisites are minimal
The release pipelines SHALL require only `bash`, coreutils and `docker` on the host. All other tools (JDK, `lein`, `gh`, `parse-changelog`, `appimagetool`, `makepkg`, `python3`, `xmllint`, `appstreamcli`) SHALL run inside containers.

#### Scenario: Fresh host
- **WHEN** a host with only `bash`, coreutils and `docker` runs `./prep.sh <version>`
- **THEN** the pipeline builds or pulls the images it needs and runs to completion without asking for any other host package

#### Scenario: Missing docker
- **WHEN** `docker` is not available or the daemon is not running
- **THEN** the pipeline exits non-zero before any stage runs, with an error naming the missing prerequisite

### Requirement: Stages are stateless
Each stage SHALL run in a new container that is removed when it exits. The only state carried between stages SHALL be the per-release workspace directory on the host. Caches (such as the Maven repository) MAY persist between runs, but deleting them SHALL NOT change any stage's output.

#### Scenario: No residue in containers
- **WHEN** a pipeline finishes, successfully or not
- **THEN** no container started by the pipeline remains

#### Scenario: Cache removal
- **WHEN** the dependency cache is deleted and the build is rerun for the same inputs
- **THEN** the build succeeds and produces artefacts with the same recorded input versions

### Requirement: Workspace is per-release and fresh
Each pipeline SHALL operate on a workspace directory keyed by release version. A `prep` or `release build` run SHALL recreate the repository clones in that workspace from their remotes, rather than reuse clones from earlier runs.

#### Scenario: Leftover clone from an earlier attempt
- **WHEN** a workspace for version `V` already contains a `strongbox` clone with local modifications
- **AND** `./release.sh build V` is run
- **THEN** the clone is replaced by a fresh clone, and the local modifications have no effect on the output

#### Scenario: Files owned by the user
- **WHEN** any stage writes to the workspace
- **THEN** the files are owned by the invoking host user, not by root

### Requirement: Inputs are pinned
Every container base image SHALL be referenced by digest. The JDK and every downloaded tool SHALL be referenced by exact version and verified against a recorded SHA-256 checksum. All pins SHALL be recorded in one committed file.

#### Scenario: Tampered download
- **WHEN** a downloaded tool's checksum does not match its recorded checksum
- **THEN** the image build fails, and no stage runs with that tool

#### Scenario: Unpinned reference
- **WHEN** a container definition refers to an image by tag only
- **THEN** a repository check fails, naming the unpinned reference

### Requirement: Long-term supported base
Build and publish images SHALL use an operating system release and a JDK 17 distribution that both receive security updates on the date the pins are last changed.

#### Scenario: Base out of support
- **WHEN** the pinned base OS or JDK distribution has reached end of support
- **THEN** the pins file records this in the base's entry, and updating it is a documented release-maintenance task

### Requirement: Fetching is anonymous
All repositories SHALL be cloned and fetched over https without credentials. Push access SHALL be configured separately from fetch access, so a stage without credentials cannot push.

#### Scenario: Credential-less stage attempts a push
- **WHEN** a stage that was not given credentials runs `git push`
- **THEN** the push fails with an authentication error, and nothing changes on the remote

### Requirement: Credentials are scoped to remote stages
Credentials SHALL be mounted read-only, and only into stages that write to a remote. Each stage SHALL receive only the credentials its remote requires: the GitHub token for GitHub, the AUR key for the AUR. Credentials SHALL NOT be written into any image layer, workspace file or log.

#### Scenario: Build stage has no credentials
- **WHEN** the build stage runs
- **THEN** no GitHub token, ssh key or ssh agent socket is available inside its container

#### Scenario: AUR stage
- **WHEN** the AUR push stage runs
- **THEN** it has the AUR key, and no other credential

#### Scenario: Credential missing on host
- **WHEN** a remote stage is about to run and its credential file is missing on the host
- **THEN** the pipeline stops before that stage, naming the missing file, and no earlier remote stage is repeated

### Requirement: GitHub token is verified before use
Any pipeline that needs the GitHub token SHALL verify it against the GitHub API before its first remote stage. The token SHALL authenticate and SHALL carry the `repo` scope. The pipeline SHALL also verify that the token's account has push permission on every repository that pipeline writes to. A token with no expiry date SHALL NOT be treated as valid on that basis, because GitHub can revoke unused tokens regardless of expiry. The pipeline SHALL verify the token on every run. On failure, the pipeline SHALL stop before any remote stage runs, and the error SHALL state the likely cause and the remedy. `release build` needs no token and SHALL NOT verify it.

#### Scenario: Revoked token
- **WHEN** `.github-token` holds a token that GitHub has revoked
- **AND** `./prep.sh 7.8.0` is run
- **THEN** the pipeline stops before cloning anything, stating that GitHub rejected the token (HTTP 401) and that it may have been revoked, and that a new classic token with the `repo` scope must be written to `.github-token`

#### Scenario: Missing scope
- **WHEN** the token authenticates but its scopes do not include `repo`
- **THEN** the pipeline stops before any remote stage, naming the scopes found and the scope required

#### Scenario: No push permission
- **WHEN** the token authenticates with the `repo` scope, but its account cannot push to `flathub/la.ogri.strongbox`
- **AND** `./release.sh publish 7.8.0` is run
- **THEN** publish stops before any remote write, naming the repository

#### Scenario: Valid token
- **WHEN** the token authenticates with the `repo` scope and has push permission on every target repository
- **THEN** the pipeline proceeds, and the token value does not appear in any output

### Requirement: Remote hosts are verified
ssh connections SHALL verify host keys against a `known_hosts` file committed to this repository. Trust-on-first-use SHALL NOT be enabled.

#### Scenario: Host key mismatch
- **WHEN** `aur.archlinux.org` presents a host key not in the committed `known_hosts`
- **THEN** the connection fails and nothing is pushed
