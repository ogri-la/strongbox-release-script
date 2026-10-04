## Context

See `proposal.md` for motivation. The current state, as measured from the 7.7.0 artefacts and the scripts:

| component | source today | highest `GLIBC_` |
|---|---|---|
| AppImage runtime | `appimagetool` 13 | 2.14 |
| JavaFX natives inside `app.jar` | Gluon Maven jars, OpenJFX `22-ea+16` | 2.15 |
| JRE (`libjvm.so` and the rest) | Ubuntu 18.04 `openjdk-17`, 17.0.7 | **2.27** |

The glibc floor of the AppImage is set by whoever compiled the JDK binaries that `jlink` copies, not by the OS the build runs on. JDK 17 is the minimum that OpenJFX 22 supports (strongbox #442, which fixed #441), so the major version is fixed. Patch releases within 17 are free to move.

Other constraints:
- `ogri-la/strongbox-appimage/build-appimage.sh` runs `lein uberjar`, downloads `full-catalogue.json` from `master`, runs `jlink` with whatever `java` is on `PATH`, and uses `./appimagetool` from its own directory when that file exists.
- The AUR `PKGBUILD` pulls the AppImage from the GitHub release URL. The Flathub manifest pulls the jar from the GitHub release and three files from a `strongbox-flatpak` tag. Both therefore depend on GitHub publication.
- The release has two human gates: merging the strongbox PR after `prep`, and merging the Flathub PR after `publish`.

## Goals / Non-Goals

**Goals:**
- Every stage is a pure function of (pinned images, workspace inputs, credentials for remote stages only), so reruns are predictable.
- Nothing remote changes until everything that can be checked locally has been checked.
- A failed publish is resumable without manual cleanup of remote state.

**Non-Goals:**
- Byte-identical, reproducible AppImages. Jar and squashfs timestamps and the moving catalogue make this a separate project. The build record captures inputs instead.
- Building or installing the Flatpak locally. `flatpak-builder` needs bubblewrap and user namespaces inside the container, which means `--privileged` or extra capabilities, and its sources are remote URLs that do not exist until publish. Flathub's own buildbot remains the Flatpak build check. Local Flatpak checks are limited to metainfo validation and checksum agreement.
- Automating the post-release steps in `release.md` (merging `master` into `develop`, truncating TODO, bumping `-unreleased`).
- CI or remote execution.
- Changing OpenJFX versions in strongbox, including the move from `22-ea+16` to a GA release.

## Decisions

### D1. Host-side bash orchestrator, stages as data

`prep.sh` and `release.sh` run on the host and do nothing except sequence stages. Each stage is a record:

```
stage = { name, image, command, mounts, secrets, network }
          network ∈ { none, fetch, remote }
          secrets ⊆ { github_token, aur_key }
```

A single `run_stage` function turns a record into one `docker run --rm` invocation. The pipelines are ordered sequences of these records. The record shape is what the credential, network and statelessness requirements are checked against, so it is declared once in `lib/stages.sh` with a short comment explaining the shape.

- *Alternative: one long-lived "VM-shaped" container.* Rejected because it needs docker-in-docker for `makepkg`, and gives every step every credential.
- *Alternative: Python orchestrator.* Python is already used for the generators. Bash was chosen anyway, because the orchestration is only sequencing and mounting, and keeping the host to `bash` + `docker` is a requirement.

### D2. Two built images, two used as-is

| image | base | contents | used by |
|---|---|---|---|
| `sb-build` | `eclipse-temurin:17-jdk-noble`, by digest | Temurin 17 JDK, `lein` 2.12.0 (pinned script and jar), `appimagetool` 1.9.1 and type2 runtime `20251108` (both pinned), `binutils`, `git`, `python3`, and the fonts and GTK libraries JavaFX loads when strongbox is compiled | prep edit, release build, glibc check |
| `sb-publish` | `ubuntu:24.04`, by digest | `git`, `openssh-client`, `gh` (pinned release), `parse-changelog` (pinned), `python3`, `libxml2-utils`, `jq`, `appstream` | fetch, derive, all remote stages |
| `archlinux:base-devel` | used as-is, by digest | `makepkg` | `.SRCINFO`, local `makepkg` |

`ubuntu:18.04`, pinned by digest, is also used unmodified, as the glibc-2.27 ceiling container for the JRE start check. `archlinux:base-devel` needs no image of its own: running it as `--user <uid>:<gid>` with `HOME=/tmp` satisfies `makepkg`'s refusal to run as root (task 1.2).

Temurin is chosen because its Linux binaries are built against an old glibc baseline and are patched quarterly for the life of 17 LTS. This decouples "old glibc floor" from "old OS", so `sb-build` can run on a supported Ubuntu LTS (noble, supported to 2029) and still produce an AppImage with a low floor. Measured on 2026-10-03 (task 1.1): a `jlink` JRE built from `eclipse-temurin:17-jdk-noble` (Temurin 17.0.20.1+1, build OS glibc 2.39) requires at most `GLIBC_2.9` (`libnio.so`; `libjvm.so` needs 2.7). Combined with the JavaFX natives (2.15), the expected AppImage floor is 2.15, down from 2.27. The 2.27 ceiling therefore has headroom. It stays at 2.27 so that a JavaFX upgrade does not fail the build, unless that upgrade would drop support for systems strongbox runs on today.

- *Alternative: keep an old Ubuntu as the base.* Rejected because it ties the JDK patch level to an OS that no longer receives updates, which is how 17.0.7 became stale.
- *Alternative: Arch base for everything.* Rejected because Arch's JDK is built against current glibc.

### D3. Pins in one file

`pins.env` records every image digest, the Temurin version, the `gh`, `parse-changelog`, `appimagetool` and `lein` versions, their SHA-256 checksums, and the glibc ceiling. Dockerfiles take these as build arguments, and the orchestrator reads the image references from the same file. A `check-pins` script fails if any `FROM` or `docker run` image reference is not digest-pinned.

Images are tagged locally by a hash of their Dockerfile and `pins.env`. A pin change therefore rebuilds the image, and an unchanged pin reuses it. Image reuse is a cache: removing the images changes nothing except how long the first run takes.

### D4. Workspace layout

```
work/prep-<version>/
  strongbox/              fresh https clone of <branch>, local release branch
work/<version>/
  strongbox/              fresh https clone of master
  strongbox-appimage/     fresh https clone
  strongbox-flatpak/      fresh https clone, local commit
  flathub/                fresh https clone of flathub/la.ogri.strongbox, local branch <version>
  aur/                    fresh https clone of aur.archlinux.org/strongbox.git, local commit
  release/                jar, AppImage and their .sha256 files, exactly what is uploaded
  release-notes.md        the version's changelog section
  state/                  one file per fact a stage records, assembled into build.json
  tmp/                    the extracted AppImage and the offline AUR build
  build.json              build record (written last)
```

`prep` and `release` use separate workspaces, so a release build never replaces a prepared branch that has not been pushed.

`work/` is git-ignored. The workspace is the only state shared between stages, and between `build` and `publish`. Clones are always recreated by `prep` and `release build`. Only `publish` reads an existing workspace, and it verifies that workspace against `build.json` first.

A host directory, `~/.cache/strongbox-release/m2`, is mounted as `~/.m2` in `sb-build`. A host directory is used instead of a named docker volume, because a volume would be owned by root and unwritable by the host user. Its contents are content-addressed by Maven, so deleting it has no effect on output.

All containers run as `--user $(id -u):$(id -g)` with `HOME` on a throwaway tmpfs, so workspace files belong to the host user. `ssh` refuses to run for a uid without a passwd entry, so `sb-publish`'s entrypoint adds one for the current uid before running the stage.

### D5. Fetch over https, push with scoped credentials

Every clone uses an https URL. Where a stage later pushes, the clone gets `remote.origin.pushurl` set separately:

- **GitHub repos** (`strongbox`, `strongbox-flatpak`, `flathub/la.ogri.strongbox`, the `strongbox-pkgbuild` mirror): pushurl is https. Remote stages authenticate with `GITHUB_TOKEN` through `gh auth git-credential`. This removes the GitHub ssh key from the design.
- **AUR:** pushurl is `ssh://aur@aur.archlinux.org/strongbox.git`. Only the AUR stage mounts `~/.ssh/aur` read-only, with `IdentitiesOnly=yes` and `StrictHostKeyChecking=yes` against the committed `known_hosts`.

The token is read from `.github-token` on the host by the orchestrator and passed with `--env GITHUB_TOKEN` to remote GitHub stages only. That file is already git-ignored. This also fixes the current mismatch between `~/.github-token` and `./.github-token`. The token is a classic token with no expiry. Its `repo` scope covers every repository the account can write to, including `flathub/la.ogri.strongbox`, so one token serves every GitHub remote. The host's own `gh` login (`~/.config/gh/`) is never mounted into containers.

A token with no expiry can still be revoked. GitHub revoked the previous release token on 2026-09-07 as "stale", five months after its last use for 7.7.0. Releases are months apart, so the token's validity is checked live at the start of `prep` and `publish`, never assumed. A `token-check` stage in `sb-publish` calls `GET /user` and reads the `x-oauth-scopes` response header. It then calls `GET /repos/<owner>/<repo>` for each target and reads `permissions.push`. The check fails with the cause and the remedy before any other stage runs. An expiry-date warning was considered and rejected, because it would not have caught this revocation.

- *Alternative: ssh agent forwarding.* Rejected for now. No agent runs in the current session, and the agent socket would expose every loaded key to the stage, not just the needed one.
- *Alternative: keep the GitHub ssh key.* Rejected because the token is needed anyway (`gh release`, `gh pr`), so the key would be a second GitHub credential that adds nothing.

`known_hosts` is committed with the AUR's host keys, verified against the fingerprints published on aur.archlinux.org. GitHub needs no entry, because it is reached over https only. The file records the keys' source and how to refresh them.

### D6. `build` and `publish` are separate commands; `build.json` is the contract between them

```
./release.sh build <version>                     ./release.sh publish <version>
 fetch ─▶ check source ─▶ build ─▶ glibc check    verify build.json ─▶ plan ─▶ confirm
  ─▶ JRE-on-2.27 check ─▶ checksums ─▶ derive      ─▶ tag ─▶ gh release ─▶ upload
  ─▶ makepkg (offline) ─▶ appstreamcli             ─▶ strongbox-flatpak push+tag
  ─▶ write build.json                              ─▶ flathub push + PR ─▶ AUR + mirror
 [no credentials, no remote writes]               [credentials, no compilation]
```

`build.json` follows a JSON Schema committed as `schemas/build-record.schema.json`. It is validated with `python3` from the standard library: a small validator covering the subset of JSON Schema that the record uses, so no third-party package is needed. It is written once, at the end of a successful build. `publish` refuses to proceed unless the record validates and the workspace's file checksums and repository HEADs match it.

A gap between build and publish is intentional. It is where artefacts can be inspected: run the AppImage on the host, diff the derived commits.

### D7. Publish as an ordered list of idempotent operations

Each publish operation is a pair: `check` returns `done`, `pending` or `conflict` from remote state, and `apply` performs the operation. Publish first evaluates every `check` to print the plan, requires the version to be typed, and then, for each operation in order: `done` → skip, `pending` → apply then re-check, `conflict` → stop. Order and rationale are in the `release-publish` spec. Remote checks compare against `build.json`: tag commit, release asset checksums (by downloading assets, or via the GitHub API digest where available), remote branch heads, and existing PRs.

### D8. The glibc check and the JRE start check

`glibc-floor` extracts the AppImage (`--appimage-extract`, no FUSE) and unzips `*.so` from `usr/app.jar`. It runs `objdump -T` over every ELF shared object and takes the maximum `GLIBC_x.y` by version sort. The check fails above the `pins.env` ceiling, naming the worst offender. The JRE start check mounts the extracted `usr/` read-only at `/jre` in the `ubuntu:18.04` container and runs `/jre/bin/java -version`. The two checks are complementary: the first is a static bound, the second confirms the binary actually loads on the target.

### D9. Using `strongbox-appimage` unmodified

`build-appimage.sh` is called as-is. Before it runs, the build stage copies a wrapper into the clone's directory as `appimagetool`, so the script's own download branch is never taken. Its download URL now returns 404 anyway: upstream renamed AppImageKit release 13's asset to `obsolete-appimagetool-x86_64.AppImage`. The wrapper runs appimagetool 1.9.1, extracted in the image so no FUSE is needed, with `--runtime-file` set to the pinned type2 runtime. Without that flag, appimagetool downloads an unpinned runtime. The runtime is `static-pie`, so it adds no glibc requirement, and it needs only a `fusermount` binary on the user's system rather than `libfuse2`. The AUR package's `depends=("fuse2")` provides that binary, so the package needs no change. The script's `wget` of `full-catalogue.json` remains a deliberate moving input. Its SHA-256 is recorded in `build.json`.

### D10. AUR local build

In `archlinux:base-devel`, as the host user and with `--network none`, the stage runs `makepkg --printsrcinfo > .SRCINFO`. It then copies the local AppImage into the package directory under the file name `source=()` expects, and runs `makepkg --nodeps --noconfirm`. `makepkg` uses an existing source file when its checksum verifies, so no download is attempted. This was verified with the 7.7.0 package (task 1.2): the build succeeds offline, and a wrong checksum fails with exit code 1. The built package is discarded; only its success matters. `makepkg -s` is not used, so no `sudo` or package installation is needed in the container.

### D11. Tests

- **Unit tests** (`unittest`, standard library): `generate-metainfo.py`, `generate-flathub.py`, the build-record validator, version comparison (including double-digit majors, a current bug in `prep.sh`), and glibc-version maximum selection. They use `given` / `expected` / `actual` naming, and can run on the host or in `sb-publish`.
- **Property test:** for the version comparison and glibc maximum, generate random version triples or lists, and check the results against an independent reference ordering of integer tuples.
- **Integration tests**, all of which change nothing remote:
  - `tests/integration-build.sh` runs `./release.sh build` for the last released version (`7.7.0`) with no credentials available. It asserts that the record validates, the checksums agree, and every ref on every remote is unchanged.
  - `tests/integration-prep.sh` runs `./prep.sh` for a major version without a terminal. It asserts the versioned file edits, including the `SECURITY.md` rows, and that no branch reaches GitHub.
  - `tests/integration-publish.sh` runs the tag and flatpak operations of `stages/publish.sh` against local bare repositories. It covers pending to done, skipping on a rerun, and conflicts on a moved branch or tag. The GitHub API operations (release, assets, Flathub PR) are exercised by the first real release.

## Risks / Trade-offs

- [A future Temurin 17 build raises its glibc baseline] → The glibc check fails the build before anything ships. Pin the last passing version, or switch vendor.
- [`archlinux:base-devel` is rolling, so pinning by digest freezes it] → Accepted. It only produces `.SRCINFO` and a throwaway local package, and neither depends on Arch package versions in any user-visible way. Refresh the digest occasionally.
- [The token is revoked or loses the `repo` scope between releases] → This has already happened once (see D5). The token check runs first in `prep` and `publish`, so a bad token fails before any work, not partway through.
- [Changed asset checksum detection] → The GitHub API may not expose asset digests. → Fall back to downloading the asset in the check. AppImage size (about 50 MB) makes this acceptable.
- [`full-catalogue.json` makes builds non-reproducible] → Accepted and recorded (see Non-Goals).
- [The AUR mirror push needs the GitHub token in the AUR stage] → Accepted. The stage still receives exactly the two credentials it needs.
- [`apt` packages in the images are not pinned] → Accepted. Base images are pinned by digest, and each image is built once and reused until a pin changes. A rebuild picks up the distribution's current security updates. Everything that shapes the artefacts (JDK, appimagetool, runtime, lein) is pinned by checksum.
- [Upstream re-uploads a pinned release asset] → appimagetool 1.9.1's asset reports a later build than its release date. Checksum pinning turns this into an image build failure rather than a silent change.
- [Docker daemon runs as root on the host] → Containers run as the host user. Rootless docker or podman would remove the residual risk, but is not required.

## Migration Plan

1. Validate with an integration-test `build` of `7.7.0`.
2. Remove the VM scripts (`Vagrantfile`, `bootstrap.sh`, `artefacts.sh`, `archbits.sh`, `flatpakbits.sh`, `post.sh`, the root `Dockerfile`) on the same branch. Once `prep.sh` and `release.sh` are replaced, they no longer form a working pipeline, so keeping them gives no fallback. The VM pipeline stays available on `master` and in history.
3. Outside this change, as follow-ups:
   - Release 7.8.0 with `build`, inspection, then `publish`. It is the first run of the GitHub API operations.
   - After that release, delete the local VM state, which cannot be recovered: the VirtualBox VM, `.vagrant/`, and the git-ignored root binaries and clones (`gh`, `parse-changelog`, `appimagetool`, `semver2.sh`, `strongbox/`, `strongbox-appimage/`, `release/`). Then remove their `.gitignore` entries.
4. Rollback is `git revert` of the removal commit, or releasing from `master`. Re-provisioning the VM is subject to the existing host-key problem and to kernel-module version drift.

## Open Questions

- Is the `ogri-la/strongbox-pkgbuild` GitHub mirror still wanted? Keeping or dropping it changes only one publish operation.
