import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('scene', Path(__file__).parents[1] / 'game/scene.py')
scene = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scene)


class SceneTests(unittest.TestCase):
    def snapshot(self):
        data = bytearray((i * 11 + (i >> 8) * 17) & 255
                         for i in range(scene.EEPROM_SIZE + scene.VIDEO_SIZE))
        data[-16:] = scene.SIGNATURE
        return data

    def test_all_regions_round_trip(self):
        data = self.snapshot()
        parts = scene.decode(data)
        self.assertEqual(parts['nvram.bin'], data[:128])
        for name, (offset, size) in scene.REGIONS.items():
            self.assertEqual(parts[name], data[128 + offset:128 + offset + size])
        for lane, color in enumerate('rgb', 1):
            self.assertEqual(len(parts[f'pal_{color}.bin']), 2048)
            for entry in (0, 1023, 1024, 2047):
                self.assertEqual(parts[f'pal_{color}.bin'][entry],
                                 data[128 + 0x6000 + entry * 4 + lane])
        self.assertEqual(len(parts['obj.bin']), 16384)
        self.assertEqual(parts['obj.bin'][-2:], data[128 + 0xbffe:128 + 0xc000])

    def test_reject_missing_or_extra_state(self):
        data = self.snapshot()
        for bad in (data[:-1], data + b'\0', data[:37025]):
            with self.assertRaises(ValueError):
                scene.decode(bad)

    def test_reject_wrong_version(self):
        data = self.snapshot()
        data[-8] = 2
        with self.assertRaises(ValueError):
            scene.decode(data)


if __name__ == '__main__':
    unittest.main()
