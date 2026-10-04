## Context

See `proposal.md` for motivation. The packaging files a release touches today, and where each one lives:

| file | lives in | maintained by |
|---|---|---|
| Flathub manifest | `la.ogri.strongbox.yml.template` here, a generated copy in `strongbox-flatpak`, a copy in `flathub/la.ogri.strongbox` | template here; Flathub contributors also edit their copy (PR #16) |
| `metainfo.xml` | `metainfo.xml.template` here, a generated copy in `strongbox-flatpak` | template here; hand edits were made to the generated copy |
| `strongbox.desktop` | `strongbox-appimage`, `strongbox-flatpak`, AUR | three hand-maintained copies, which now differ in `Exec`, `Icon` and keywords |
| `strongbox.svg` | `strongbox` repo (`resources/`), `strongbox-flatpak` | same image; the `strongbox-flatpak` copy has its Inkscape metadata removed |
| screenshots | `strongbox` repo (`screenshots/screenshot-7.0.0-*.png`), `strongbox-flatpak` | byte-identical copies |
| `PKGBUILD`, `changelog`, `.SRCINFO` | AUR, mirrored to `strongbox-pkgbuild` | edited in place by `sed` each release |
| `build-appimage.sh`, `AppRun` | `strongbox-appimage` | used from its `master` at build time, so it is not pinned by anything |

Flathub's manifest references `metainfo.xml`, `strongbox.desktop` and `strongbox.svg` by raw URL at a `strongbox-flatpak` tag, each with a sha256. Flathub's linter runs as a container image (`ghcr.io/flathub-infra/flatpak-builder-lint`). On 7.7.0 it reported `developer-info-missing` for our metainfo, and a runtime that is end-of-life.

## Goals / Non-Goals

**Goals:**
- One source for every packaging file, in repositories we own. Downstream repositories hold only rendered copies.
- One input per release: the version. Everything else is derived and written out in full.
- An edit made downstream is detected, never silently overwritten.
- Flathub's checks run before a pull request is opened.

**Non-Goals:**
- Dropping Flathub. The change reduces Flathub to one rendered directory and one publish operation, so dropping it later means removing that directory and that operation.
- Changes to the `strongbox` repository. Its icon and screenshots are used as they are.
- Building or running the Flatpak locally.
- Byte-identical, reproducible artefacts (unchanged from `containerise-release`).
- Moving to Flathub runtime 26.08. The manifest template stays at 25.08. The bump changes the libraries JavaFX renders with, and only a Flathub test build can verify it, so it is a separate, later edit. Flathub publishes `org.freedesktop.Sdk.Extension.openjdk17` for `26.08`, so nothing blocks it.
- Packaging-only updates: republishing Flathub or AUR files without a new strongbox version, such as a runtime bump or a `pkgrel` increment. Every publish is keyed to a strongbox release, and 7.8.0 is the first release under this change.

## Decisions

### D1. Templates, one context, rendered files written out in full

This is the `makepkg` model. A `PKGBUILD` is a template whose variables are filled once, and `.SRCINFO` is its rendered, fully-expanded form. Here, `templates/` holds the templates and `dist/` holds the rendered files. The render context is a map from name to string, built once per release:

```
context = { version, jar_sha256, appimage_sha256, release_date, release_notes, metainfo_releases, ... }
```

A render plan, declared as data, lists every output:

```
render plan = [ { template, output, overlay } ... ]
  overlay: per-target names, e.g. { desktop_exec: "strongbox", desktop_icon: "strongbox" } for aur
```

Rendering is a pure function from `(templates, context, plan)` to `{output path: bytes}`. It runs in two phases, because the AUR `PKGBUILD` carries the sha256 of the rendered desktop file, and the Flathub manifest carries the sha256 of each `dist/flatpak/` file:
1. Files that need no checksums: the desktop files, `metainfo.xml`, the copied `strongbox.svg` and the release notes.
2. The `PKGBUILD` and the Flathub manifest, with the checksums of phase 1's outputs and of the artefacts added to the context.

Placeholders are `{{ name }}`. `${...}` is bash syntax in the `PKGBUILD`, and `{...}` appears in YAML. A name a template uses that is missing from the context fails rendering. So does a context name that no template uses, which catches a variable that was renamed in a template but not in the context.

- *Alternative: `str.format` (as the current generators use).* Rejected because its `{}` syntax conflicts with `${pkgname}` in a `PKGBUILD`.
- *Alternative: `string.Template` (`$name`).* Rejected for the same reason.

### D2. Layout

```
templates/
  strongbox.desktop              one template, rendered three times with per-target overlays
  aur/PKGBUILD
  aur/.gitignore
  flathub/la.ogri.strongbox.yml
  flatpak/metainfo.xml
appimage/
  build-appimage.sh              moved from strongbox-appimage, its appimagetool download removed
  AppRun
dist/                            committed by publish, tagged <version>
  context.json                   the render context
  build.json                     the build record
  release-notes.md
  aur/       PKGBUILD .SRCINFO changelog strongbox.desktop .gitignore    copied to the AUR
  flathub/   la.ogri.strongbox.yml                                      copied to Flathub
  flatpak/   metainfo.xml strongbox.desktop strongbox.svg               fetched by the manifest, by URL at this tag
  appimage/  strongbox.desktop                                          built into the AppImage
```

`dist/` holds one release at a time. The previous release is its committed state, and earlier releases are its history: `git diff 7.7.0 7.8.0 -- dist/` shows exactly what changed between two releases. This is the same model as the AUR repository, which holds one `PKGBUILD` and records history in git.

The desktop template keeps the keywords `elvui` and `tukui`. strongbox still supports both, as ordinary addons that it scrapes and publishes to GitHub unofficially. The AppImage copy lacked them, and the unified template adds them there.

`strongbox.svg` is copied from `resources/strongbox.svg` in the `strongbox` clone at the release commit, so it is derived. Screenshot URLs in `metainfo.xml` point at `raw.githubusercontent.com/ogri-la/strongbox/{{ strongbox_commit }}/screenshots/screenshot-7.0.0-*.png`. These are the same images `strongbox-flatpak` holds today. They are referenced at the strongbox commit being built, not its release tag: Flathub's metainfo check requires every URL to resolve at build time, which is before `publish` creates the tag. A commit is also immutable, which a tag is not. The screenshot set (`7.0.0`) is a constant in the metainfo template, and is changed there when new screenshots are taken.

### D3. Downstream repositories hold only `dist/` copies

Flathub's requirements forbid copies of metadata files in its repository: "These metadata files must be integrated in the upstream project. Please do not include a copy in the submission pull request unless it is using an extra-data source." (checked in task 1.1).

So the Flathub repository holds only the rendered manifest. The manifest has four URL sources, each with a sha256:
- the jar, from the strongbox GitHub release
- `metainfo.xml`, `strongbox.desktop` and `strongbox.svg`, from `raw.githubusercontent.com/ogri-la/strongbox-release-script/{{ version }}/dist/flatpak/`

This replaces `strongbox-flatpak`'s tag as the host. The metadata checksums used to break because files were edited after hashing, or tags were placed by hand. Now the checksums are computed from the files committed at the same tag, by the same build, and `publish` pushes that tag first (D7). The Flathub repository has always been fetched this way, and has accepted it.

The AUR repository keeps its layout. Its files are now rendered copies, including `strongbox.desktop`.

Every file stored in a downstream repository is a copy of a file in `dist/` at a tag of this repository. So no data that cannot be derived is stored on a repository we do not own.

- *Alternative: copy the metadata into the Flathub repository as `path:` sources.* Rejected because Flathub's requirements forbid it.
- *Alternative: upload the metadata as strongbox GitHub release assets.* Rejected because it adds three packaging files to every release page and an upload step. Hosting at this repository's tag keeps them with the scripts that rendered them.
- *Alternative: move the metadata into the `strongbox` repository.* Rejected because a packaging change would then need a strongbox commit, and this repository is the generator.
- *Alternative: patch Flathub's file in place each release.* Rejected because the Flathub repository would become a source of data, which the ownership rule forbids.

### D4. Drift detection and `adopt`

After the fetch stage, a drift stage compares the file set (names and bytes, excluding `.git`) of each fresh downstream clone with `dist/<target>` as committed at this repository's `HEAD`. It uses the committed state, not the working tree, because only `publish` commits `dist/`, so `HEAD` is what was last pushed. Comparing file sets is a pure function, `{path: bytes} × {path: bytes} → [difference]`, run in `sb-publish` with this repository mounted read-only.

On a difference, build stops before rendering. It prints a unified diff per file and the next steps: move the edit into a template, run `./release.sh adopt <target>`, review `git diff dist/<target>`, and commit. `adopt` is local-only. It fetches the downstream repository and copies its files into `dist/<target>`, so the committed baseline matches the downstream repository again. The diff that `adopt` produces is the record of what the downstream contributor changed.

- *Alternative: render the current templates with the previous release's context, and compare with downstream.* Rejected because it fails as soon as a template gains a new name, which the previous context lacks.

### D5. Build pipeline

```
fetch (strongbox, flathub, aur) ─▶ drift ─▶ check source ─▶ build (appimage/ in this repo)
  ─▶ glibc floor ─▶ JRE start ─▶ checksums ─▶ render phase 1 + 2 into work/<v>/dist
  ─▶ lint (flatpak-builder-lint, appstreamcli) ─▶ .SRCINFO + offline makepkg
  ─▶ copy into downstream clones, commit ─▶ write build.json ─▶ replace dist/ with work/<v>/dist
```

Everything is rendered into `work/<version>/dist` and copied over `dist/` only by the last stage. A failed build therefore leaves `dist/` as it was. The build stage runs `/release-script/appimage/build-appimage.sh`, so the AppImage scripts are pinned by this repository's commit. That commit, and whether the working tree had changes outside `dist/`, go into `build.json`. `strongbox-appimage`'s commit is no longer recorded.

### D6. Linting

`flatpak-builder-lint` runs from `ghcr.io/flathub-infra/flatpak-builder-lint`, pinned by digest in `pins.env`. It runs as `--exceptions manifest dist/flathub/la.ogri.strongbox.yml` and `appstream dist/flatpak/metainfo.xml`. Applying exceptions fetches Flathub's per-app exception list, so the stage has network `fetch`. The linter writes a cache under `$HOME`, which the stage runner's throwaway home provides. Without exceptions, `--filesystem=host` is reported as an error, although Flathub grants this app an exception for it. For the manifest, errors fail the build and warnings, such as a newer runtime being available, are printed. For the metainfo, the linter fails on warnings and checks that every URL resolves, so that stage also has network `fetch`; Flathub's buildbot applies the same check, so the build keeps it. `appstreamcli validate` stays as well.

### D7. Publish

Preconditions, checked before any remote contact:
- This repository is on its default branch (`master`).
- Its working tree has no changes outside `dist/`.
- `dist/build.json` validates, and the artefacts and downstream clones match it and `dist/`.

The operations:

| # | operation | check | apply |
|---|---|---|---|
| 1 | `record` | remote tag `<version>` of this repository: absent → pending, at the local release commit → done, elsewhere → conflict | commit `dist/` as `release <version>`, tag it, push the default branch and the tag over https with the token |
| 2 | `tag` | unchanged | unchanged |
| 3 | `release` | unchanged | notes from `dist/release-notes.md` |
| 4 | `assets` | unchanged | unchanged |
| 5 | `flathub` | unchanged (a merged PR is done) | push the branch carrying `dist/flathub/la.ogri.strongbox.yml`, open the PR |
| 6 | `aur` | AUR `master` only | push to the AUR only |

The `flatpak` operation and the `strongbox-pkgbuild` mirror push are removed. The token check covers `ogri-la/strongbox`, `ogri-la/strongbox-release-script` and `flathub/la.ogri.strongbox`. `record` is first, so a release that fails partway still has a tag here stating what it is publishing. Its local commit is made once: on a rerun, an existing local tag at a commit whose `dist/` matches the work tree is reused.

The `record` operation pushes this repository to `https://github.com/ogri-la/strongbox-release-script`, regardless of the local `origin` URL, which is ssh. The URL can be overridden by an environment variable, so the integration test can point it at a local bare repository.

### D8. Retiring repositories

`strongbox-flatpak`, `strongbox-pkgbuild` and `strongbox-appimage` each get a README pointing here, then are archived on GitHub by hand after the first release under this change. They are archived, not deleted. Flathub's history holds manifests that reference files in `strongbox-flatpak` by raw URL, and archived repositories still serve those files.

### D9. Tests

- **Renderer** (unit and property):
  - Placeholders are replaced.
  - Unknown and unused names fail.
  - Rendering any context drawn at random from a template's own names leaves no `{{` in the output.
  - Overlays apply only to their target.
- **Drift comparison** (unit): equal sets; a changed file; an added file; a removed file. Each reports exactly that difference.
- **Templates against today's files** (unit, with fixtures): rendering the 7.7.0 context gives:
  - the AUR `PKGBUILD` and `changelog` as published for 7.7.0
  - a Flathub manifest that differs from Flathub `master` only in the three metadata URLs and their checksums
- **Integration:**
  - `tests/integration-build.sh` asserts the rendered `dist/` and the drift check.
  - `tests/integration-publish.sh` gains the `record` operation, against a local bare repository.

## Risks / Trade-offs

- [Flathub reviewers question metadata hosted in a release-script repository] → It is hosted the same way as before, by a separate `ogri-la` repository at a tag. The PR description names the new host and why.
- [The first release under this change changes the manifest's three metadata URLs] → The pull request shows three changed `url` lines and checksums. The PR description says why.
- [The linter image is a rolling `latest`, pinned by digest] → Its rules change between refreshes, so a refresh can start failing builds on new rules. Refresh deliberately, as with other pins.
- [The metadata files depend on this repository's tag existing] → Publish pushes it (`record`) before `flathub`, and the plan's conflict checks prevent a tag on another commit. Screenshots are referenced at a strongbox commit, so they exist before any tag is pushed.
- [`strongbox.svg` from the `strongbox` repository still has its Inkscape metadata] → It is well-formed, and neither the linter nor `appstreamcli` objects (task 7.4). Flathub's buildbot checks the exported icon, which cannot be checked locally. If it objects, the render step strips the metadata rather than keeping a hand-edited copy.
- [`dist/` diffs are noisy, because `metainfo.xml` lists every release] → Accepted. `git diff` shows only the new release's block and the changed checksums.

## Migration Plan

1. Write the templates so that they reproduce today's files, adopting Flathub PR #16 (runtime 25.08, style-guide formatting) and the `developer` element.
2. Create the baseline: `./release.sh adopt flathub` and `./release.sh adopt aur` copy today's downstream files into `dist/`. Commit them as the 7.7.0 baseline, untagged; tags mark published releases only.
3. The first release under this change (7.8.0) changes the Flathub layout (D3) and the unified desktop file. Its `dist/` diff against the baseline commit shows both.
4. Outside this change, after that release: add the README pointers and archive the three retired repositories.
5. Rollback is reverting this change's commits. The retired repositories are archived, not deleted, and can be unarchived.
