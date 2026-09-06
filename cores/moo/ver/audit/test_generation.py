"""Negative-admission checks for Moo's generation comparison."""
from pathlib import Path
import tempfile
import unittest

from check_generation import MOO_SOURCES, compare


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.left, self.right = root / "left", root / "right"
        self.left.mkdir()
        self.right.mkdir()
        source = root / "cores/moo/hdl"
        source.mkdir(parents=True)
        self.paths = [source / name for name in sorted(MOO_SOURCES)]
        for i, path in enumerate(self.paths):
            path.write_text(f"module unit{i}; endmodule\n")
        for directory in (self.left, self.right):
            self.manifest(directory, self.paths)

    @staticmethod
    def manifest(directory, paths):
        (directory / "files.qip").write_text("".join(
            f"set_global_assignment -name VERILOG_FILE {p.as_posix()}\n"
            for p in paths))

    def test_identical_projects(self):
        self.assertTrue(compare(self.left, self.right)["pass"])

    def test_order_difference_rejected(self):
        self.manifest(self.right, list(reversed(self.paths)))
        result = compare(self.left, self.right)
        self.assertFalse(result["pass"])
        self.assertTrue(result["source_membership_equal"])
        self.assertFalse(result["source_order_equal"])

    def test_missing_source_rejected(self):
        self.paths[0].unlink()
        with self.assertRaisesRegex(ValueError, "Missing source"):
            compare(self.left, self.right)

    def test_added_macro_rejected(self):
        (self.right / "core.qsf").write_text('set_global_assignment -name VERILOG_MACRO "X=1"\n')
        self.assertFalse(compare(self.left, self.right)["pass"])

    def test_unparsed_assignment_rejected(self):
        (self.right / "files.qip").write_text("source hidden.tcl\n")
        with self.assertRaisesRegex(ValueError, "Unparsed"):
            compare(self.left, self.right)


if __name__ == "__main__":
    unittest.main()
