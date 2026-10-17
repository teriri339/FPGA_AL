"""Prepare isolated TD builds and full-resolution RTL vectors; no production LUT.

The output directory must not already exist. Generated top-level parameter
overrides affect the build copy only. The supplied field is synthetic test data.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

import numpy as np
from calibrate_white_field import make_table, write_table


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--on-board", action="store_true", help="Build the button-triggered calibrator, not the synthetic static LUT")
    parser.add_argument("--soft-preset",action="store_true",help="Build the empirical fixed preset with original automatic AWB/buttons")
    parser.add_argument("--bitstream", action="store_true", help="Continue through bitgen in the isolated build")
    args = parser.parse_args()
    if args.on_board and args.soft_preset: parser.error("Choose either on-board calibration or soft preset")
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    repo = Path(__file__).resolve().parents[1]
    original = repo / "reference_edge_project"
    board = root / "reference_edge_project"
    shutil.copytree(original / "user_source", board / "user_source")
    (board / "td_project").mkdir()
    shutil.copyfile(original / "td_project/camera_to_dsi_display.sdc",
                    board / "td_project/camera_to_dsi_display.sdc")
    # Deterministic smooth chromatic shading plus a small fixed black offset.
    yy, xx = np.mgrid[0:720, 0:1280]
    field = np.stack([120+35*xx/1279+8*yy/719,
                      175-18*xx/1279+12*yy/719,
                      145+25*yy/719-8*xx/1279], axis=-1)
    pixels = np.rint(field).astype(np.uint8)
    table, summary = make_table(pixels, black=4, target=160)
    black_level=4
    if args.soft_preset:
        words=[int(s,16) for s in (original / "user_source/hdl_source/hx1p35_port/white_field_soft_preset.mem").read_text().split()]
        table=np.asarray([[(w>>24)&4095,(w>>12)&4095,w&4095] for w in words],dtype=np.uint16).reshape(9,16,3)
        summary={"empirical_preset":True,"gain_min":float(table.min()/256),"gain_max":float(table.max()/256)}
        black_level=0
    write_table(root / "verification.mem", table)
    write_table(root / "unity.mem", np.full((9,16,3), 256, dtype=np.uint16))
    ux = np.arange(1280)*15*256//1279
    uy = np.arange(720)*8*256//719
    nx = np.minimum(ux//256,14); ny = np.minimum(uy//256,7)
    fx = (ux-nx*256)[None,:,None]; fy = (uy-ny*256)[:,None,None]
    nodes = table.astype(np.int64)
    t0 = (nodes[ny[:,None],nx[None,:]]*(256-fx) +
          nodes[ny[:,None],nx[None,:]+1]*fx+128)//256
    t1 = (nodes[ny[:,None]+1,nx[None,:]]*(256-fx) +
          nodes[ny[:,None]+1,nx[None,:]+1]*fx+128)//256
    gains = (t0*(256-fy)+t1*fy+128)//256
    corrected = np.clip((np.maximum(pixels.astype(np.int64)-black_level,0)*gains+128)//256,0,255)
    # Test field plus a sharp high-contrast scene; expected pixels are calculated
    # independently in NumPy, not by calling the HDL interpolation function.
    scene = np.stack([(xx*17+yy*3)%256, ((xx//8+yy//8)%2)*255,
                      (xx*5+yy*11)%256],axis=-1).astype(np.uint8)
    scene_out = np.clip((np.maximum(scene.astype(np.int64)-black_level,0)*gains+128)//256,0,255)
    for name, source, result in [("field",pixels,corrected),("scene",scene,scene_out)]:
        src = source.astype(np.uint64)
        dst = result.astype(np.uint64)
        words = ((src[:,:,0]<<40)|(src[:,:,1]<<32)|(src[:,:,2]<<24)|
                 (dst[:,:,0]<<16)|(dst[:,:,1]<<8)|dst[:,:,2])
        np.savetxt(root / f"{name}_vectors.mem", words.reshape(-1), fmt="%012x")
    summary.update({"synthetic_only": True, "pixels_per_frame": 1280*720,
                    "input_channel_means": pixels.mean(axis=(0,1)).tolist(),
                    "input_std": float(pixels.std()),
                    "corrected_channel_means": corrected.mean(axis=(0,1)).tolist(),
                    "corrected_std": float(corrected.std()),
                    "max_target_error": int(np.max(np.abs(corrected-160)))})
    (root / "synthetic_metrics.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    # Mechanical parameter overrides in the isolated source copy only.
    top = board / "user_source/hdl_source/design_top_wrapper.v"
    text = top.read_text(encoding="utf-8")
    overrides={"WHITE_FIELD_SELF_CAL":str(int(args.on_board)),"LSC_ENABLE":"1",
               "WHITE_FIELD_SOFT_PRESET":str(int(args.soft_preset)),
               "LSC_GAIN_FILE":'""' if args.on_board or args.soft_preset else f'"{root.as_posix()}/verification.mem"',
               "LSC_BLACK_LEVEL":"0" if args.on_board or args.soft_preset else "4",
               "WHITE_FIELD_FIXED_AWB":"0" if args.soft_preset else "1"}
    for name,value in overrides.items():
        text,count=re.subn(r"(parameter\s+"+name+r"\s*=\s*)[^,\n]+",lambda m:m[1]+value,text)
        if count!=1: raise ValueError(f"Expected exactly one parameter: {name}")
    top.write_text(text,encoding="utf-8")
    # Use the CURRENT source list, including the user's exclusions, not a stale run.
    al = original / "td_project/camera_to_dsi_display.al"
    # TD run settings use non-XML double-colon names; they are not part of a PRJ.
    raw = re.sub(r"<Runs>.*?</Runs>", "", al.read_text(encoding="utf-8"), flags=re.S)
    project = ET.fromstring(re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#)","&amp;",raw))
    project.attrib.pop("Path",None)
    runs=project.find("Runs")
    if runs is not None: project.remove(runs)
    for element in project.findall(".//File"):
        source=(al.parent / element.attrib["Path"]).resolve()
        mapped=board / source.relative_to(original)
        if not mapped.exists(): raise FileNotFoundError(mapped)
        element.set("Path",mapped.as_posix())
    for run in ("syn_1","phy_1"):
        run_dir=root / run
        run_dir.mkdir()
        ET.ElementTree(project).write(run_dir / "camera_to_dsi_display.prj",encoding="utf-8",xml_declaration=True)
        baseline=original / "td_project/camera_to_dsi_display_Runs" / run
        settings=(baseline / "settings.cfg").read_text(encoding="utf-8")
        settings=settings.replace("../../../user_source/",(board / "user_source").as_posix()+"/")
        settings=settings.replace("../../camera_to_dsi_display.sdc",(board / "td_project/camera_to_dsi_display.sdc").as_posix())
        # Verification stops after routed timing; no bitstream or board programming.
        if run=="phy_1" and not args.bitstream:
            settings=settings.replace("set end_step bitgen","set end_step opt_route")
        (run_dir / "settings.cfg").write_text(settings,encoding="utf-8")
        flow=(baseline / "camera_to_dsi_display.tcl").read_text(encoding="utf-8")
        if args.bitstream:
            flow=flow.replace("  bitgen -bit $prj_name.bit", "  set_param bitgen compress on\n  bitgen -bit $prj_name.bit")
        (run_dir / "verify.tcl").write_text(flow,encoding="utf-8")
    print(json.dumps({"output":str(root),**summary},indent=2))


if __name__=="__main__":
    main()
