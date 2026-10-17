"""Estimate a conservative CHROMA-ONLY preset from a supplied white-field image.

This is an empirical preview preset, NOT a camera/lens calibration. It preserves
mean channel balance and local luminance approximately; it does not learn live
scenes, change exposure, or use the green image from fixed-AWB operation.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from calibrate_white_field import write_table


def estimate(image, strength=0.85):
    # Discard the thin black frame around the supplied screenshot.
    a=np.asarray(image.convert("RGB"),dtype=np.float64)[4:-4,4:-4]
    h,w=a.shape[:2]
    nodes=np.empty((9,16,3))
    rx=max(1,round(w/30));ry=max(1,round(h/16))
    for j,y in enumerate(np.linspace(0,h-1,9)):
        for i,x in enumerate(np.linspace(0,w-1,16)):
            xx,yy=round(x),round(y)
            nodes[j,i]=np.median(a[max(0,yy-ry):min(h,yy+ry+1),max(0,xx-rx):min(w,xx+rx+1)],axis=(0,1))
    if nodes.min()<32: raise ValueError("Reference is not a usable bright field")
    # Low-frequency shading only; do not fit sensor noise or display texture.
    for axis in (0,1):
        pads=[(0,0)]*3;pads[axis]=(1,1)
        expanded=np.pad(nodes,pads,mode="edge")
        nodes=(np.take(expanded,range(nodes.shape[axis]),axis=axis)+
               2*np.take(expanded,range(1,nodes.shape[axis]+1),axis=axis)+
               np.take(expanded,range(2,nodes.shape[axis]+2),axis=axis))/4
    luminance=(nodes[...,0]*77+nodes[...,1]*150+nodes[...,2]*29)/256
    log_gain=np.log(luminance[...,None]/nodes)
    # Avoid adding a second global white-balance adjustment behind the live AWB.
    log_gain-=log_gain.mean(axis=(0,1),keepdims=True)
    gains=np.clip(np.exp(log_gain*strength),0.90,1.10)
    quantized=np.floor(gains*256+0.5).astype(np.uint16)
    return quantized,{"empirical_only":True,"strength":strength,
                      "source_rgb_means":a.mean((0,1)).tolist(),
                      "gain_min":float(quantized.min()/256),"gain_max":float(quantized.max()/256),
                      "center_node_rgb_gains":(quantized[4,8]/256).tolist(),
                      "mode":"spatial chroma only; global geometric-mean gain normalized per channel"}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image",type=Path)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--print-verilog",action="store_true")
    args=parser.parse_args()
    with Image.open(args.image) as im: table,report=estimate(im)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    write_table(args.output,table)
    report["source_sha256"]=hashlib.sha256(args.image.read_bytes()).hexdigest()
    report["source_name"]=args.image.name
    args.output.with_suffix(".json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    if args.print_verilog:
        print("    // Empirical chroma-only preset estimated from the supplied first white field.")
        print("    // Global AWB stays active; this is not a measured lens calibration.")
        print("    function [35:0] soft_preset_gain;")
        print("        input integer index;")
        print("        begin case(index)")
        for i,(r,g,b) in enumerate(table.reshape(-1,3)):
            print(f"            {i}: soft_preset_gain=36'h{int(r):03x}{int(g):03x}{int(b):03x};")
        print("            default:soft_preset_gain=36'h100100100;")
        print("        endcase end\n    endfunction")
    else: print(json.dumps(report,indent=2))


if __name__=="__main__": main()
