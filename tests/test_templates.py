"""The committed templates against the files published for 7.7.0, captured in `tests/fixtures/7.7.0`."""

import os
import sys
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "lib"))
import render  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "7.7.0")


def fixture(path):
    with open(os.path.join(FIXTURES, path), "rb") as fh:
        return fh.read()


def render_7_7_0():
    "renders the full plan with the values published for 7.7.0"
    plan = render.load_plan(ROOT)
    context = {
        "version": "7.7.0",
        "strongbox_commit": "7de669aa8000059a4ebafa6c6b441144e817c007",
        "release_notes": fixture("aur/changelog").decode().rstrip("\n"),
        "metainfo_releases": "    <releases/>",
        "sha256_jar": "498d9ff11f63022f8a2b54e309e283799c744574b42fd17aa229c34c648dcc8f",
        "sha256_appimage": "1dff6a53e2d01cf19231b7e6f82479349f818b84c8a6abda7f6587df2a2e55c8",
    }
    copies = {"strongbox:resources/strongbox.svg": b"<svg/>"}
    return render.render_plan(plan, render.load_templates(ROOT, plan), copies, context)


class TestTemplates(unittest.TestCase):
    def test_aur_files_reproduced(self):
        "the AUR files rendered for 7.7.0 are byte-identical to those published"
        outputs, _ = render_7_7_0()
        for name in ["PKGBUILD", "changelog", "strongbox.desktop", ".gitignore"]:
            with self.subTest(name=name):
                self.assertEqual(fixture("aur/" + name), outputs["aur/" + name])

    def test_manifest_differs_only_in_metadata_sources(self):
        "the rendered manifest differs from Flathub's only in the three metadata urls and checksums"
        outputs, _ = render_7_7_0()
        differences = render.compare_trees({"m": fixture("flathub/la.ogri.strongbox.yml")},
                                           {"m": outputs["flathub/la.ogri.strongbox.yml"]})
        self.assertEqual(1, len(differences))
        changed = [line for line in differences[0][2].splitlines()
                   if line[:1] in "+-" and not line.startswith(("+++", "---"))]
        self.assertEqual(12, len(changed), changed)
        for line in changed:
            self.assertRegex(line, r"^[+-] +(url: https://raw\.githubusercontent\.com/ogri-la/strongbox-(flatpak|release-script)/7\.7\.0/|sha256: [0-9a-f]{64}$)")
        for line in changed:
            if line.startswith("+") and "url:" in line:
                self.assertIn("/strongbox-release-script/7.7.0/dist/flatpak/", line)

    def test_desktop_files_per_target(self):
        outputs, _ = render_7_7_0()
        self.assertIn(b"\nExec=AppRun\n", outputs["appimage/strongbox.desktop"])
        self.assertIn(b"\nIcon=strongbox\n", outputs["appimage/strongbox.desktop"])
        self.assertIn(b"\nExec=\n", outputs["flatpak/strongbox.desktop"])
        self.assertIn(b"\nIcon=la.ogri.strongbox\n", outputs["flatpak/strongbox.desktop"])
        for output in ["aur/strongbox.desktop", "flatpak/strongbox.desktop", "appimage/strongbox.desktop"]:
            self.assertIn(b"elvui;tukui;", outputs[output])

    def test_metainfo_screenshots_at_strongbox_commit(self):
        "screenshots are referenced at the strongbox commit, which exists before the release tag is pushed"
        outputs, _ = render_7_7_0()
        metainfo = outputs["flatpak/metainfo.xml"].decode()
        self.assertEqual(6, metainfo.count("https://raw.githubusercontent.com/ogri-la/strongbox/7de669aa8000059a4ebafa6c6b441144e817c007/screenshots/screenshot-7.0.0-"))
        self.assertIn('<developer id="la.ogri">', metainfo)
        self.assertNotIn("developer_name", metainfo)

    def test_every_output_named_in_spec(self):
        "the outputs are the files the release-build spec lists, and nothing else"
        outputs, _ = render_7_7_0()
        expected = {
            "aur/PKGBUILD", "aur/changelog", "aur/strongbox.desktop", "aur/.gitignore",
            "flathub/la.ogri.strongbox.yml",
            "flatpak/metainfo.xml", "flatpak/strongbox.desktop", "flatpak/strongbox.svg",
            "appimage/strongbox.desktop", "release-notes.md",
        }
        self.assertEqual(expected, set(outputs))


if __name__ == "__main__":
    unittest.main()
