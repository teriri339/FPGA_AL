import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_logo", ROOT / "tools/prepare_anlogic_logo.py")
prepare_logo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare_logo)


class AnlogicLogoTests(unittest.TestCase):
    def test_embedded_rom_has_all_pixels_and_palette(self):
        text = (ROOT / "reference_edge_project/user_source/hdl_source/hx1p35_port/hx_anlogic_logo_rom.v").read_text()
        chunks = re.findall(r"256'h([0-9a-f]{64})", text)
        self.assertEqual(len(chunks), 256)
        rom = np.array([int(n, 16) for n in "".join(chunks)[::-1]], dtype=np.uint8)
        entries = re.findall(r"4'd(\d+): O_rgb = 24'h([0-9a-f]{6})", text)
        self.assertEqual([int(i) for i, _ in entries], list(range(16)))
        palette = np.array([[int(value[n:n+2], 16) for n in (0, 2, 4)] for _, value in entries])
        image = palette[rom[:15360]].reshape(96, 160, 3)
        # Visible mark retains substantial red and navy areas on a white panel.
        red = (image[:, :, 0] > 180) & (image[:, :, 1] < 100) & (image[:, :, 2] < 100)
        navy = (image[:, :, 0] < 70) & (image[:, :, 1] < 90) & (image[:, :, 2] < 130)
        self.assertGreater(int(red.sum()), 1000)
        self.assertGreater(int(navy.sum()), 2500)
        np.testing.assert_array_equal(image[:, :6], 255)

    def test_converter_preserves_crop_and_pixel_order(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "logo.v"
            source.write_text("15'd6407: O_pixel = 25'h1ed1c24;\n15'd12888: O_pixel = 25'h11c2d4e;\n")
            rom, palette, metadata = prepare_logo.convert(source)
            np.testing.assert_array_equal(palette[rom[(40-32)*160+7]], [237, 28, 36])
            np.testing.assert_array_equal(palette[rom[(80-32)*160+88]], [28, 45, 78])
            self.assertEqual(metadata["crop_xywh"], [0, 32, 160, 96])
            generated = prepare_logo.render_rtl(rom, palette, metadata)
            chunks = re.findall(r"256'h([0-9a-f]{64})", generated)
            restored = np.array([int(n, 16) for n in "".join(chunks)[::-1]], dtype=np.uint8)
            np.testing.assert_array_equal(restored, rom)

    def test_reject_unknown_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.v"
            source.write_text("not an artwork ROM")
            with self.assertRaises(ValueError):
                prepare_logo.convert(source)


if __name__ == "__main__":
    unittest.main()
