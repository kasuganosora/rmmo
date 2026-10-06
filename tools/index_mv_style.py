"""Read-only alpha analysis for MV-style sprite layout; outputs JSON, no image writes."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
import json
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import label, find_objects, distance_transform_edt
from scipy.cluster.vq import kmeans2

ROOT = art_path("character_creator_mv_style/source")

def index(path, count, poses=None):
    pixels=np.asarray(Image.open(path).convert("RGBA"))
    mask=pixels[:,:,3]>127
    labels,_=label(mask)
    boxes=[]
    for i,s in enumerate(find_objects(labels),1):
        if s is not None and np.count_nonzero(labels[s]==i)>600:
            y,x=s
            boxes.append([x.start,y.start,x.stop-x.start,y.stop-y.start])
    bottoms=np.array([b[1]+b[3] for b in boxes],float)
    centers,groups=kmeans2(bottoms,np.array([.27,.54,.78,.99])*pixels.shape[0],minit="matrix")
    rows=[sorted([b for b,g in zip(boxes,groups) if g==group],key=lambda b:b[0]) for group in np.argsort(centers)]
    print(path.name,[len(row) for row in rows])
    assert all(len(row)==count for row in rows), "Unexpected sprite count; inspect image before packing"
    records=[]
    for row in rows:
        if poses is not None:
            row=[row[i] for i in poses]
        frames=[]
        for pose,box in enumerate(row):
            x,y,w,h=box
            dist=distance_transform_edt(mask[y:y+h,x:x+w])
            limit=h if poses is not None and pose==11 else max(1,round(h*.49))
            hy,hx=np.unravel_index(np.argmax(dist[:limit]),dist[:limit].shape)
            frame={"rect":box,"head":[int(x+hx),int(y+hy)],"head_radius":float(dist[hy,hx])}
            if poses is not None:
                rgb=pixels[y:y+h,x:x+w,:3].astype(float)/255
                hi=rgb.max(axis=2);lo=rgb.min(axis=2)
                gray=(hi-lo<.13)&(hi>.25)&(hi<.75)&mask[y:y+h,x:x+w]
                if pose!=11:gray[:min(h,hy+int(dist[hy,hx])),:]=False
                ys,xs=np.where(gray)
                if len(xs):frame["waist"]=[int(x+np.median(xs)),int(y+np.quantile(ys,.15))]
                else:frame["waist"]=[int(x+w/2),int(y+h*.73)]
            frames.append(frame)
        records.append(frames)
    return {"size":[pixels.shape[1],pixels.shape[0]],"rows":records}

data={"standing":index(ROOT/"body_standing.png",8)}
data["parts"]={}
for path in list(ROOT.glob("hair_*.png"))+list(ROOT.glob("standing_*.png")):
    pix=np.asarray(Image.open(path).convert("RGBA")); mask=pix[:,:,3]>127
    labels,_=label(mask); boxes=[]
    for i,s in enumerate(find_objects(labels),1):
        if s is not None and np.count_nonzero(labels[s]==i)>100:
            y,x=s; boxes.append([x.start,y.start,x.stop,y.stop])
    centers=np.array([[(b[0]+b[2])/2,(b[1]+b[3])/2] for b in boxes])
    cy,gy=kmeans2(centers[:,1],np.array([.18,.42,.66,.89])*pix.shape[0],minit="matrix")
    cx,gx=kmeans2(centers[:,0],(np.arange(8)+.5)*pix.shape[1]/8,minit="matrix")
    rows=[]
    for ry in np.argsort(cy):
        cells=[]
        for rx in np.argsort(cx):
            group=np.array([b for b,x,y in zip(boxes,gx,gy) if x==rx and y==ry])
            assert len(group)>0,(path,rx,ry)
            x0,y0=group[:,:2].min(axis=0);x1,y1=group[:,2:].max(axis=0)
            cells.append([int(x0),int(y0),int(x1-x0),int(y1-y0)])
        rows.append(cells)
    data["parts"][path.stem]={"size":[pix.shape[1],pix.shape[0]],"rows":rows}
for path in ([] if "--static" in sys.argv else ROOT.glob("motion_*.png")):
    direction=path.stem.removeprefix("motion_")
    poses=([0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16] if direction=="front" else
           [0,1,2,3,4,5,6,7,9,10,11,12,13,15,16,17] if direction=="back" else
           [0,1,2,3,4,5,6,7,9,10,11,12,13,14,15,16])
    data[path.stem]=index(path,18 if direction=="back" else 17,poses)
    data[path.stem]["source_poses"]=poses
(ROOT/"layout.json").write_text(json.dumps(data,indent=2),encoding="utf-8")

# Equipment uses the body atlas as registration grid. Read alpha only; no raster edits.
for path in ROOT.glob("equipment_*.png"):
    direction,category=path.stem.removeprefix("equipment_").rsplit("_",1)
    key="motion_"+direction
    if key not in data:continue
    pix=np.asarray(Image.open(path).convert("RGBA"));mask=pix[:,:,3]>127
    body=data[key];bw,bh=body["size"];h,w=mask.shape
    raw=index(ROOT/(key+".png"),18 if direction=="back" else 17)
    rows=[]
    for t,row in enumerate(raw["rows"]):
        cells=[]
        ymin=0 if t==0 else (max(r["rect"][1]+r["rect"][3] for r in raw["rows"][t-1])+min(r["rect"][1] for r in row))/2
        ymax=bh if t==3 else (max(r["rect"][1]+r["rect"][3] for r in row)+min(r["rect"][1] for r in raw["rows"][t+1]))/2
        for i in body["source_poses"]:
            r=row[i]["rect"]
            xmin=0 if i==0 else (row[i-1]["rect"][0]+row[i-1]["rect"][2]+r[0])/2
            xmax=bw if i==len(row)-1 else (r[0]+r[2]+row[i+1]["rect"][0])/2
            x0,x1=round(xmin*w/bw),round(xmax*w/bw);y0,y1=round(ymin*h/bh),round(ymax*h/bh)
            ys,xs=np.where(mask[y0:y1,x0:x1])
            assert len(xs),(path,t,i)
            cells.append([int(x0+xs.min()),int(y0+ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)])
        rows.append(cells)
    data[path.stem]={"size":[w,h],"rows":rows}
(ROOT/"layout.json").write_text(json.dumps(data,indent=2),encoding="utf-8")
