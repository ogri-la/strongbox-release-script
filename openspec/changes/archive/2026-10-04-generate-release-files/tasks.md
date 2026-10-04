## 1. Verify assumptions

- [x] 1.1 Confirm against Flathub's current requirements that an app repository may carry `metainfo.xml`, a desktop file and an icon as local `path:` sources (D3). It may not, so D3 now hosts them in `dist/flatpak/` at this repository's tag.
- [x] 1.2 Pin `ghcr.io/flathub-infra/flatpak-builder-lint` by digest in `pins.env`. Confirm that `--exceptions manifest` passes on Flathub's current manifest and that `appstream` reports `developer-info-missing` on the 7.7.0 metainfo.

## 2. Renderer and pure helpers

- [x] 2.1 `lib/render.py`: render a template with `{{ name }}` placeholders from a context, failing on unknown names. Render a plan of `{template, output, overlay}` entries into `{path: bytes}`, failing on context names no entry uses.
- [x] 2.2 Unit and property tests for the renderer: replacement, unknown and unused names, overlays scoped to their target, no `{{` left after rendering any context drawn from a template's own names.
- [x] 2.3 File-set comparison, `{path: bytes} × {path: bytes} → [difference]`, with a unified diff per changed file. Unit tests for equal, changed, added and removed files.
- [x] 2.4 Build record schema: replace the `strongbox-appimage` source with this repository's commit and its dirty flag, and drop `strongbox-flatpak` from `derived`. Update the validator tests.

## 3. Templates

- [x] 3.1 `templates/strongbox.desktop`: one desktop file with `{{ desktop_exec }}` and `{{ desktop_icon }}`, replacing the three copies. Keywords include `elvui` and `tukui` (D2).
- [x] 3.2 `templates/aur/PKGBUILD` and `templates/aur/.gitignore`, from the AUR's 7.7.0 files.
- [x] 3.3 `templates/flathub/la.ogri.strongbox.yml`, from Flathub `master`: runtime 25.08 and PR #16's style, the jar from the strongbox release, and `metainfo.xml`, `strongbox.desktop` and `strongbox.svg` from `dist/flatpak/` at this repository's tag, each with its sha256.
- [x] 3.4 `templates/flatpak/metainfo.xml`, from `metainfo.xml.template`, with the `developer` element and screenshot URLs at the strongbox release tag.
- [x] 3.5 The render plan and context: phase 1 (desktop files, `metainfo.xml`, `strongbox.svg`, release notes) and phase 2 (`PKGBUILD` and the manifest, which need artefact and phase-1 checksums), declared as data in one place.
- [x] 3.6 Fixture tests. The 7.7.0 context renders the AUR `PKGBUILD` and `changelog` exactly as published. The rendered manifest differs from Flathub `master` only in the three metadata URLs and their checksums.

## 4. AppImage scripts

- [x] 4.1 Move `build-appimage.sh` and `AppRun` from `strongbox-appimage` into `appimage/`. Remove the script's appimagetool download, and take its desktop file from the phase-1 render.
- [x] 4.2 The build stage runs `appimage/build-appimage.sh` from this repository. Record this repository's commit and dirty flag instead of `strongbox-appimage`'s commit.

## 5. Build pipeline

- [x] 5.1 Fetch stage: stop cloning `strongbox-appimage` and `strongbox-flatpak`.
- [x] 5.2 Drift stage: compare each downstream clone with `dist/<target>` at `HEAD`, and fail with the diffs and the `adopt` instruction. Add `./release.sh adopt <target>`, which copies a fresh downstream clone's files into `dist/<target>` and changes nothing remote.
- [x] 5.3 Render stages: phase 1 before the build stage, phase 2 after checksums, both into `work/<version>/dist`.
- [x] 5.4 Lint stage: `flatpak-builder-lint --exceptions manifest` and `appstream`, then `appstreamcli validate`. Fail on errors, print warnings.
- [x] 5.5 AUR stage: `.SRCINFO` and the offline `makepkg` run on `work/<version>/dist/aur`, and `.SRCINFO` is written back there.
- [x] 5.6 Copy each target's rendered files into its downstream clone, removing files absent from `dist/`, and commit.
- [x] 5.7 Write `build.json`, then replace `dist/` with `work/<version>/dist` as the last step.
- [x] 5.8 Remove `generate-flathub.py`, `generate-metainfo.py`, `la.ogri.strongbox.yml.template`, `metainfo.xml.template`, `stages/release-derive.sh`'s editing of clones, and `tests/test_generators.py`.

## 6. Publish

- [x] 6.1 Preconditions before any remote contact: on the default branch, no changes outside `dist/`, `dist/build.json` valid, artefacts and clones matching it and `dist/`.
- [x] 6.2 `record` operation: commit `dist/` as `release <version>`, tag it, and push branch and tag over https. Check against the remote tag. Make the push URL overridable by environment variable.
- [x] 6.3 Remove the `flatpak` operation and the `strongbox-pkgbuild` mirror push. Change the token check to `ogri-la/strongbox`, `ogri-la/strongbox-release-script` and `flathub/la.ogri.strongbox`.
- [x] 6.4 The `flathub` operation pushes the branch carrying `dist/flathub/la.ogri.strongbox.yml`.

## 7. Baseline and integration

- [x] 7.1 Create the baseline with `./release.sh adopt flathub` and `./release.sh adopt aur`. Commit it as the 7.7.0 baseline.
- [x] 7.2 `tests/integration-build.sh`: assert the rendered `dist/`, the drift check passing against the baseline, and `dist/` unchanged after a failed build.
- [x] 7.3 `tests/integration-publish.sh`: add the `record` operation against a local bare repository, including a rerun and a conflict.
- [x] 7.4 Check `strongbox.svg` from the `strongbox` repository against the linter and `appstreamcli`. If either objects, strip its metadata during rendering.

## 8. Documentation

- [x] 8.1 `release.md` and `README.md`: templates and `dist/`, the tag per release, drift and `adopt`, and the retired repositories.
