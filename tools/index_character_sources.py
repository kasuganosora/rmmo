"""Read-only sprite analysis: emit crop/anchor metadata, never modify image pixels."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
import json
import numpy as np
from PIL import Image
from scipy.ndimage import label, find_objects, distance_transform_edt
from scipy.cluster.vq import kmeans2

ROOT = art_path("character_creator/source")

def index(path):
    pixels = np.asarray(Image.open(path).convert("RGBA"))
    mask = pixels[:, :, 3] > 127
    labels, _ = label(mask)
    boxes = []
    for i, sl in enumerate(find_objects(labels), 1):
        if sl is not None and np.count_nonzero(labels[sl] == i) > 1200:
            y, x = sl
            boxes.append([x.start, y.start, x.stop-x.start, y.stop-y.start])
    bottoms = np.array([b[1]+b[3] for b in boxes], dtype=float)
    seeds = np.array([.27, .54, .78, .99]) * pixels.shape[0]
    centers, groups = kmeans2(bottoms, seeds, minit="matrix")
    order = np.argsort(centers)
    rows = [[b for b, g in zip(boxes, groups) if g == group] for group in order]
    for row in rows:
        row.sort(key=lambda b: b[0])
    counts = [len(row) for row in rows]
    print(path.name, counts)
    if any(n not in [16, 17] for n in counts):
        raise ValueError(f"Review sprite component count: {path.name} {counts}")
    result = []
    for row in rows:
        # Back-left source contains one additional neutral pose after anticipation.
        if len(row) == 17:
            row = [row[i] for i in [0,1,2,3,5,6,7,8,9,10,11,12,13,14,15,16]]
        frames = []
        for pose, box in enumerate(row):
            x,y,w,h = box
            # Approximate head anchor, reviewed in the packed contact sheet.
            if pose == 11:
                head = [x + h*.24, y + h*.26]
            else:
                # For action poses the head generally remains above the hips,
                # while arms may extend the bounds horizontally.
                center = x + w*.5
                if pose in [3,4,5] and "left" in path.stem:
                    center = x + w*.65
                # Find the round head inside the upper silhouette; raised hands
                # have a smaller inscribed radius and must not move the hair.
                distance = distance_transform_edt(mask[y:y+h,x:x+w])
                limit = min(h, round(row[0][3]*.20))
                region = distance[:limit,:]
                hy,hx = np.unravel_index(np.argmax(region), region.shape)
                head = [int(x+hx),int(y+hy)]
            frames.append({"rect":box, "head":head})
        result.append(frames)
    return {"size":[pixels.shape[1],pixels.shape[0]], "rows":result}

if __name__ == "__main__":
    data = {p.stem:index(p) for p in sorted(ROOT.glob("motion_*.png"))}
    (ROOT / "motion_index.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    pixels = np.asarray(Image.open(ROOT / "chair.png").convert("RGBA"))
    h,w = pixels.shape[:2]
    rows=[]
    for row in range(4):
        cells=[]
        for col in [0,2,1,3,4,5,6,7]:
            x0,x1 = col*w//8,(col+1)*w//8
            y0,y1 = row*h//4,(row+1)*h//4
            ys,xs=np.where(pixels[y0:y1,x0:x1,3]>127)
            x,y = int(xs.min()+x0),int(ys.min()+y0)
            bw,bh=int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)
            distance=distance_transform_edt(pixels[y:y+bh,x:x+bw,3]>127)
            hy,hx=np.unravel_index(np.argmax(distance[:max(1,round(bh*.24)),:]),distance[:max(1,round(bh*.24)),:].shape)
            fy,fx=np.where(pixels[y+round(bh*.93):y+bh,x:x+bw,3]>127)
            cells.append({"rect":[x,y,bw,bh],"head":[int(x+hx),int(y+hy)],"foot_x":float(x+(fx.min()+fx.max())*.5)})
        rows.append(cells)
    (ROOT / "chair_index.json").write_text(json.dumps({"size":[w,h],"rows":rows},indent=2),encoding="utf-8")
