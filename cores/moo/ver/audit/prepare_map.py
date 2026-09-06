"""Prepare Moo's native MiSTer synthesis project without running jtcore."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

CORE = Path(__file__).resolve().parents[2]
ROOT = CORE.parents[1]
FRAME = ROOT / 'modules/jtframe'
OUT = CORE / 'ver/audit/results/production'


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUT)
    args = parser.parse_args()
    OUT = args.output.resolve()
    if not OUT.is_relative_to(CORE.resolve()):
        parser.error('--output must remain under cores/moo')
    OUT.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, JTROOT=ROOT.as_posix(), JTFRAME=FRAME.as_posix(),
               CORES=(ROOT / 'cores').as_posix(), MODULES=(ROOT / 'modules').as_posix(),
               JTBIN=(OUT / 'jtbin').as_posix())
    def generate(*args):
        return subprocess.check_output([str(FRAME / 'src/jtframe/jtframe.exe'), *args],
                                       cwd=OUT, env=env, text=True)
    for extension in ('qpf', 'qsf'):
        generate('parse', 'moo', str(FRAME / f'target/mister/mister.{extension}'),
                 '--target', 'mister', '--output', str(OUT / f'jtmoo.{extension}'))
    # The template's shell variables are expanded by jtcore's shell environment.
    qpf = OUT / 'jtmoo.qpf'
    qpf.write_text(qpf.read_text().replace('${CORENAME}', 'moo'), newline='\n')
    qsf = OUT / 'jtmoo.qsf'
    definitions = generate('cfgstr', 'moo', '--target', 'mister', '--output', 'quartus')
    generate('cfgstr', 'moo', '--target', 'mister', '--output', 'cfgstr')
    qsf.write_text(qsf.read_text() + '\n' + '\n'.join(sorted(definitions.splitlines())) +
                   f'\nset_global_assignment -name SEARCH_PATH "{CORE.as_posix()}/hdl"\n',
                   newline='\n')
    generate('mem', 'moo', '--target', 'mister', '--local')
    generate('files', 'syn', 'moo', '--target', 'mister', '--local')
    qip = OUT / 'files.qip'
    # Native generator paths are Tcl words: backslashes would escape separators.
    lines = qip.read_text().replace('\\', '/').splitlines()
    qip.write_text('\n'.join(dict.fromkeys(lines)) + '\n', newline='\n')
    generate('msg', 'moo')
    inputs = [FRAME / 'bin/font0.hex', FRAME / 'hdl/video/logodata.hex',
              FRAME / 'hdl/video/logomap.hex']
    inputs += sorted((FRAME / 'hdl/sound').glob('*.hex'))
    inputs += sorted((CORE / 'hdl').glob('*.hex'))
    for source in inputs:
        shutil.copyfile(source, OUT / source.name)
    print(OUT)


if __name__ == '__main__':
    main()
