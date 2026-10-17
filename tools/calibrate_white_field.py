"""Generate the display-domain 16x9 RGB Q4.8 LUT from digital white-field frames.

Requires numpy and Pillow. Input must be uncorrected, OSD-free 1280x720 RGB
captures with identical exposure/gain/fixed-AWB settings, not photos of a screen.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def make_table(mean, black=0, target=None):
    height, width, channels = mean.shape
    if channels != 3 or width < 16 or height < 9:
        raise ValueError("Expected an RGB image at least 16x9")
    signal = np.maximum(mean.astype(np.float64) - black, 0)
    nodes = np.empty((9, 16, 3), dtype=np.float64)
    # Local averages reject fine texture without blurring the corrected video.
    rx, ry = max(1, round((width-1)/30)), max(1, round((height-1)/16))
    for j, y in enumerate(np.linspace(0, height-1, 9)):
        for i, x in enumerate(np.linspace(0, width-1, 16)):
            ix, iy = round(x), round(y)
            nodes[j, i] = signal[max(0, iy-ry):min(height, iy+ry+1),
                                  max(0, ix-rx):min(width, ix+rx+1)].mean(axis=(0, 1))
    if nodes.min() < 16:
        raise ValueError("White field too dark: a node has less than 16 DN above black")
    target = float(np.median(nodes)) if target is None else float(target)
    if not 16 <= target <= 240:
        raise ValueError("Target must be between 16 and 240 DN")
    gains = target / nodes
    if gains.min() < 0.25 or gains.max() > 4.0:
        raise ValueError("Required gains exceed [0.25, 4]; check lighting/exposure")
    quantized = np.floor(gains*256+0.5).astype(np.uint16)
    return quantized, {"target": target, "gain_min": float(gains.min()),
                       "gain_max": float(gains.max()),
                       "node_signal_min": float(nodes.min()),
                       "node_signal_max": float(nodes.max())}


def write_table(path, table):
    # One row-major 36-bit RGB word per line, consumed by $readmemh.
    words = [(int(r) << 24) | (int(g) << 12) | int(b)
             for r, g, b in table.reshape(-1, 3)]
    path.write_text("".join(f"{word:09x}\n" for word in words), encoding="ascii")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path, help="Directory of lossless PNG/BMP/TIFF frames")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--black-level", type=int, default=0,
                        help="Black offset measured at this RGB stage, not sensor RAW black")
    parser.add_argument("--target", type=float)
    args = parser.parse_args()
    if not 0 <= args.black_level < 240:
        parser.error("black level must be 0..239")
    files = sorted(p for p in args.frames.iterdir()
                   if p.suffix.lower() in {".png", ".bmp", ".tif", ".tiff"})
    if not 16 <= len(files) <= 32:
        parser.error(f"Expected 16..32 lossless digital frames; found {len(files)}")
    total = np.zeros((720, 1280, 3), dtype=np.float64)
    frame_means = []
    clipped = 0
    for path in files:
        with Image.open(path) as im:
            if im.size != (1280, 720) or im.mode != "RGB":
                parser.error(f"{path.name}: expected 1280x720 RGB, got {im.size} {im.mode}")
            frame = np.asarray(im, dtype=np.float64)
        clipped += int(np.count_nonzero(frame >= 250))
        total += frame
        frame_means.append(frame.mean(axis=(0, 1)).tolist())
    clip_fraction = clipped / (len(files)*total.size)
    if clip_fraction > 0.001:
        parser.error("More than 0.1% channel samples >=250; reduce exposure")
    means = np.asarray(frame_means)
    if np.max(np.ptp(means, axis=0)) > 3:
        parser.error("Frame mean changed by >3 DN; lock exposure/gain/AWB and remove flicker")
    try:
        table, report = make_table(total/len(files), args.black_level, args.target)
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_table(args.output, table)
    report.update({"width": 1280, "height": 720, "grid": [16, 9],
                   "format": "row-major RGB Q4.8, 36-bit hex", "frames": [str(p) for p in files],
                   "black_level": args.black_level, "clipped_fraction": clip_fraction,
                   "frame_channel_means": frame_means})
    args.output.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Wrote {args.output}: gain {report['gain_min']:.3f}..{report['gain_max']:.3f}")


if __name__ == "__main__":
    main()
