"""Refine an ALREADY APPLIED LUT using photographed output white fields.

Fit only broad chromatic shading. Reject clipped pixels, known dust/edge ROIs,
retain illumination gradients, and compose the residual with the old LUT.
This is an output-domain estimate, not RAW-domain lens calibration.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from calibrate_white_field import write_table


def read_table(path):
    words=[int(s,16) for s in path.read_text().split()]
    return np.array([[(w>>24)&4095,(w>>12)&4095,w&4095] for w in words],dtype=np.int64).reshape(9,16,3)


def basis(x,y):
    return np.stack([x**i*y**j for i in range(7) for j in range(7-i)],axis=-1)


def fit(a,values):
    weights=np.ones(len(a))
    for _ in range(12):
        coef=np.linalg.lstsq(a*weights[:,None]**.5,values*weights[:,None]**.5,rcond=None)[0]
        residual=np.linalg.norm(values-a@coef,axis=1)
        scale=max(.002,float(np.median(np.abs(residual-np.median(residual))))*1.4826)
        weights=np.minimum(1,2.5*scale/np.maximum(residual,1e-8))
    return coef


def samples(path):
    with Image.open(path) as im: image=np.asarray(im.convert("RGB"),dtype=np.float64)
    h,w=image.shape[:2]
    coords=[]; colors=[]
    for j in range(27):
        for i in range(48):
            x=(i+.5)/48;y=(j+.5)/27
            # Fixed dark marks in the two supplied fields, and the paper corner.
            if ((x-.245)/.055)**2+((y-.445)/.075)**2<1: continue
            if ((x-.579)/.05)**2+((y-.13)/.07)**2<1: continue
            if x>.90 and y>.78: continue
            patch=image[max(4,int(j*h/27)):min(h-4,int((j+1)*h/27)),
                        max(4,int(i*w/48)):min(w-4,int((i+1)*w/48))].reshape(-1,3)
            valid=(patch.min(axis=1)>40)&(patch.max(axis=1)<245)
            if valid.sum()<max(40,len(patch)*.3): continue
            coords.append([x,y]);colors.append(np.median(patch[valid],axis=0))
    return np.asarray(coords),np.asarray(colors)


def residual_gains(log_ratios):
    red=np.exp(log_ratios[...,0]);blue=np.exp(log_ratios[...,1])
    level=(77*red+150+29*blue)/256
    return np.stack([level/red,level,level/blue],axis=-1)


def interpolate(table,coords):
    x=coords[:,0]*15;y=coords[:,1]*8
    ix=np.minimum(x.astype(int),14);iy=np.minimum(y.astype(int),7)
    fx=(x-ix)[:,None];fy=(y-iy)[:,None]
    return (((1-fx)*table[iy,ix]+fx*table[iy,ix+1])*(1-fy)+
            ((1-fx)*table[iy+1,ix]+fx*table[iy+1,ix+1])*fy)/256


def neutral_error(rgb):
    return (rgb.max(axis=-1)-rgb.min(axis=-1))/rgb.mean(axis=-1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("photos",nargs=2,type=Path)
    parser.add_argument("--baseline",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--print-verilog",action="store_true")
    args=parser.parse_args()
    old=read_table(args.baseline)
    sets=[samples(path) for path in args.photos]
    matrices=[basis(xy[:,0]*2-1,xy[:,1]*2-1) for xy,_ in sets]
    values=[np.log(rgb[:,[0,2]]/rgb[:,1,None]) for _,rgb in sets]
    separate=[fit(a,b) for a,b in zip(matrices,values)]
    # Share the spatial model, but account for per-photo global AWB drift.
    a=np.concatenate([np.column_stack([matrices[0],np.zeros(len(matrices[0]))]),
                      np.column_stack([matrices[1],np.ones(len(matrices[1]))])])
    coef=fit(a,np.concatenate(values))
    shared=coef[:-1].copy();shared[0]+=coef[-1]/2
    yy,xx=np.mgrid[0:9,0:16]
    design=basis(xx/15*2-1,yy/8*2-1)
    residual=residual_gains(design@shared)
    proposed=old/256*residual
    if proposed.min()<.75 or proposed.max()>1.35:
        raise ValueError("Required correction outside bounded [0.75,1.35]; no table written")
    new=np.floor(proposed*256+.5).astype(np.uint16)
    validation=[]
    for i,((coords,rgb),mat) in enumerate(zip(sets,matrices)):
        ratio=interpolate(new,coords)/interpolate(old,coords)
        predicted=rgb*ratio
        held_out=rgb*residual_gains(mat@separate[1-i])
        before=neutral_error(rgb);after=neutral_error(predicted);cross=neutral_error(held_out)
        validation.append({"name":args.photos[i].name,"samples":len(coords),
                           "before_median_channel_spread":float(np.median(before)),
                           "predicted_median_channel_spread":float(np.median(after)),
                           "predicted_p95_channel_spread":float(np.percentile(after,95)),
                           "held_out_median_channel_spread":float(np.median(cross)),
                           "held_out_p95_channel_spread":float(np.percentile(cross,95))})
        central=(coords[:,0]>.4)&(coords[:,0]<.6)&(coords[:,1]>.25)&(coords[:,1]<.75)
        validation[-1].update({"central_sample_rgb_before":rgb[central].mean(axis=0).tolist(),
                               "central_sample_rgb_predicted":predicted[central].mean(axis=0).tolist()})
        if np.median(after)>.6*np.median(before) or np.percentile(cross,95)>.08:
            raise ValueError(f"Reference cross-check failed: {validation[-1]}")
    report={"mode":"two-output-frame residual chroma refinement; composed with already applied LUT",
            "baseline_sha256":hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
            "source_sha256":[hashlib.sha256(p.read_bytes()).hexdigest() for p in args.photos],
            "gain_min":float(new.min()/256),"gain_max":float(new.max()/256),
            "center_rgb_gains":(new[4,8]/256).tolist(),
            "inter_photo_log_chroma_offset":coef[-1].tolist(),"validation":validation,
            "no_hardware_verification":True,"illumination_flattening":False}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    write_table(args.output,new)
    args.output.with_suffix(".json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    if args.print_verilog:
        print("    // Residual chroma fitted from the two supplied output white-paper frames.")
        print("    // Composed with the LUT already applied to those frames; AWB remains active.")
        print("    function [35:0] soft_preset_gain;\n        input integer index;\n        begin case(index)")
        for i,(r,g,b) in enumerate(new.reshape(-1,3)):
            print(f"            {i}: soft_preset_gain=36'h{int(r):03x}{int(g):03x}{int(b):03x};")
        print("            default:soft_preset_gain=36'h100100100;\n        endcase end\n    endfunction")
    else: print(json.dumps(report,indent=2))


if __name__=="__main__": main()
