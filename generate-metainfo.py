import os
import sys
import subprocess
import json

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


def main(args):
    #metainfo_template_path = os.path.abspath(args[0])
    #changelog_path = os.path.abspath(args[1])
    metainfo_template_path = "metainfo.xml.template"
    changelog_path = "strongbox/CHANGELOG.md"

    assert os.path.exists(metainfo_template_path)
    assert os.path.exists(changelog_path)

    # parse given changelog into json
    output = subprocess.check_output(["./parse-changelog", changelog_path, "--json"])
    data = json.loads(output)

    releases = []

    for _, release_map in data.items():
        title = release_map["title"]
        version, dt = title.split(" - ")
        notes = release_map['notes'].splitlines()
        notes = group_by(lambda line: line.startswith('#'), notes)
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

    releases_str = "    <releases>\n" + "\n".join(releases) + "    </releases>"

    with open("metainfo_template_path") as fh:
        metainfo = fh.read().format(releases=releases_str)
        print(metainfo)

if __name__ == '__main__':
    main(sys.argv[1:])
