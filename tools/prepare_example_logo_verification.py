"""Verify the unmodified lab_ex3 logo source against its supplied ZIP archive.

Generate independent 25-bit transparency/RGB vectors, without cropping,
quantization, white backing, or rewriting the example RTL.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

import numpy as np
from PIL import Image


def pixels_from_source(text):
    pixels = np.zeros(32768, dtype=np.uint32)
    entries = re.findall(r"15'd(\d+):\s*O_pixel\s*=\s*25'h([0-9a-fA-F]+)", text)
    if not entries:
        raise ValueError("No example logo pixels found")
    seen = set()
    for address, value in entries:
        address, value = int(address), int(value, 16)
        if address >= 160 * 160 or address in seen or value >= 1 << 25:
            raise ValueError("Invalid or duplicate example logo entry")
        pixels[address] = value
        seen.add(address)
    if not re.search(r"default:\s*O_pixel\s*=\s*25'd0", text):
        raise ValueError("Unknown default pixel behaviour")
    return pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with ZipFile(args.archive) as archive:
        matches = [n for n in archive.namelist() if n.endswith("/user_source/hdl_source/anlogic_logo_rom.v")]
        mixers = [n for n in archive.namelist() if n.endswith("/user_source/hdl_source/hdmi_mixer.v")]
        if len(matches) != 1 or len(mixers) != 1:
            raise ValueError("Expected one original logo ROM and mixer")
        source = archive.read(matches[0])
        mixer = archive.read(mixers[0])
    target = Path(__file__).resolve().parents[1] / "reference_edge_project/user_source/hdl_source/hx1p35_port/anlogic_logo_rom.v"
    if target.read_bytes() != source:
        raise ValueError("Project example ROM is not byte-identical to supplied archive")
    pixel_data = pixels_from_source(source.decode("utf-8"))
    args.output.mkdir(parents=True, exist_ok=False)
    np.savetxt(args.output / "logo_expected.mem", pixel_data, fmt="%07x")
    rgba = np.stack([(pixel_data >> 16) & 255, (pixel_data >> 8) & 255,
                     pixel_data & 255, ((pixel_data >> 24) & 1) * 255], axis=-1)
    Image.fromarray(rgba[:25600].astype(np.uint8).reshape(160, 160, 4)).save(args.output / "example_logo.png")
    metadata = {"archive": str(args.archive), "source_entry": matches[0], "mixer_entry": mixers[0],
                "source_sha256": hashlib.sha256(source).hexdigest(),
                "mixer_sha256": hashlib.sha256(mixer).hexdigest(),
                "visible_pixels": int(np.count_nonzero(pixel_data >> 24)), "size": [160, 160],
                "rgb_bits": 24, "transparency_bit": 24, "byte_identical": True}
    (args.output / "example_source.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
