import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "calibrate_white_field.py"
spec = importlib.util.spec_from_file_location("calibrate", SCRIPT)
calibrate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calibrate)


class WhiteFieldTests(unittest.TestCase):
    def test_uniform_and_black(self):
        frame = np.full((90, 160, 3), [90, 130, 170], dtype=float)
        gains, _ = calibrate.make_table(frame, black=10, target=120)
        np.testing.assert_array_equal(gains, np.broadcast_to([384, 256, 192], (9, 16, 3)))

    def test_invalid_dark_and_gain(self):
        for value in (0, 10):
            with self.assertRaises(ValueError):
                calibrate.make_table(np.full((90, 160, 3), value))
        frame = np.full((90, 160, 3), [20, 180, 180], dtype=float)
        with self.assertRaises(ValueError):
            calibrate.make_table(frame)

    def test_spatial_field(self):
        yy, xx = np.mgrid[0:90, 0:160]
        field = np.stack([100+xx*.3, 170-xx*.2+yy*.1, 120+yy*.4], axis=-1)
        table, _ = calibrate.make_table(field, target=140)
        # Independently evaluate the gain table over the complete test image.
        corrected = np.empty_like(field)
        for y in range(90):
            uy = y*8/89
            j = min(int(uy), 7)
            fy = uy-j
            for x in range(160):
                ux = x*15/159
                i = min(int(ux), 14)
                fx = ux-i
                gain = ((1-fy)*((1-fx)*table[j,i]+fx*table[j,i+1]) +
                        fy*((1-fx)*table[j+1,i]+fx*table[j+1,i+1]))/256
                corrected[y,x] = field[y,x]*gain
        self.assertLess(np.max(np.abs(corrected-140)), 2)
        self.assertLess(corrected.std(), field.std()/10)

    def test_cli_table_and_rejections(self):
        with tempfile.TemporaryDirectory(prefix="white_field_test_") as directory:
            root = Path(directory)
            frames = root / "frames"
            frames.mkdir()
            output = root / "gains.mem"
            frame = np.full((720, 1280, 3), [120, 160, 200], dtype=np.uint8)
            for n in range(16):
                Image.fromarray(frame).save(frames / f"{n:02}.png")
            cmd = [sys.executable, str(SCRIPT), str(frames), "--output", str(output), "--target", "160"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text().splitlines(), ["1551000cd"]*144)
            self.assertEqual(len(json.loads(output.with_suffix(".json").read_text())["frames"]), 16)
            Image.fromarray(np.full_like(frame, 255)).save(frames / "00.png")
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reduce exposure", result.stderr)
            Image.fromarray(np.full_like(frame, 150)).save(frames / "00.png")
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Frame mean changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
