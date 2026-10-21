import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("example_logo", ROOT / "tools/prepare_example_logo_verification.py")
example = importlib.util.module_from_spec(spec)
spec.loader.exec_module(example)


class ExampleLogoTests(unittest.TestCase):
    def test_original_pixels_and_transparency(self):
        text = (ROOT / "reference_edge_project/user_source/hdl_source/hx1p35_port/anlogic_logo_rom.v").read_text()
        pixels = example.pixels_from_source(text)
        self.assertEqual(len(pixels), 32768)
        self.assertEqual(int((pixels >> 24).sum()), 6387)
        self.assertEqual(int(pixels[5494]), 0x1D3D4D8)
        self.assertEqual(int(pixels[5499]), 0x1FCD5D5)
        self.assertEqual(int(pixels[20426]), 0x1FDE0E1)
        self.assertFalse(pixels[25600:].any())
        self.assertGreater(len(set(map(int, pixels[pixels != 0]))), 16)

    def test_reject_duplicate_or_out_of_picture(self):
        for text in ("15'd1: O_pixel = 25'h1000000; 15'd1: O_pixel = 25'h1000001;",
                     "15'd25600: O_pixel = 25'h1000000;"):
            with self.assertRaises(ValueError):
                example.pixels_from_source(text + " default: O_pixel = 25'd0;")

    def test_reject_unknown_default(self):
        with self.assertRaises(ValueError):
            example.pixels_from_source("15'd1: O_pixel = 25'h1000000;")


if __name__ == "__main__":
    unittest.main()
