import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import release  # noqa: E402

SCRIPT_DIR = os.path.join(os.path.dirname(__file__), "..")


def random_version(rng):
    return tuple(rng.randint(0, 120) for _ in range(3))


class TestVersions(unittest.TestCase):
    def test_parse_version(self):
        given = "7.10.0"
        expected = (7, 10, 0)
        actual = release.parse_version(given)
        self.assertEqual(expected, actual)

    def test_parse_version_malformed(self):
        for given in ["7.8", "7.8.0.1", "v7.8.0", "7.8.x", "", "7..0"]:
            with self.assertRaises(release.VersionError, msg=given):
                release.parse_version(given)

    def test_latest_release_ignores_other_tags(self):
        given = ["1.0.0", "7.7.0", "7.10.0", "debug-build", "7.11.0-rc1", "v9.0.0"]
        expected = (7, 10, 0)
        actual = release.latest_release(given)
        self.assertEqual(expected, actual)

    def test_latest_release_none(self):
        self.assertIsNone(release.latest_release(["debug"]))

    def test_check_new_version_minor(self):
        given = ("7.8.0", ["7.6.0", "7.7.0"])
        expected = {"last": "7.7.0", "major": False}
        actual = release.check_new_version(*given)
        self.assertEqual(expected, actual)

    def test_check_new_version_double_digit_major(self):
        "the previous `prep.sh` compared only the first character, so '10.0.0' looked like '1'"
        given = ("10.0.0", ["9.4.0"])
        expected = {"last": "9.4.0", "major": True}
        actual = release.check_new_version(*given)
        self.assertEqual(expected, actual)

    def test_check_new_version_lower(self):
        with self.assertRaisesRegex(release.VersionError, "less than"):
            release.check_new_version("7.6.0", ["7.7.0"])

    def test_check_new_version_equal(self):
        with self.assertRaisesRegex(release.VersionError, "equal to"):
            release.check_new_version("7.7.0", ["7.7.0"])

    def test_check_new_version_matches_tuple_ordering(self):
        "property: acceptance agrees with integer tuple ordering, and 'major' with the first component"
        rng = random.Random(1)
        for _ in range(2000):
            tags = [random_version(rng) for _ in range(rng.randint(1, 6))]
            given = random_version(rng)
            last = max(tags)
            try:
                actual = release.check_new_version(release.format_version(given), [release.format_version(t) for t in tags])
            except release.VersionError:
                self.assertLessEqual(given, last)
                continue
            self.assertGreater(given, last)
            self.assertEqual(given[0] > last[0], actual["major"])


OBJDUMP_SAMPLE = """
/tmp/jre/lib/libnio.so:     file format elf64-x86-64

DYNAMIC SYMBOL TABLE:
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.2.5) free
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.9)  pipe2
0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.3.4) __sprintf_chk
"""


class TestGlibc(unittest.TestCase):
    def test_max_glibc_orders_numerically(self):
        "'2.9' must be below '2.10' and '2.3.4' below '2.9'"
        given = OBJDUMP_SAMPLE + "  (GLIBC_2.10) foo\n"
        expected = (2, 10)
        actual = release.max_glibc(given)
        self.assertEqual(expected, actual)

    def test_max_glibc_none(self):
        self.assertIsNone(release.max_glibc("no versioned symbols here"))

    def test_glibc_floor_names_worst_file(self):
        given = {"a.so": "(GLIBC_2.4)", "b.so": "(GLIBC_2.17)", "static": "nothing"}
        expected = ((2, 17), "b.so")
        actual = release.glibc_floor(given)
        self.assertEqual(expected, actual)

    def test_split_objdump_sections(self):
        given = "== /x/a.so\n(GLIBC_2.4)\n== /x/b.so\n(GLIBC_2.17)\n"
        expected = {"/x/a.so": "(GLIBC_2.4)\n", "/x/b.so": "(GLIBC_2.17)\n"}
        actual = release.split_objdump_sections(given)
        self.assertEqual(expected, actual)

    def test_max_glibc_matches_tuple_ordering(self):
        "property: the maximum agrees with the maximum of integer tuples"
        rng = random.Random(2)
        for _ in range(2000):
            versions = [tuple(rng.randint(0, 40) for _ in range(rng.randint(2, 3))) for _ in range(rng.randint(1, 8))]
            given = "\n".join("(GLIBC_%s) sym" % ".".join(map(str, v)) for v in versions)
            expected = max(versions)
            actual = release.max_glibc(given)
            self.assertEqual(expected, actual)


