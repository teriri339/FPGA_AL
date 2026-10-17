"""Independent NumPy reference and RTL vectors for binary edge refinement.

Inputs are pre-dilation one-bit edge maps, not RGB photos. This does not run
the preceding Gaussian/Sobel/NMS stages or predict their missing contours.
"""
import argparse
from pathlib import Path

import numpy as np


def window_stage(edge, bridge=False, raster=False):
    edge = np.asarray(edge, dtype=bool)
    height, width = edge.shape
    padded = np.pad(edge, 2)
    w = [[padded[y:y + height, x:x + width] for x in range(5)] for y in range(5)]
    if bridge:
        result = edge.copy()
        for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
            a, b, c, d = (w[2 + k * dy][2 + k * dx] for k in (-2, -1, 1, 2))
            result |= (b & c & (a | d)) | (a & b & d) | (a & c & d)
    else:
        adjacent = np.zeros_like(edge)
        outer = np.zeros_like(edge)
        for y in range(5):
            for x in range(5):
                distance = max(abs(y - 2), abs(x - 2))
                if distance == 1:
                    adjacent |= w[y][x]
                elif distance == 2:
                    outer |= w[y][x]
        opposite = np.zeros_like(edge)
        for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
            opposite |= w[2 - dy][2 - dx] & w[2 + dy][2 + dx]
        result = edge & ((adjacent & outer) | opposite)
    if raster:
        # Hardware emits the centre result at the current bottom-right scan
        # position and suppresses incomplete 5x5 top/left windows.
        shifted = np.zeros_like(edge)
        shifted[4:, 4:] = result[2:height - 2, 2:width - 2]
        return shifted
    return result


def refine(edge, raster=False):
    return window_stage(window_stage(edge, raster=raster), bridge=True, raster=raster)


def fixtures(width=96, height=80):
    """Structured, dense noise, blank-after-nonblank, and boundary fixtures."""
    field = np.zeros((height, width), dtype=bool)
    field[5, 5] = 1
    field[7, 15:17] = 1
    field[5:7, 25:27] = 1
    field[15, 8:85] = 1
    field[15, 20] = 0
    field[15, 40:42] = 0
    field[15, 60:63] = 0
    field[25:70, 10] = 1
    field[40:42, 10] = 0
    for k in range(30):
        field[28 + k, 28 + k] = 1
        field[28 + k, 82 - k] = 1
    field[40:42, 40:42] = 0
    field[40:42, 69:71] = 0
    field[65, 30:80] = 1
    field[69, 30:80] = 1
    rng = np.random.default_rng(20261017)
    random = rng.random((height, width)) < 0.14
    border = np.zeros_like(field)
    border[:5, :] = 1
    border[-5:, :] = 1
    border[:, :5] = 1
    border[:, -5:] = 1
    return [field, random, np.zeros_like(field), border]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=96)
    parser.add_argument("--height", type=int, default=80)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    for index, field in enumerate(fixtures(args.width, args.height)):
        expected = refine(field, raster=True)
        words = field.astype(np.uint8) * 2 + expected.astype(np.uint8)
        np.savetxt(args.output / f"edge_{index}.mem", words.ravel(), fmt="%x")
    print(f"Prepared four {args.width}x{args.height} input/expected binary maps in {args.output}")


if __name__ == "__main__":
    main()
