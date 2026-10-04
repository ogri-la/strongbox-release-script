## 1. Verify assumptions

- [x] 1.1 Download the current Temurin 17 JDK tarball, `jlink` a JRE with strongbox's module list, and measure its highest `GLIBC_` requirement. Record the result. If it is above 2.27, choose an alternative vendor (D2) before continuing.
- [x] 1.2 Confirm `makepkg` uses a pre-placed source file whose checksum verifies, with `--network none` (D10).
- [x] 1.3 Confirm `.github-token` is valid and has the `repo` scope (`x-oauth-scopes` header of `GET /user`), and that the account has push permission on `ogri-la/strongbox`, `ogri-la/strongbox-flatpak`, `ogri-la/strongbox-pkgbuild` and `flathub/la.ogri.strongbox`.

## 2. Pins and repository hygiene

- [x] 2.1 Add `pins.env` with image digests (`eclipse-temurin:17-jdk-noble`, `ubuntu:24.04`, `ubuntu:18.04`, `archlinux:base-devel`), the Temurin version, the versions and SHA-256s of `gh`, `parse-changelog`, `appimagetool` and `lein`, and `GLIBC_CEILING=2.27`.
- [x] 2.2 Add a committed `known_hosts` for `aur.archlinux.org`, with its source and refresh procedure. GitHub is reached over https only (D5), so it has no entry.
- [x] 2.3 Add `work/` to `.gitignore`.
- [x] 2.4 Add a `check-pins` script that fails on any tag-only image reference in Dockerfiles or orchestrator scripts.

## 3. Images

- [x] 3.1 `images/sb-build/Dockerfile`: Temurin 17 JDK base, pinned `lein`, `binutils`, `git`, `wget`, `unzip`, and pinned `appimagetool` verified by checksum.
- [x] 3.2 `images/sb-publish/Dockerfile`: Ubuntu 24.04 base, `git`, `openssh-client`, `python3`, `libxml2-utils`, `jq`, `appstream`, and pinned `gh` and `parse-changelog` verified by checksum.
- [x] 3.3 Run `archlinux:base-devel` by digest as the host user with `HOME=/tmp`, with no image of its own (task 1.2).
- [x] 3.4 Image build function: tags each image by a hash of its Dockerfile and `pins.env`, and builds only when that tag is missing.

## 4. Stage runner

- [x] 4.1 `lib/stages.sh`: declare the stage record shape (D1) and `run_stage`, which maps a record to `docker run --rm --user <uid>:<gid>` with its mounts, network mode (`none` / default) and the declared secrets only.
- [x] 4.2 Host prerequisite check: `docker` is present and the daemon is reachable. Fail before any stage otherwise.
- [x] 4.3 Secret providers: `github_token` reads `.github-token` into `--env GITHUB_TOKEN`; `aur_key` mounts `~/.ssh/aur` and `known_hosts` read-only. Fail with the missing path before the stage runs.
- [x] 4.4 Fresh-clone helper: https clone into `work/<version>/<name>`, replacing any existing directory, with optional `pushurl`.
- [x] 4.5 Confirmation helper: shows a plan and requires typed input. It refuses when no terminal is attached unless an explicit flag is given.
- [x] 4.6 Token check stage (`sb-publish`, `github_token`): `GET /user` must return 200 with `repo` in `x-oauth-scopes`, and `permissions.push` must be true on each given repository. On failure, report the cause (revoked, missing scope or no push permission) and the remedy, without printing the token.

## 5. Pure helpers and their tests

- [x] 5.1 Version comparison (`major.minor.patch`, integer components), replacing `semver2.sh` and the single-digit major detection. Unit and property tests.
- [x] 5.2 glibc maximum: given `objdump -T` output, return the highest `GLIBC_x.y`. Unit and property tests.
- [x] 5.3 `schemas/build-record.schema.json` and a standard-library validator for it. Unit tests for valid and invalid records.
- [x] 5.4 Unit tests for `generate-metainfo.py` and `generate-flathub.py`, using fixture changelogs and files.

## 6. Prep pipeline

