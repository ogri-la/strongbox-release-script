import os
import hashlib
import sys

def sha256(path):
    with open(path, "rb") as fh:
        #return hashlib.file_digest(fh, "sha256").hexdigest()
        m = hashlib.sha256()
        m.update(fh.read())
        return m.hexdigest()

def main(args):
    assert len(args) > 0 and "." in args[0]
    release = args[0].strip()
    necessary_file_list = [
        "la.ogri.strongbox.yml.template",
        "release/strongbox-%s-standalone.jar" % release,
        "release/strongbox-%s-standalone.jar.sha256" % release,
        "strongbox-flatpak/metainfo.xml",
        "strongbox-flatpak/strongbox.desktop",
        "strongbox-flatpak/strongbox.svg",
    ]
    for necessary_file in necessary_file_list:
        assert os.path.exists(necessary_file), "necessary file not found: " + necessary_file
    template = open("la.ogri.strongbox.yml.template").read()

    # valid according to spec but flathub doesn't like them
    removal_list = [
        "\n          path: app.jar",
        "\n          path: metainfo.xml",
        "\n          path: strongbox.desktop",
        "\n          path: strongbox.svg",
    ]
    for removal in removal_list:
        template = template.replace(removal, "")

    context = {
        "release": release,
        "app_jar_sha256": sha256("release/strongbox-%s-standalone.jar" % release),
        "metainfo_xml_sha256": sha256("strongbox-flatpak/metainfo.xml"),
        "strongbox_desktop_sha256": sha256("strongbox-flatpak/strongbox.desktop"),
        "strongbox_svg_sha256": sha256("strongbox-flatpak/strongbox.svg"),
    }

    sum1 = open("release/strongbox-%s-standalone.jar.sha256" % release).read().split(' ')[0] # file is: <sum>  <filename>
    sum2 = context["app_jar_sha256"]
    assert sum1 == sum2, "sums don't match: %r and %r" % (sum1, sum2)

    print(template.format(**context))

if __name__ == '__main__':
    main(sys.argv[1:])
