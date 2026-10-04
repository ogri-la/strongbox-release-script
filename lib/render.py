"""Renders release files from templates, and compares rendered files with downstream copies.

A template refers to context values as `{{ name }}`. `${...}` (bash, in a `PKGBUILD`) and single braces
(YAML) are left alone. A render plan is data: a list of phases, each a list of entries that render a
template or copy a file to an output path. Every function above `main` is pure.
"""

import difflib
import hashlib
import json
import os
import re
import sys

PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-z][a-z0-9_]*)\s*\}\}")


class RenderError(ValueError):
    pass


# --- templates


def placeholders(template):
    "returns the set of names a template refers to"
    return set(PLACEHOLDER_RE.findall(template))


def render(template, context, name="template"):
    "returns `template` with every placeholder replaced, raising `RenderError` for names missing from `context`"
    missing = placeholders(template) - set(context)
    if missing:
        raise RenderError("%s refers to names not in the context: %s" % (name, ", ".join(sorted(missing))))
    return PLACEHOLDER_RE.sub(lambda match: context[match.group(1)], template)


def hash_name(output):
    "returns the context name holding the sha256 of a rendered output, e.g. 'flatpak/metainfo.xml' => 'sha256_flatpak_metainfo_xml'"
    return "sha256_" + re.sub(r"[^a-z0-9]+", "_", output.lower()).strip("_")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def render_phase(entries, templates, copies, context):
    """renders one phase of a plan. returns `({output: bytes}, used names)`.
    `templates` maps template names to text, `copies` maps copy sources to bytes.
    an entry's overlay applies to that entry only, and every overlay name must be used by its template."""
    outputs = {}
    used = set()
    for entry in entries:
        output = entry["output"]
        if output in outputs:
            raise RenderError("two entries render %s" % output)
        if "copy" in entry:
            outputs[output] = copies[entry["copy"]]
            continue
        template = templates[entry["template"]]
        overlay = entry.get("overlay", {})
        unused_overlay = set(overlay) - placeholders(template)
        if unused_overlay:
            raise RenderError("%s: overlay names unused by %s: %s"
                              % (output, entry["template"], ", ".join(sorted(unused_overlay))))
        outputs[output] = render(template, {**context, **overlay}, entry["template"]).encode()
        used |= placeholders(template) - set(overlay)
    return outputs, used


def hashes_of(outputs, names):
    "returns the context entries holding the sha256 of each named output"
    return {hash_name(name): sha256(outputs[name]) for name in names}


def unused_names(context, used):
    "returns context names no template used"
    return set(context) - used


def render_plan(plan, templates, copies, context, check_unused=True):
    """renders every phase in order. a phase's `hashes` adds the sha256 of earlier outputs to the context.
    fails when any context name, including added hashes, is used by no template. a render of only the first
    phases passes `check_unused=False`, because a name may be used only by a later phase."""
    outputs = {}
    used = set()
    context = dict(context)
    for phase in plan["phases"]:
        context.update(hashes_of(outputs, phase.get("hashes", [])))
        rendered, phase_used = render_phase(phase["entries"], templates, copies, context)
        overlap = set(rendered) & set(outputs)
        if overlap:
            raise RenderError("outputs rendered twice: %s" % ", ".join(sorted(overlap)))
        outputs.update(rendered)
        used |= phase_used
    unused = unused_names(context, used) if check_unused else set()
    if unused:
        raise RenderError("context names used by no template: %s" % ", ".join(sorted(unused)))
    return outputs, context


# --- context
# phase 1's context comes from the version and strongbox's changelog, phase 2 adds the artefacts' checksums.

RELEASE_LIST_ITEM_TEMPLATE = '''<li>%s</li>'''

RELEASE_BODY_TEMPLATE = '''
                <p>%s</p>
                <ul>
                    %s
                </ul>'''

RELEASE_TEMPLATE = '''
        <release version="%s" date="%s">
            <description>
                %s
            </description>
        </release>
'''


def group_by(grouper, rows):
    "splits changelog lines into groups, each starting at a line `grouper` accepts. blank lines and sub-items are dropped"
    groups = []
    current_group = []
    for row in rows:
        if row.strip() == "":
            continue
        if row.startswith('    '):
            # sub-item, and sub-list-items are not allowed, ignore :(
            continue
        if grouper(row):
            groups.append(current_group)
            current_group = []
        current_group.append(row)
    groups.append(current_group)
    return groups


def metainfo_releases(changelog_data):
    "returns the metainfo `<releases>` element for `parse-changelog --json` output"
    releases = []
    for _, release_map in changelog_data.items():
        version, dt = release_map["title"].split(" - ")
        notes = group_by(lambda line: line.startswith('#'), release_map['notes'].splitlines())
        release_body_template_list = []
        for group in notes:
            if group == []:
                continue
            header = group[0].strip('# ')
            li_list = [RELEASE_LIST_ITEM_TEMPLATE % (row.strip('*#- ')) for row in group[1:]]
            if not group[1:]:
                # handling for release 1.0.0
                continue
            release_body_template_list.append(RELEASE_BODY_TEMPLATE % (header, "\n                    ".join(li_list)))
        releases.append(RELEASE_TEMPLATE % (version, dt, "\n".join(release_body_template_list)))
    return "    <releases>\n" + "\n".join(releases) + "    </releases>"


def metadata_context(version, strongbox_commit, release_notes, changelog_data):
    """returns phase 1's context. `release_notes` is `parse-changelog`'s output for this version.
    screenshots are referenced at `strongbox_commit`, which exists on GitHub before the release tag does."""
    return {
        "version": version,
        "strongbox_commit": strongbox_commit,
        "release_notes": release_notes.rstrip("\n"),
        "metainfo_releases": metainfo_releases(changelog_data),
    }


