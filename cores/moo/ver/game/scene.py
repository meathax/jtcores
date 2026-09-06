"""Moo scene snapshot version 1: validation and restore-file extraction."""
import argparse
import hashlib
import json
from pathlib import Path

EEPROM_SIZE = 128
VIDEO_SIZE = 0xc0f0
SIGNATURE = b'MOOSCENE\x01' + bytes(7)
REGIONS = {
    'scr0.bin': (0x0000, 0x2000),
    'scr1.bin': (0x2000, 0x2000),
    'scr2.bin': (0x4000, 0x2000),
    'pal.bin': (0x6000, 0x2000),
    'obj.bin': (0x8000, 0x4000),
    'scr_mmr.bin': (0xc000, 64),
    'gfx_mmr.bin': (0xc040, 8),
    'pal_mmr.bin': (0xc080, 13),
    'k338_mmr.bin': (0xc0a0, 32),
    'obj_mmr.bin': (0xc0c0, 8),
    'ccu.bin': (0xc0d0, 16),
}


def decode(data):
    if len(data) != EEPROM_SIZE + VIDEO_SIZE:
        raise ValueError(f'expected {EEPROM_SIZE + VIDEO_SIZE} bytes; got {len(data)}; '
                         'legacy dumps omit state and cannot be upgraded losslessly')
    video = data[EEPROM_SIZE:]
    if video[0xc0e0:] != SIGNATURE:
        raise ValueError('missing Moo scene version 1 signature')
    parts = {'nvram.bin': data[:EEPROM_SIZE]}
    for name, (offset, size) in REGIONS.items():
        parts[name] = video[offset:offset + size]
    for lane, color in enumerate('rgb', 1):
        parts[f'pal_{color}.bin'] = parts['pal.bin'][lane::4]
    return parts


def extract(source, destination):
    data = source.read_bytes()
    parts = decode(data)  # Validate everything before touching restore files.
    destination.mkdir(parents=True, exist_ok=True)
    for name, payload in parts.items():
        (destination / name).write_bytes(payload)
    manifest = {'schema': 'moo-scene-v1', 'source_sha256': hashlib.sha256(data).hexdigest(),
                'files': {name: {'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
                          for name, payload in parts.items()},
                'contract': 'scene RAM and display registers; not a CPU/audio checkpoint'}
    (destination / 'scene.json').write_text(json.dumps(manifest, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-s', '--scene', default='')
    parser.add_argument('-f', '--file', type=Path)
    parser.add_argument('--output', type=Path, default=Path.cwd())
    # Accepted legacy invocation flags; Moo v1 always includes these regions.
    parser.add_argument('--nvram', action='store_true')
    parser.add_argument('--fullram', action='store_true')
    parser.add_argument('--fullobj', action='store_true')
    args = parser.parse_args()
    directory = Path('scenes') / args.scene if args.scene else Path.cwd()
    source = args.file
    if source is not None and not source.is_absolute():
        source = directory / source
    if source is None:
        source = next((directory / n for n in
                       (Path.cwd().name.upper() + '.RAM', Path.cwd().name + '.sav', 'dump.bin')
                       if (directory / n).is_file()), None)
    if source is None:
        if args.scene:
            parser.error(f'no scene snapshot in {directory}')
        return  # Ordinary cold boot has no scene snapshot to restore.
    try:
        extract(source, args.output)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f'Validated and extracted Moo scene: {source}')


if __name__ == '__main__':
    main()