def valid_record():
    commit = "a" * 40
    sha = "b" * 64
    image = "ubuntu:24.04@sha256:" + "c" * 64
    return {
        "schema": 1,
        "version": "7.8.0",
        "sources": {"strongbox": commit, "release-script": {"commit": commit, "dirty": False}},
        "images": {"temurin": image, "ubuntu": image, "glibc-ceiling": image, "arch": image, "flatpak-lint": image,
                   "sb-build": "sha256:" + "d" * 64, "sb-publish": "sha256:" + "e" * 64},
        "jdk": "17.0.20.1+1",
        "catalogue_sha256": sha,
        "glibc": {"floor": "2.15", "worst": "libdecora_sse.so", "ceiling": "2.27"},
        "artefacts": {"strongbox-7.8.0-standalone.jar": sha, "strongbox-7.8.0-standalone.jar.sha256": sha,
                      "strongbox-7.8.0-x86_64.AppImage": sha, "strongbox-7.8.0-x86_64.AppImage.sha256": sha},
        "derived": {"flathub": commit, "aur": commit},
    }


class TestBuildRecord(unittest.TestCase):
    schema = release.load_schema(SCRIPT_DIR)

    def test_valid_record(self):
        given = valid_record()
        expected = []
        actual = release.validate(given, self.schema)
        self.assertEqual(expected, actual)

    def test_schema_is_json_schema_shaped(self):
        "the committed schema parses and declares the draft it follows"
        self.assertIn("$schema", self.schema)

    def test_invalid_records(self):
        cases = [
            ("missing field", lambda r: r.pop("jdk"), "missing required property 'jdk'"),
            ("extra field", lambda r: r.update(extra=1), "unexpected property 'extra'"),
            ("short commit", lambda r: r["derived"].update(aur="abc"), "$.derived.aur"),
            ("tag-only image", lambda r: r["images"].update(arch="archlinux:base-devel"), "$.images.arch"),
            ("bad version", lambda r: r.update(version="7.8"), "$.version"),
            ("too few artefacts", lambda r: r["artefacts"].pop("strongbox-7.8.0-x86_64.AppImage"), "fewer than 4"),
            ("wrong type", lambda r: r.update(schema="1"), "expected integer"),
            ("dirty as text", lambda r: r["sources"]["release-script"].update(dirty="false"), "expected boolean"),
            ("retired repository", lambda r: r["derived"].update({"strongbox-flatpak": "a" * 40}), "unexpected property 'strongbox-flatpak'"),
        ]
        for name, mutate, expected in cases:
            given = valid_record()
            mutate(given)
            actual = release.validate(given, self.schema)
            self.assertTrue(any(expected in error for error in actual), "%s: %r" % (name, actual))

    def test_record_mismatches(self):
        given = valid_record()
        artefacts = dict(given["artefacts"])
        artefacts["strongbox-7.8.0-x86_64.AppImage"] = "f" * 64
        heads = dict(given["derived"])
        del heads["aur"]
        actual = release.record_mismatches(given, artefacts, heads)
        self.assertEqual(2, len(actual))
        self.assertTrue(actual[0].startswith("artefact strongbox-7.8.0-x86_64.AppImage"))
        self.assertTrue(actual[1].startswith("repository aur"))

    def test_build_record_from_state_validates(self):
        "integration: state files written by the stages assemble into a valid record"
        given = valid_record()
        state = {
            "strongbox.commit": "a" * 40, "release-script.commit": "a" * 40, "release-script.dirty": "false",
            "image.temurin": given["images"]["temurin"], "image.ubuntu": given["images"]["ubuntu"],
            "image.glibc-ceiling": given["images"]["glibc-ceiling"], "image.arch": given["images"]["arch"],
            "image.flatpak-lint": given["images"]["flatpak-lint"],
            "image.sb-build": given["images"]["sb-build"], "image.sb-publish": given["images"]["sb-publish"],
            "jdk.version": "17.0.20.1+1", "catalogue.sha256": "b" * 64,
            "glibc.floor": "2.15", "glibc.worst": "libdecora_sse.so", "glibc.ceiling": "2.27",
            "flathub.commit": "a" * 40, "aur.commit": "a" * 40,
        }
        with tempfile.TemporaryDirectory() as tmp:
            for key, value in state.items():
                with open(os.path.join(tmp, key), "w") as fh:
                    fh.write(value + "\n")
            actual = release.build_record("7.8.0", release.read_state(tmp), given["artefacts"])
        self.assertEqual(given, actual)
        self.assertEqual([], release.validate(actual, self.schema))


if __name__ == "__main__":
    unittest.main()
