import os
import random
import string
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import render  # noqa: E402


def random_name(rng):
    return rng.choice(string.ascii_lowercase) + "".join(rng.choice(string.ascii_lowercase + string.digits + "_") for _ in range(rng.randint(0, 8)))


class TestRender(unittest.TestCase):
    def test_render(self):
        given = ("pkgver={{ version }}\nsource=(\"$pkgname-${pkgver}\")\nsha256={{sha256_appimage}}\n",
                 {"version": "7.8.0", "sha256_appimage": "abc"})
        expected = "pkgver=7.8.0\nsource=(\"$pkgname-${pkgver}\")\nsha256=abc\n"
        actual = render.render(*given)
        self.assertEqual(expected, actual)

    def test_single_braces_and_bash_untouched(self):
        "YAML and bash syntax are not placeholders"
        given = 'a: {b: c}\nx="${pkgname}"\ny={notaname}\n'
        self.assertEqual(set(), render.placeholders(given))
        self.assertEqual(given, render.render(given, {}))

    def test_unknown_name(self):
        with self.assertRaisesRegex(render.RenderError, "jar_sha512"):
            render.render("{{ jar_sha512 }}", {"version": "7.8.0"}, "flathub/la.ogri.strongbox.yml")

    def test_hash_name(self):
        self.assertEqual("sha256_flatpak_metainfo_xml", render.hash_name("flatpak/metainfo.xml"))
        self.assertEqual("sha256_aur_strongbox_desktop", render.hash_name("aur/strongbox.desktop"))

    def test_no_placeholder_left(self):
        "property: rendering a context drawn from a template's own names leaves no placeholder"
        rng = random.Random(3)
        for _ in range(1000):
            names = {random_name(rng) for _ in range(rng.randint(1, 6))}
            template = "".join(rng.choice(["{{ %s }}" % n, "{{%s}}" % n, " text ${x} {y} "]) for n in sorted(names) for _ in range(2))
            context = {n: "".join(rng.choice(string.printable) for _ in range(rng.randint(0, 12))).replace("{", "") for n in render.placeholders(template)}
            actual = render.render(template, context)
            self.assertNotIn("{{", actual)


PLAN = {
    "phases": [
        {"entries": [
            {"template": "desktop", "output": "aur/strongbox.desktop", "overlay": {"exec": "strongbox"}},
            {"template": "desktop", "output": "flatpak/strongbox.desktop", "overlay": {"exec": ""}},
            {"copy": "strongbox:resources/strongbox.svg", "output": "flatpak/strongbox.svg"},
        ]},
        {"hashes": ["aur/strongbox.desktop", "flatpak/strongbox.svg"], "entries": [
            {"template": "pkgbuild", "output": "aur/PKGBUILD"},
            {"template": "manifest", "output": "flathub/la.ogri.strongbox.yml"},
        ]},
    ]
}
TEMPLATES = {
    "desktop": "Exec={{ exec }}\nKeywords={{ keywords }}\n",
    "pkgbuild": "pkgver={{ version }}\ndesktop={{ sha256_aur_strongbox_desktop }}\n",
    "manifest": "url: x/{{ version }}/strongbox.svg\nsha256: {{ sha256_flatpak_strongbox_svg }}\n",
}
COPIES = {"strongbox:resources/strongbox.svg": b"<svg/>"}


class TestRenderPlan(unittest.TestCase):
    def test_render_plan(self):
        given = {"version": "7.8.0", "keywords": "wow;"}
        outputs, context = render.render_plan(PLAN, TEMPLATES, COPIES, given)
        self.assertEqual(b"Exec=strongbox\nKeywords=wow;\n", outputs["aur/strongbox.desktop"])
        self.assertEqual(b"Exec=\nKeywords=wow;\n", outputs["flatpak/strongbox.desktop"])
        self.assertEqual(b"<svg/>", outputs["flatpak/strongbox.svg"])
        expected_pkgbuild = "pkgver=7.8.0\ndesktop=%s\n" % render.sha256(b"Exec=strongbox\nKeywords=wow;\n")
        self.assertEqual(expected_pkgbuild.encode(), outputs["aur/PKGBUILD"])
        self.assertIn(render.sha256(b"<svg/>").encode(), outputs["flathub/la.ogri.strongbox.yml"])
        self.assertEqual(render.sha256(b"<svg/>"), context["sha256_flatpak_strongbox_svg"])

    def test_overlay_scoped_to_its_entry(self):
        "an overlay name is not visible to other entries, so a template using it elsewhere fails"
        plan = {"phases": [{"entries": [
            {"template": "desktop", "output": "a", "overlay": {"exec": "x"}},
            {"template": "desktop", "output": "b"},
        ]}]}
        with self.assertRaisesRegex(render.RenderError, "exec"):
            render.render_plan(plan, TEMPLATES, COPIES, {"keywords": "k"})

    def test_unused_context_name(self):
        given = {"version": "7.8.0", "keywords": "wow;", "release_date": "2026-10-04"}
        with self.assertRaisesRegex(render.RenderError, "release_date"):
            render.render_plan(PLAN, TEMPLATES, COPIES, given)

    def test_partial_render_skips_unused_check(self):
        "a name used only by a later phase is not unused when only the first phase is rendered"
        given = {"version": "7.8.0", "keywords": "wow;"}
        first_phase = {"phases": PLAN["phases"][:1]}
        with self.assertRaisesRegex(render.RenderError, "version"):
            render.render_plan(first_phase, TEMPLATES, COPIES, given)
        outputs, _ = render.render_plan(first_phase, TEMPLATES, COPIES, given, check_unused=False)
        self.assertEqual({"aur/strongbox.desktop", "flatpak/strongbox.desktop", "flatpak/strongbox.svg"}, set(outputs))

    def test_unused_overlay_name(self):
        plan = {"phases": [{"entries": [{"template": "desktop", "output": "a", "overlay": {"exec": "x", "icon": "y"}}]}]}
        with self.assertRaisesRegex(render.RenderError, "icon"):
            render.render_plan(plan, TEMPLATES, COPIES, {"keywords": "k"})

    def test_unused_hash(self):
        "a hash added for an output that no template refers to is an unused name"
        plan = {"phases": [PLAN["phases"][0], {"hashes": ["flatpak/strongbox.desktop"], "entries": []}]}
        with self.assertRaisesRegex(render.RenderError, "sha256_flatpak_strongbox_desktop"):
            render.render_plan(plan, TEMPLATES, COPIES, {"keywords": "k"})

    def test_output_rendered_twice(self):
        plan = {"phases": [{"entries": [{"copy": "strongbox:resources/strongbox.svg", "output": "a"}]},
                           {"entries": [{"copy": "strongbox:resources/strongbox.svg", "output": "a"}]}]}
        with self.assertRaisesRegex(render.RenderError, "twice"):
            render.render_plan(plan, TEMPLATES, COPIES, {})

    def test_render_is_pure(self):
        "rendering twice gives identical outputs, which re-rendering earlier phases depends on"
        given = {"version": "7.8.0", "keywords": "wow;"}
        self.assertEqual(render.render_plan(PLAN, TEMPLATES, COPIES, given), render.render_plan(PLAN, TEMPLATES, COPIES, given))


