import importlib.util
from pathlib import Path
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location(
    "edge_refine", Path(__file__).resolve().parents[1] / "tools/edge_refine_reference.py")
edge_refine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(edge_refine)


class EdgeRefineTests(unittest.TestCase):
    def test_isolated_single_pairs_and_2x2_removed(self):
        field = np.zeros((40, 60), dtype=bool)
        field[8, 8] = 1
        field[8, 20:22] = 1
        field[8:10, 35] = 1
        field[20:22, 8:10] = 1
        field[20, 25] = field[21, 26] = 1
        self.assertFalse(edge_refine.refine(field).any())

    def test_preserve_lines_endpoints_and_corners(self):
        for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
            field = np.zeros((60, 60), dtype=bool)
            for k in range(20):
                field[20 + k * dy, 30 + k * dx] = 1
            np.testing.assert_array_equal(edge_refine.refine(field), field)
        field = np.zeros((60, 60), dtype=bool)
        field[20, 10:31] = 1
        field[20:41, 30] = 1
        cleaned = edge_refine.window_stage(field)
        self.assertTrue(np.all(cleaned[field]))

    def test_bridge_one_and_two_pixel_gaps_four_axes(self):
        for gap in (1, 2):
            for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
                with self.subTest(gap=gap, direction=(dy, dx)):
                    field = np.zeros((64, 64), dtype=bool)
                    for k in range(-10, 11):
                        if k not in range(gap):
                            field[30 + k * dy, 30 + k * dx] = 1
                    result = edge_refine.refine(field)
                    for k in range(-10, 11):
                        self.assertTrue(result[30 + k * dy, 30 + k * dx])

    def test_no_bridge_three_pixel_gap(self):
        field = np.zeros((40, 60), dtype=bool)
        field[20, 10:50] = 1
        field[20, 28:31] = 0
        self.assertFalse(edge_refine.refine(field)[20, 28:31].any())

    def test_parallel_lines_four_pixels_apart_not_merged(self):
        field = np.zeros((40, 60), dtype=bool)
        field[15, 10:50] = field[19, 10:50] = 1
        np.testing.assert_array_equal(edge_refine.refine(field), field)

    def test_three_pixel_straight_stroke_preserved(self):
        field = np.zeros((24, 24), dtype=bool)
        field[12, 10:13] = 1
        np.testing.assert_array_equal(edge_refine.refine(field), field)

    def test_raster_shift_and_blank_frame(self):
        field = np.zeros((40, 60), dtype=bool)
        field[20, 10:40] = 1
        expected = np.zeros_like(field)
        expected[24, 14:44] = 1
        np.testing.assert_array_equal(edge_refine.refine(field, raster=True), expected)
        self.assertFalse(edge_refine.refine(np.zeros_like(field), raster=True).any())


if __name__ == "__main__":
    unittest.main()
