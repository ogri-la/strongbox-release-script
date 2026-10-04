## Why

Packaging files for a release are spread over five repositories, and several exist as hand-maintained copies. An edit to one copy is overwritten by the next release, then made again by hand. The history shows this repeatedly:
- the `developer` element is added and lost four times
- `--share=ipc` is added in two repositories
- five commits fix checksums
- Flathub's runtime upgrade (PR #16) would be reverted by the next release

Three different `strongbox.desktop` files have drifted apart. Flathub's checks run only after a pull request is opened, so failures are found late. No single place records what was generated and pushed for a release.

## What Changes

- This repository becomes the only source of packaging files. Templates in `templates/` are rendered once per release from one context: the version, artefact checksums, and text derived from the changelog. The rendered files are written to `dist/`, with every value written out in full. This is the same model as `makepkg` and a `PKGBUILD`.
- `dist/` is committed and this repository is tagged `<version>` when a release is published. The tag shows exactly which scripts and templates generated which files, and what was pushed.
- Repositories owned by others (`flathub/la.ogri.strongbox`, the AUR package) hold only copies of `dist/` output. Anything that cannot be derived lives in repositories we own: this one and `ogri-la/strongbox`.
- Flathub requires metadata files to come from upstream, not to be copied into its repository. So `metainfo.xml`, `strongbox.desktop` and `strongbox.svg` are rendered into `dist/flatpak/` and fetched by URL at this repository's release tag, in place of `strongbox-flatpak`'s tag. Their checksums are computed from the same committed files, so they cannot disagree. The Flathub repository holds only the rendered manifest. Screenshots are referenced at the strongbox release tag, where they already exist.
- Build detects downstream drift before generating files. Each downstream repository must match the files last pushed to it, as committed in `dist/`. A difference means someone edited the downstream copy. The build stops and shows the diff, so the edit is moved into a template instead of being overwritten. `./release.sh adopt <target>` then takes the downstream files into `dist/`.
- Build runs Flathub's own linter (`flatpak-builder-lint`) on the manifest and metainfo, so problems the Flathub buildbot would find are found locally.
- One `strongbox.desktop` template replaces the three copies, with per-target values for `Exec` and `Icon`.
- **BREAKING**: `ogri-la/strongbox-flatpak`, `ogri-la/strongbox-pkgbuild` and `ogri-la/strongbox-appimage` are no longer used. `build-appimage.sh` and `AppRun` move into this repository. The three repositories are archived, not deleted, because earlier Flathub manifests reference files in `strongbox-flatpak` by URL.
- **BREAKING**: `la.ogri.strongbox.yml.template`, `metainfo.xml.template`, `generate-flathub.py` and `generate-metainfo.py` are replaced by `templates/` and a single renderer.

## Capabilities

### New Capabilities

None. The behaviour belongs to the existing build and publish capabilities.

### Modified Capabilities

- `release-build`: per-release files are rendered from templates into `dist/` instead of being edited in place in downstream clones. New requirements cover rendering, downstream drift detection and Flathub linting. The build record moves into `dist/` and records this repository's commit instead of `strongbox-appimage`'s.
- `release-publish`: publish commits `dist/` and tags this repository first. The `strongbox-flatpak` operation and the `strongbox-pkgbuild` mirror push are removed. Publish requires this repository to be on its default branch, with no changes outside `dist/`.
- `release-environment`: the AUR stage no longer holds the GitHub token, because the `strongbox-pkgbuild` mirror push is removed.

## Impact

- **New in this repository:** `templates/` (Flathub manifest, metainfo, desktop file, `PKGBUILD`), `appimage/` (`build-appimage.sh`, `AppRun`), `dist/` (committed per release), and a renderer in `lib/`.
- **Removed from this repository:** `la.ogri.strongbox.yml.template`, `metainfo.xml.template`, `generate-flathub.py`, `generate-metainfo.py`, and their tests (replaced by renderer tests).
- **Stages:** the fetch stage no longer clones `strongbox-flatpak` or `strongbox-appimage`. The derive stage renders templates instead of editing clones. Publish loses the `flatpak` operation and gains a `record` operation for this repository.
- **Build record schema:** gains this repository's commit and the render context, and loses `strongbox-appimage` and `strongbox-flatpak`.
- **Downstream repositories:**
  - The Flathub manifest's three metadata URLs move from `strongbox-flatpak` to this repository's tag.
  - The AUR repository's `strongbox.desktop` becomes a rendered copy.
- **GitHub:** `ogri-la/strongbox-flatpak`, `ogri-la/strongbox-pkgbuild` and `ogri-la/strongbox-appimage` are archived, by hand, after the first release under this change.
- **External:** a new pinned image, `ghcr.io/flathub-infra/flatpak-builder-lint`. Its manifest check fetches Flathub's per-app exceptions over the network.