def packages_context(context, jar_sha256, appimage_sha256):
    "returns phase 2's context: phase 1's, with the artefacts' checksums"
    return {**context, "sha256_jar": jar_sha256, "sha256_appimage": appimage_sha256}


# --- file trees


def compare_trees(expected, actual):
    """compares two `{relative path: bytes}` maps. returns a sorted list of
    `(path, kind, diff)` with kind 'changed', 'missing' (in expected only) or 'unexpected' (in actual only)."""
    differences = []
    for path in sorted(set(expected) | set(actual)):
        if path not in actual:
            differences.append((path, "missing", ""))
        elif path not in expected:
            differences.append((path, "unexpected", ""))
        elif expected[path] != actual[path]:
            diff = difflib.unified_diff(
                expected[path].decode(errors="replace").splitlines(keepends=True),
                actual[path].decode(errors="replace").splitlines(keepends=True),
                fromfile="expected/" + path, tofile="actual/" + path)
            differences.append((path, "changed", "".join(diff)))
    return differences


# --- commands


def read_tree(root):
    "returns `{relative path: bytes}` for every file under `root`, excluding `.git`"
    tree = {}
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = [name for name in subdirectories if name != ".git"]
        for name in files:
            path = os.path.join(directory, name)
            with open(path, "rb") as fh:
                tree[os.path.relpath(path, root)] = fh.read()
    return tree


def write_tree(root, tree):
    for path, data in sorted(tree.items()):
        target = os.path.join(root, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(data)


def load_plan(script_dir):
    with open(os.path.join(script_dir, "templates", "plan.json")) as fh:
        return json.load(fh)


def load_templates(script_dir, plan):
    names = {entry["template"] for phase in plan["phases"] for entry in phase["entries"] if "template" in entry}
    templates = {}
    for name in sorted(names):
        with open(os.path.join(script_dir, "templates", name)) as fh:
            templates[name] = fh.read()
    return templates


def load_copies(workspace, plan):
    "reads copy sources, given as '<repository>:<path>' relative to the workspace"
    copies = {}
    for phase in plan["phases"]:
        for entry in phase["entries"]:
            if "copy" in entry:
                repository, path = entry["copy"].split(":", 1)
                with open(os.path.join(workspace, repository, path), "rb") as fh:
                    copies[entry["copy"]] = fh.read()
    return copies


def cmd_render(args):
    """usage: render <script-dir> <workspace> <phase-count> <context.json> <out-dir>
    renders the first `phase-count` phases into `out-dir`, and writes the context, with added hashes, beside them.
    rendering is pure, so a later call with more phases and a larger context re-renders earlier phases identically."""
    script_dir, workspace, phase_count, context_path, out_dir = args
    plan = load_plan(script_dir)
    partial = {"phases": plan["phases"][: int(phase_count)]}
    complete = len(partial["phases"]) == len(plan["phases"])
    with open(context_path) as fh:
        context = json.load(fh)
    try:
        outputs, full_context = render_plan(partial, load_templates(script_dir, partial), load_copies(workspace, partial),
                                            context, check_unused=complete)
    except RenderError as err:
        raise SystemExit("render failed: %s" % err)
    write_tree(out_dir, outputs)
    with open(os.path.join(out_dir, "context.json"), "w") as fh:
        json.dump(full_context, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("rendered %d files into %s" % (len(outputs), out_dir), file=sys.stderr)


def cmd_context(args):
    """usage: context <version> <strongbox-commit> <changelog> <parse-changelog> <out.json>
    writes phase 1's context from strongbox's changelog"""
    import subprocess
    version, strongbox_commit, changelog, parse_changelog, out = args
    notes = subprocess.check_output([parse_changelog, changelog, version], text=True)
    data = json.loads(subprocess.check_output([parse_changelog, changelog, "--json"], text=True))
    with open(out, "w") as fh:
        json.dump(metadata_context(version, strongbox_commit, notes, data), fh, indent=2, sort_keys=True)
        fh.write("\n")


def read_checksum(path):
    "returns the checksum from a `sha256sum`-format file"
    with open(path) as fh:
        return fh.read().split()[0]


def cmd_add_checksums(args):
    """usage: add-checksums <context.json> <release-dir> <version> <out.json>
    writes phase 2's context: the given context with the jar's and AppImage's checksums"""
    context_path, release_dir, version, out = args
    with open(context_path) as fh:
        context = json.load(fh)
    # checksums from an earlier render are recomputed, so they are dropped
    context = {key: value for key, value in context.items() if not key.startswith("sha256_")}
    jar = read_checksum(os.path.join(release_dir, "strongbox-%s-standalone.jar.sha256" % version))
    appimage = read_checksum(os.path.join(release_dir, "strongbox-%s-x86_64.AppImage.sha256" % version))
    with open(out, "w") as fh:
        json.dump(packages_context(context, jar, appimage), fh, indent=2, sort_keys=True)
        fh.write("\n")


def cmd_compare(args):
    "usage: compare <expected-dir> <actual-dir>, exits 1 and prints a diff per difference when they differ"
    expected_dir, actual_dir = args
    differences = compare_trees(read_tree(expected_dir), read_tree(actual_dir))
    for path, kind, diff in differences:
        print("%s: %s" % (kind, path))
        if diff:
            print(diff)
    if differences:
        raise SystemExit(1)


COMMANDS = {
    "context": cmd_context,
    "add-checksums": cmd_add_checksums,
    "render": cmd_render,
    "compare": cmd_compare,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        raise SystemExit("usage: render.py {%s} ..." % ",".join(sorted(COMMANDS)))
    COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
