## MODIFIED Requirements

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