class TestCompareTrees(unittest.TestCase):
    def test_equal(self):
        given = {"PKGBUILD": b"a", "changelog": b"b"}
        self.assertEqual([], render.compare_trees(given, dict(given)))

    def test_changed(self):
        expected = {"la.ogri.strongbox.yml": b"runtime-version: '24.08'\n"}
        actual = {"la.ogri.strongbox.yml": b"runtime-version: '25.08'\n"}
        differences = render.compare_trees(expected, actual)
        self.assertEqual(1, len(differences))
        path, kind, diff = differences[0]
        self.assertEqual(("la.ogri.strongbox.yml", "changed"), (path, kind))
        self.assertIn("-runtime-version: '24.08'", diff)
        self.assertIn("+runtime-version: '25.08'", diff)

    def test_missing_and_unexpected(self):
        expected = {"PKGBUILD": b"a", "strongbox.desktop": b"d"}
        actual = {"PKGBUILD": b"a", "README.md": b"r"}
        expected_differences = [("README.md", "unexpected", ""), ("strongbox.desktop", "missing", "")]
        self.assertEqual(expected_differences, render.compare_trees(expected, actual))

    def test_compare_matches_set_semantics(self):
        "property: differences are exactly the symmetric difference of paths plus paths whose bytes differ"
        rng = random.Random(4)
        for _ in range(500):
            paths = ["f%d" % i for i in range(8)]
            expected = {p: bytes([rng.randint(0, 2)]) for p in paths if rng.random() < 0.7}
            actual = {p: bytes([rng.randint(0, 2)]) for p in paths if rng.random() < 0.7}
            differing = {p for p in set(expected) | set(actual) if expected.get(p) != actual.get(p)}
            self.assertEqual(differing, {path for path, _, _ in render.compare_trees(expected, actual)})


# shape of `parse-changelog --json` output
CHANGELOG = {
    "7.8.0": {
        "title": "7.8.0 - 2026-10-04",
        "notes": "### Added\n\n* a thing\n    - a sub-item, dropped\n* another thing\n\n### Fixed\n\n* issue #1 \"a bug\"\n",
    },
    "1.0.0": {"title": "1.0.0 - 2019-01-01", "notes": "### Initial release\n"},
}


class TestContext(unittest.TestCase):
    def test_group_by(self):
        given = ["# a", "1", "    sub", "", "# b", "2"]
        expected = [[], ["# a", "1"], ["# b", "2"]]
        actual = render.group_by(lambda row: row.startswith("#"), given)
        self.assertEqual(expected, actual)

    def test_metainfo_releases(self):
        actual = render.metainfo_releases(CHANGELOG)
        self.assertTrue(actual.startswith("    <releases>\n"))
        self.assertTrue(actual.endswith("    </releases>"))
        self.assertIn('<release version="7.8.0" date="2026-10-04">', actual)
        self.assertIn("<p>Added</p>", actual)
        self.assertIn("<li>a thing</li>", actual)
        self.assertIn("<li>issue #1 \"a bug\"</li>", actual)
        self.assertNotIn("sub-item", actual)
        # a section without items, as in 1.0.0, has no body
        self.assertNotIn("Initial release", actual)
        self.assertIn('<release version="1.0.0" date="2019-01-01">', actual)

    def test_metadata_context(self):
        given = ("7.8.0", "a" * 40, "### Added\n\n* a thing\n\n", CHANGELOG)
        actual = render.metadata_context(*given)
        self.assertEqual({"version", "strongbox_commit", "release_notes", "metainfo_releases"}, set(actual))
        self.assertEqual("### Added\n\n* a thing", actual["release_notes"])

    def test_packages_context(self):
        given = ({"version": "7.8.0"}, "a" * 64, "b" * 64)
        expected = {"version": "7.8.0", "sha256_jar": "a" * 64, "sha256_appimage": "b" * 64}
        self.assertEqual(expected, render.packages_context(*given))


if __name__ == "__main__":
    unittest.main()