- [x] 6.0 Run the token check against `ogri-la/strongbox` before any other stage.
- [x] 6.1 Fetch stage (`sb-publish`, network fetch): clone strongbox at `<branch>` and list tags.
- [x] 6.2 Version check against the highest existing release tag, before any edit.
- [x] 6.3 Edit stage (`sb-build`, no secrets): create branch `<version>`, update `project.clj`, `CHANGELOG.md`, `README.md`, and `SECURITY.md` on a major release; run `lein pom`; commit locally.
- [x] 6.4 Show the diff and plan, then confirm.
- [x] 6.5 Remote stage (`sb-publish`, `github_token`): push the branch and open the PR with `strongbox--pr-template.md`, skipping creation if a PR from `<version>` to `master` already exists.

## 7. Release build pipeline

- [x] 7.1 Fetch stage: fresh clones of `strongbox` (`master`), `strongbox-appimage`, `strongbox-flatpak`, `flathub/la.ogri.strongbox` and the AUR repo. Record the commit SHAs.
- [x] 7.2 Source consistency checks: `project.clj` version, `CHANGELOG.md` section, and that the remote tag is absent or at HEAD.
- [x] 7.3 Build stage (`sb-build`, no secrets): place the pinned `appimagetool`, set `APPIMAGE_EXTRACT_AND_RUN=1`, and run `build-appimage.sh`. Move the outputs into `release/` with versioned names, and record the catalogue's SHA-256.
- [x] 7.4 glibc floor check over the extracted AppImage and the `.so` files inside its jar, against `GLIBC_CEILING`.
- [x] 7.5 JRE start check: run `usr/bin/java -version` in the pinned `ubuntu:18.04` container.
- [x] 7.6 Write the `.sha256` files.
- [x] 7.7 Derive stage (`sb-publish`, network none): release notes via `parse-changelog`, `metainfo.xml` via `generate-metainfo.py` plus `xmllint`, `appstreamcli validate`, `la.ogri.strongbox.yml` via `generate-flathub.py`. Commit to `strongbox-flatpak`, and to the `flathub` branch `<version>`.
- [x] 7.8 AUR derive stage (`archlinux:base-devel`, network none): update `PKGBUILD` (`pkgver`, `pkgrel`, checksums), `changelog` and `.SRCINFO`; run a local `makepkg` with the pre-placed AppImage; commit.
- [x] 7.9 Write `build.json` last. Remove any stale record at the start of the build.

## 8. Release publish pipeline

- [x] 8.0 Run the token check against all four target repositories before any other stage.
- [x] 8.1 Verify `build.json` against its schema, the artefact checksums, and the derived repositories' HEADs, before contacting any remote.
- [x] 8.2 Implement `check` and `apply` for each operation, in spec order: tag, GitHub release, asset upload, `strongbox-flatpak` push and tag, Flathub push and PR, AUR push and mirror push.
- [x] 8.3 Print the plan with `done` / `pending` / `conflict` per operation, and require the version to be typed.
- [x] 8.4 Execute pending operations in order, re-checking after each and stopping on the first failure or conflict.

## 9. Integration and documentation

- [x] 9.1 Integration test (`tests/integration-build.sh`): `./release.sh build 7.7.0` with no credential files present. Assert success, a valid record, agreeing checksums, and no remote writes.
- [x] 9.2 Rewrite `release.md` for the build → inspect → publish workflow, including the two human gates and token scope notes.
- [x] 9.3 Update `README.md` to describe `prep.sh`, `release.sh build` and `release.sh publish`, and the host prerequisites.
- [x] 9.4 Integration test (`tests/integration-prep.sh`): a major-release prep commits the `SECURITY.md` rows and pushes nothing without a terminal.
- [x] 9.5 Integration test (`tests/integration-publish.sh`): the publish git operations against local bare remotes, including reruns and conflicts.
- [x] 9.6 Document updating pins in `release.md`.

## 10. Retire the VM

- [x] 10.1 Remove `Vagrantfile`, `bootstrap.sh`, `artefacts.sh`, `archbits.sh`, `flatpakbits.sh`, the empty `post.sh` and the root `Dockerfile`. Extend `check-pins.sh` to every Dockerfile in the repository and to `tests/`.
