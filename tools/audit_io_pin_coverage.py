"""Read-only comparison of project pin assignments with TD's physical IO table.

This does not replace board electrical/timing checks. Dedicated DPHY pads are
classified separately, never assigned arbitrary GPIO locations to hide warnings.
"""
import argparse
import json
from pathlib import Path
import re


def assignments(path, command):
    result = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    pattern = rf"{command}\s*\{{\s*([^}}]+?)\s*\}}\s*\{{([^}}]+)\}}"
    for name, properties in re.findall(pattern, text):
        location = re.search(r"LOCATION\s*=\s*([^;\s]+)", properties)
        standard = re.search(r"IOSTANDARD\s*=\s*([^;\s]+)", properties)
        if location and standard:
            result[name.strip()] = (location[1], standard[1])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("area", type=Path)
    args = parser.parse_args()
    normal = assignments(args.project / "user_source/constraints_source/pin.adc", "set_pin_assignment")
    ddr = assignments(args.project / "user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc", "set_ippin_assignment")
    # The IP's scalar CK port connects to the top's [0:0] vector.
    ddr = {(name+"[0]" if name in ("ddr_ck_p", "ddr_ck_n") else name): value
           for name, value in ddr.items()}
    area = args.area.read_text(encoding="utf-8", errors="replace")
    rows = {}
    for name, direction, location, standard, kind in re.findall(
            r"^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+(\S+)\s+(\S+)\s+(\S+)", area, re.M):
        rows[name] = (location, standard, kind)
    errors = []
    if len(normal) != 13 or len(ddr) != 45:
        errors.append(f"Unexpected assignment counts: normal={len(normal)}, DDR={len(ddr)}")
    for name, (location, standard) in normal.items():
        if name not in rows or rows[name][:2] != (location, standard):
            errors.append(f"Normal IO mapping mismatch: {name}")
    for name, (_, standard) in ddr.items():
        if name not in rows or rows[name][1:] != (standard, "DDR") or not rows[name][0].startswith("S82_"):
            errors.append(f"Integrated DDR IO mapping mismatch: {name}")
    auto_negative = {name for name in rows if name.endswith("(n)")}
    unexpected = set(rows) - set(normal) - set(ddr) - auto_negative
    if unexpected:
        errors.append(f"Unexpected physical IO rows: {sorted(unexpected)}")
    top = (args.project / "user_source/hdl_source/design_top_wrapper.v").read_text(encoding="utf-8")
    if not re.search(r'\.DPHY_RX_LOCATION\s*\(\s*"DPHY0"\s*\)', top):
        errors.append("Expected fixed DPHY0 macro location not found")
    result = dict(normal_io=len(normal), integrated_ddr_io=len(ddr),
                  physical_logical_io=len(set(normal)|set(ddr)),
                  automatic_tmds_negative_pads=len(auto_negative),
                  dedicated_mipi_pad_bits=10, errors=errors,
                  scope="Logical pin coverage and physical IO table only; not electrical/DDR board signoff")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
