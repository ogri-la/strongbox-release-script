## Why

Releases run inside a Vagrant + VirtualBox VM that fails to start when it is needed (most recently because a kernel upgrade without a reboot left the loaded `vboxdrv` module at 7.2.12, while the VirtualBox userland was at 7.2.20), and that accumulates state over time: an end-of-life Ubuntu 18.04 base, a JDK frozen at 17.0.7 since 2023, a revoked GitHub host key pinned in `bootstrap.sh`, a `gh` from 2021 and private keys copied into the VM's disk. The release also creates public, hard-to-reverse effects early: `release.sh` tags and publishes a GitHub release *before* building the artefacts, so a failed build leaves a release without artefacts.

## What Changes

- Replace the VM with short-lived containers orchestrated from the host. The host needs only `bash`, coreutils and `docker`.
- Split every pipeline into local stages (fetch, edit, build, verify, derive) and remote stages (push, tag, release, upload, PR). All local stages complete and are reviewed before any remote stage runs.
- Fetch every repository over anonymous https. Mount credentials only into the stages that write to a remote, and only the credential that stage needs.
- Build the bundled JRE from a pinned, long-term supported JDK 17 distribution instead of the operating system's package. Verify the AppImage's glibc floor explicitly instead of relying on an old build OS.
- Pin every image, JDK and downloaded tool by version and checksum or digest.
- Package the AUR release in an Arch Linux container, including a local `makepkg` build against the locally built AppImage before anything is pushed.
- Make publication idempotent and resumable: a publish that fails partway can be rerun without duplicating or overwriting remote effects.
- **BREAKING**: remove `Vagrantfile`, `bootstrap.sh`, `artefacts.sh`, `archbits.sh` and `flatpakbits.sh`. `prep.sh` and `release.sh` keep their names and arguments, but become host-side orchestrators. `release.sh` gains `build` and `publish` subcommands.

## Capabilities

### New Capabilities

- `release-environment`: the container runtime contract. Covers statelessness, pinned inputs, credential isolation, the host prerequisites and the anonymous-fetch/authenticated-push split.
- `release-prep`: preparing a release branch of strongbox and opening its PR, with every edit committed and reviewable locally before the push.
- `release-build`: producing, verifying and recording release artefacts (uberjar, AppImage, checksums, AUR package, Flatpak metadata) without credentials or remote side effects.
- `release-publish`: applying a verified build to GitHub, the AUR and Flathub in a fixed order, idempotently and only after explicit confirmation.

### Modified Capabilities

None. There are no existing specs.

## Impact

- **Scripts:** `prep.sh` and `release.sh` are rewritten. `generate-metainfo.py` and `generate-flathub.py` are kept but run inside a container. `artefacts.sh`, `archbits.sh`, `flatpakbits.sh`, `bootstrap.sh`, `Vagrantfile` and the root `Dockerfile` are removed. `release.md` is rewritten for the new workflow.
- **New files:** container definitions for a build image, a publish image and an Arch image; a committed `known_hosts`; a pinned-inputs manifest.
- **Host requirements:** `docker`. VirtualBox, Vagrant and the VM are no longer used.
- **Release artefacts:** the AppImage's JRE moves from Ubuntu's `openjdk-17` 17.0.7 to a current JDK 17 patch release. The glibc floor must not rise above 2.27, today's value.
- **External repositories:** `ogri-la/strongbox-appimage` is consumed as-is; `appimagetool` is supplied pre-pinned and run without FUSE. No changes to `strongbox`, `strongbox-flatpak` or the AUR package beyond their normal per-release updates.
- **Credentials:** the GitHub token (`.github-token`) and the AUR key (`~/.ssh/aur`) are read from the host at run time, read-only. They are never copied into images or the workspace. GitHub pushes move from ssh to token-authenticated https, so the GitHub ssh key (`~/.ssh/id_rsa`) is no longer used.
