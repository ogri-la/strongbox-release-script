"""Pure logic for the release pipelines, with a small command-line front end.

The functions above `main` take values and return values. Only the command
functions (prefixed `cmd_`) read files, run `git` or print. Runs with the
standard library only, on the host or inside the release images.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

import render

VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
GLIBC_RE = re.compile(r"GLIBC_(\d+(?:\.\d+)*)")

# --- versions


class VersionError(ValueError):
    pass


def parse_version(given):
    "returns `major.minor.patch` as a tuple of ints, raising `VersionError` when malformed"
    match = VERSION_RE.match(given.strip())
    if not match:
        raise VersionError("malformed version %r, expected 'major.minor.patch'" % given)
    return tuple(int(part) for part in match.groups())


def format_version(version):
    return ".".join(str(part) for part in version)


def latest_release(tags):
    "returns the highest `major.minor.patch` tag as a tuple, ignoring tags of any other shape, or `None`"
    versions = [parse_version(tag) for tag in tags if VERSION_RE.match(tag.strip())]
    return max(versions, default=None)


def check_new_version(given, tags):
    """returns `{"last": str|None, "major": bool}` when `given` is strictly greater than every release tag.
    raises `VersionError` otherwise."""
    version = parse_version(given)
    last = latest_release(tags)
    if last is None:
        return {"last": None, "major": True}
    if version < last:
        raise VersionError("given release %r is less than the last release %r" % (given, format_version(last)))
    if version == last:
        raise VersionError("given release %r is equal to the last release %r" % (given, format_version(last)))
    return {"last": format_version(last), "major": version[0] > last[0]}


# --- glibc


def parse_glibc(given):
    return tuple(int(part) for part in given.split("."))


def max_glibc(objdump_text):
    "returns the highest `GLIBC_x.y` symbol version in `objdump -T` output as a tuple, or `None`"
    return max((parse_glibc(match) for match in GLIBC_RE.findall(objdump_text)), default=None)


def glibc_floor(objdump_by_file):
    """returns `(version, file)` for the highest glibc version required across a map of
    `{file: objdump -T output}`, or `(None, None)` when no file requires glibc."""
    found = [(max_glibc(text), path) for path, text in sorted(objdump_by_file.items())]
    found = [(version, path) for version, path in found if version is not None]
    return max(found, default=(None, None))


def split_objdump_sections(text):
    "splits concatenated output of the form '== <path>' followed by that file's `objdump -T` output into a map"
    sections = {}
    current = None
    for line in text.splitlines():
        if line.startswith("== "):
            current = line[3:].strip()
            sections[current] = ""
        elif current is not None:
            sections[current] += line + "\n"
    return sections


# --- schema validation
# a subset of JSON Schema: type, required, properties, additionalProperties (false only),
# pattern, enum, minLength, minProperties, items, $defs and local $ref.

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "null": type(None),
}


def _is_type(value, type_name):
    if type_name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    return isinstance(value, TYPES[type_name])


def validate(value, schema, root=None, path="$"):
    "returns a list of error strings, empty when `value` conforms to `schema`"
    root = schema if root is None else root
    if "$ref" in schema:
        name = schema["$ref"].split("/")[-1]
        return validate(value, root["$defs"][name], root, path)

    if "type" in schema and not _is_type(value, schema["type"]):
        return ["%s: expected %s, got %s" % (path, schema["type"], type(value).__name__)]

    errors = []
    if "enum" in schema and value not in schema["enum"]:
        errors.append("%s: %r is not one of %r" % (path, value, schema["enum"]))

    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append("%s: shorter than %d characters" % (path, schema["minLength"]))
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append("%s: %r does not match %r" % (path, value, schema["pattern"]))

    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            errors.append("%s: fewer than %d properties" % (path, schema["minProperties"]))
        for key in schema.get("required", []):
            if key not in value:
                errors.append("%s: missing required property %r" % (path, key))
        properties = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in sorted(value.items()):
            if key in properties:
                errors.extend(validate(item, properties[key], root, "%s.%s" % (path, key)))
            elif extra is False:
                errors.append("%s: unexpected property %r" % (path, key))
            elif isinstance(extra, dict):
                errors.extend(validate(item, extra, root, "%s.%s" % (path, key)))

    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            errors.extend(validate(item, schema["items"], root, "%s[%d]" % (path, index)))

    return errors


# --- build record


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def record_mismatches(record, actual_artefacts, actual_heads):
    """returns a list of differences between a build record and the workspace's current
    artefact checksums (`{filename: sha256}`) and derived repository heads (`{name: sha}`)"""
    problems = []
    for name, expected in sorted(record["artefacts"].items()):
        actual = actual_artefacts.get(name)
        if actual != expected:
            problems.append("artefact %s: recorded %s, found %s" % (name, expected, actual or "nothing"))
    for name, expected in sorted(record["derived"].items()):
        actual = actual_heads.get(name)
        if actual != expected:
            problems.append("repository %s: recorded HEAD %s, found %s" % (name, expected, actual or "nothing"))
    return problems


def read_state(state_dir):
    "returns `{key: value}` for each file in the stage state directory, values stripped"
    state = {}
    for name in sorted(os.listdir(state_dir)):
        with open(os.path.join(state_dir, name)) as fh:
            state[name] = fh.read().strip()
    return state


def build_record(version, state, artefacts):
    "assembles a build record from stage state and artefact checksums"
    return {
        "schema": 1,
        "version": version,
        "sources": {
            "strongbox": state["strongbox.commit"],
            "release-script": {
                "commit": state["release-script.commit"],
                "dirty": state["release-script.dirty"] == "true",
            },
        },
        "images": {
            "temurin": state["image.temurin"],
            "ubuntu": state["image.ubuntu"],
            "glibc-ceiling": state["image.glibc-ceiling"],
            "arch": state["image.arch"],
            "flatpak-lint": state["image.flatpak-lint"],
            "sb-build": state["image.sb-build"],
            "sb-publish": state["image.sb-publish"],
        },
        "jdk": state["jdk.version"],
        "catalogue_sha256": state["catalogue.sha256"],
        "glibc": {"floor": state["glibc.floor"], "worst": state["glibc.worst"], "ceiling": state["glibc.ceiling"]},
        "artefacts": artefacts,
        "derived": {
            "flathub": state["flathub.commit"],
            "aur": state["aur.commit"],
        },
    }


# --- commands


def load_schema(script_dir):
    with open(os.path.join(script_dir, "schemas", "build-record.schema.json")) as fh:
        return json.load(fh)


def git_head(repo):
    return subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()


def artefact_checksums(release_dir):
    return {name: sha256_file(os.path.join(release_dir, name)) for name in sorted(os.listdir(release_dir))}


def cmd_check_version(args):
    "usage: check-version <version>, reads tags from stdin, prints 'major' or 'minor'"
    result = check_new_version(args[0], sys.stdin.read().split())
    print("last release: %s" % result["last"], file=sys.stderr)
    print("major" if result["major"] else "minor")


def cmd_glibc_floor(args):
    "usage: glibc-floor <ceiling>, reads '== path' sections of objdump output from stdin"
    ceiling = parse_glibc(args[0])
    floor, worst = glibc_floor(split_objdump_sections(sys.stdin.read()))
    if floor is None:
        raise SystemExit("no shared objects requiring glibc were found, refusing to pass an empty check")
    print("%s %s" % (format_version(floor), worst))
    if floor > ceiling:
        raise SystemExit("glibc floor %s (%s) is above the ceiling %s" % (format_version(floor), worst, args[0]))


def cmd_write_record(args):
    "usage: write-record <script-dir> <workspace> <version>, writes the record beside the rendered files in <workspace>/dist"
    script_dir, workspace, version = args
    record = build_record(version, read_state(os.path.join(workspace, "state")),
                          artefact_checksums(os.path.join(workspace, "release")))
    errors = validate(record, load_schema(script_dir))
    if errors:
        raise SystemExit("build record is invalid:\n  " + "\n  ".join(errors))
    path = os.path.join(workspace, "dist", "build.json")
    with open(path + ".pending", "w") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(path + ".pending", path)
    print(path)


def cmd_verify_record(args):
    """usage: verify-record <script-dir> <workspace> <version>
    checks the record in <script-dir>/dist against the workspace's artefacts and downstream clones,
    and each clone's files against the rendered files in <script-dir>/dist"""
    script_dir, workspace, version = args
    path = os.path.join(script_dir, "dist", "build.json")
    if not os.path.exists(path):
        raise SystemExit("no build record at %s, run './release.sh build %s' first" % (path, version))
    with open(path) as fh:
        record = json.load(fh)
    errors = validate(record, load_schema(script_dir))
    if record.get("version") != version:
        errors.append("record is for version %r, not %r" % (record.get("version"), version))
    if errors:
        raise SystemExit("build record is invalid:\n  " + "\n  ".join(errors))
    heads = {name: git_head(os.path.join(workspace, name)) for name in record["derived"]}
    problems = record_mismatches(record, artefact_checksums(os.path.join(workspace, "release")), heads)
    for name in sorted(record["derived"]):
        for changed, kind, _ in render.compare_trees(render.read_tree(os.path.join(script_dir, "dist", name)),
                                                     render.read_tree(os.path.join(workspace, name))):
            problems.append("repository %s: %s %s, compared with dist/%s" % (name, kind, changed, name))
    if problems:
        raise SystemExit("workspace no longer matches its build record:\n  " + "\n  ".join(problems))
    print("build record verified: %s" % path)


def cmd_record_get(args):
    "usage: record-get <record> <key>..., prints one value from a build record. artefact names contain dots, so each key is its own argument"
    path, keys = args[0], args[1:]
    with open(path) as fh:
        value = json.load(fh)
    for key in keys:
        value = value[key]
    print(value if isinstance(value, str) else json.dumps(value))


COMMANDS = {
    "check-version": cmd_check_version,
    "glibc-floor": cmd_glibc_floor,
    "write-record": cmd_write_record,
    "verify-record": cmd_verify_record,
    "record-get": cmd_record_get,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        raise SystemExit("usage: release.py {%s} ..." % ",".join(sorted(COMMANDS)))
    try:
        COMMANDS[argv[0]](argv[1:])
    except VersionError as err:
        raise SystemExit(str(err))


if __name__ == "__main__":
    main(sys.argv[1:])
