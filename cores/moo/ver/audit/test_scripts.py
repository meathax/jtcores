"""Exercise Moo's shell wrappers with fake tools; never launches a simulator."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CORE = Path(__file__).resolve().parents[2]
BASH = shutil.which("bash")


class ScriptTests(unittest.TestCase):
    def setUp(self):
        results = CORE / "ver/audit/results"
        results.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="scripts-", dir=results)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "cores/moo/ver/moomesa"
        self.work.mkdir(parents=True)
        for name in ("sim.sh", "sim_coin.sh"):
            self.write(self.work / name, (CORE / "ver/moomesa" / name).read_text())
        self.wrapper = self.root / "cores/moo/ver/game/dump_split.sh"
        self.write(self.wrapper, (CORE / "ver/game/dump_split.sh").read_text())
        self.write(self.wrapper.with_name("scene.py"),
                   'import os, sys\nfrom pathlib import Path\n'
                   'Path("split.args").write_text("\\n".join(sys.argv[1:]) + "\\n")\n'
                   'sys.exit(int(os.environ.get("SPLIT_RC", "0")))\n')
        self.bin = self.root / "bin"
        self.write(self.bin / "jtsim",
                   '#!/bin/bash\nprintf "%s\\n" "$@" > sim.args\n'
                   'if [[ -n "${MOCK_FRAME:-}" ]]; then\n'
                   '  mkdir -p frames\n'
                   '  printf pixels > "frames/frame_00001.$MOCK_FRAME"\n'
                   '  printf "%s\\n" "${MOCK_CRC:-1234}" > frames/frames.crc\n'
                   'fi\nexit "${SIM_RC:-0}"\n')
        self.write(self.bin / "jtutil", '#!/bin/bash\nexit 0\n')
        self.env = dict(os.environ)
        self.env["PATH"] = self.bin.as_posix() + os.pathsep + self.env.get("PATH", "")
        self.work.joinpath("nvram.bin").write_bytes(bytes(128))

    @staticmethod
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, newline="\n")
        path.chmod(0o755)

    def run_script(self, *args, script="sim.sh", **env):
        return subprocess.run([BASH, script, *args], cwd=self.work,
                              env={**self.env, **env}, capture_output=True,
                              text=True, timeout=10)

    def test_missing_nvram_is_failure(self):
        self.work.joinpath("nvram.bin").unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.work.joinpath("sim.args").exists())

    def test_simulator_failure_propagates(self):
        self.assertEqual(self.run_script(SIM_RC="37").returncode, 37)

    def test_scene_split_failure_stops_simulator(self):
        self.work.joinpath("scenes/test").mkdir(parents=True)
        self.assertEqual(self.run_script("--scene", "test", SPLIT_RC="23").returncode, 23)
        self.assertFalse(self.work.joinpath("sim.args").exists())

    def test_batch_is_forwarded(self):
        result = self.run_script("--batch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-batch", self.work.joinpath("sim.args").read_text().splitlines())

    def test_arguments_keep_boundaries(self):
        result = self.run_script("-d", "A B")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.work.joinpath("sim.args").read_text().splitlines(), ["-d", "A B"])

    def test_scene_requires_frame(self):
        self.work.joinpath("scenes/test").mkdir(parents=True)
        result = self.run_script("--scene", "test")
        self.assertNotEqual(result.returncode, 0)

    def test_dump_wrapper_forwards_arguments(self):
        result = self.run_script("--scene", "test", "--nvram", "--fullram",
                                 script="../game/dump_split.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.work.joinpath("split.args").read_text().splitlines(),
                         ["--scene", "test", "--nvram", "--fullram"])

    def test_coin_simulator_failure_propagates(self):
        self.assertEqual(self.run_script(script="sim_coin.sh", SIM_RC="37").returncode, 37)

    def test_missing_scene_argument(self):
        self.assertNotEqual(self.run_script("--scene").returncode, 0)

    def test_png_scene_preserves_extension(self):
        scene = self.work / "scenes/test"
        scene.mkdir(parents=True)
        result = self.run_script("--scene", "test", MOCK_FRAME="png")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((scene / "test.png").read_text(), "pixels")
        self.assertEqual((scene / "test.crc").read_text(), "1234\n")

    def test_crc_mismatch_preserves_golden(self):
        scene = self.work / "scenes/test"
        scene.mkdir(parents=True)
        (scene / "test.crc").write_text("old\n")
        result = self.run_script("--scene", "test", MOCK_FRAME="jpg")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((scene / "test.crc").read_text(), "old\n")

    def test_explicit_crc_update(self):
        scene = self.work / "scenes/test"
        scene.mkdir(parents=True)
        (scene / "test.crc").write_text("old\n")
        result = self.run_script("--scene", "test", "--crc", MOCK_FRAME="jpg")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((scene / "test.crc").read_text(), "1234\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bash", default=BASH)
    args, remaining = parser.parse_known_args()
    BASH = args.bash
    if not BASH:
        parser.error("Bash is required; use --bash with its path")
    unittest.main(argv=[__file__, *remaining])
