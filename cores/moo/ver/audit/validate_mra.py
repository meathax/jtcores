"""Validate a privately staged Moo MRA set; never assemble or distribute ROMs."""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

EXPECTED = {'moomesa', 'moomesaaab', 'moomesauab', 'moomesauac'}


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def validate(root):
    found = set()
    versions = set()
    for path in sorted(root.rglob('*.mra')):
        tree = ET.parse(path).getroot()
        name = tree.findtext('setname')
        require(name in EXPECTED and name not in found, (path, name))
        found.add(name)
        require(tree.findtext('rbf') == 'jtmoo', path)
        require(tree.findtext('rotation') == 'horizontal', path)
        version = tree.findtext('mameversion')
        require(version and re.fullmatch(r'\d{4}', version), (path, version))
        versions.add(version)
        resolution = tree.findtext('resolution')
        require(resolution in (None, '15kHz'), (path, resolution))
        for tag in ('homebrew', 'bootleg'):
            require(tree.findtext(tag) in (None, 'yes', 'no'), (path, tag))
        rom = tree.find("rom[@index='0']")
        require(rom is not None and 'type' not in rom.attrib, path)
        require(rom.findall('part'), path)
    require(found == EXPECTED, ('missing sets', EXPECTED - found))
    require(len(versions) == 1, versions)
    print(f'PASS: {len(found)} Moo MRAs; database version {versions.pop()}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    validate(parser.parse_args().directory)
