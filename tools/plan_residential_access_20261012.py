"""Read-only layout planning from the current map audit; emits a review recipe."""
import heapq
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.path import Path as PolygonPath
from matplotlib.patches import Polygon
import numpy as np

OUT = Path("D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012")
data = json.loads((OUT / "audit.json").read_text(encoding="utf8"))
old = json.loads(Path("D:/code/rmmo_runtime/review_artifacts/bridge_street_finish_20261006/plan.json").read_text(encoding="utf8"))
rear = [h["id"] for h in old["houses"] if h.get("rear")]

def rotation(yaw):
    a = math.radians(yaw)
    return np.array([[math.cos(a), math.sin(a)], [-math.sin(a), math.cos(a)]])

def rectangle(center, half, basis):
    x, z = half
    return np.array([[-x, -z], [x, -z], [x, z], [-x, z]]) @ basis.T + center

houses = []
for key, h in data["houses"].items():
    center = np.array(h["position"])[::2]
    half = np.array([h["parameters"]["width"], h["parameters"]["depth"]]) * .5
    basis = rotation(h["yaw"])
    houses.append((key, center, half, basis))

roads = []
for r in data["roads"]:
    basis = rotation(r["rotation"][1])
    for raw in r["road_mesh"]["polygons"]:
        poly = np.array(raw) * np.array(r["size"])[::2] @ basis.T + np.array(r["position"])[::2]
        if poly[:, 0].max() >= 290 and poly[:, 0].min() <= 425 and poly[:, 1].max() >= 165 and poly[:, 1].min() <= 288:
            roads.append(poly)

def overlaps(a, b):
    for poly in (a, b):
        for i in range(len(poly)):
            edge = poly[(i + 1) % len(poly)] - poly[i]
            axis = np.array([-edge[1], edge[0]])
            pa, pb = a @ axis, b @ axis
            if pa.max() <= pb.min() or pb.max() <= pa.min():
                return False
    return True

tree_candidates = {}
for uuid in ("obj_201002", "obj_201003"):
    r = next(r for r in data["records"] if r["uuid"] == uuid)
    original = np.array(r["position"])[::2]
    basis = rotation(r["rotation"][1])
    sz = np.array(r["bounds_size"])[::2] * np.array(r["size"])[::2]
    offset = (np.array(r["bounds_position"])[::2] * np.array(r["size"])[::2] + sz * .5) @ basis.T
    candidates = []
    for dx in np.arange(-30, 30.1, 1):
        for dz in np.arange(-30, 30.1, 1):
            at = original + [dx, dz]
            crown = rectangle(at + offset, sz * .5 + .35, basis)
            if any(overlaps(crown, rectangle(c, half + .55, b)) for _, c, half, b in houses):
                continue
            trunk = rectangle(at, [.7, .7], np.eye(2))
            if any(overlaps(trunk, road) for road in roads):
                continue
            candidates.append((float(np.linalg.norm(at-original)), at.tolist()))
    tree_candidates[uuid] = [at for _, at in sorted(candidates)[:16]]

step = .25
origin = np.array([300., 203.])
xs, zs = np.arange(300, 414.01, step), np.arange(203, 284.01, step)
X, Z = np.meshgrid(xs, zs)
points = np.stack((X.ravel(), Z.ravel()), axis=1)
blocked = np.zeros(len(points), dtype=bool)
for _, center, half, basis in houses:
    local = (points - center) @ basis
    blocked |= (np.abs(local) <= half + .9).all(axis=1)
# Avoid low solid props; the two conflicting trees are relocated separately.
for r in data["records"]:
    if r.get("collision") == "none" or r["uuid"] in tree_candidates:
        continue
    low = np.array(r.get("bounds_position", [0, 0, 0])) * r["size"] + r["position"]
    if low[1] > 2.1:
        continue
    sz = np.array(r.get("bounds_size", [0, 0, 0]))[::2] * np.array(r["size"])[::2]
    basis = rotation(r["rotation"][1]); center = np.array(r["position"])[::2]
    offset = np.array(r.get("bounds_position", [0, 0, 0]))[::2] * np.array(r["size"])[::2] + sz*.5
    local = (points-center) @ basis - offset
    blocked |= (np.abs(local) <= sz*.5 + .85).all(axis=1)
on_road = np.zeros(len(points), dtype=bool)
for poly in roads:
    on_road |= PolygonPath(poly).contains_points(points)
blocked = blocked.reshape(X.shape); on_road = on_road.reshape(X.shape)

def cell(p):
    return tuple(np.rint((np.array(p)-origin)/step).astype(int)[::-1])

def at(c):
    return origin + np.array(c[::-1])*step

def clear_line(a, b):
    n = max(2, math.ceil(np.linalg.norm(b-a)/(step*.3)))
    for p in np.linspace(a, b, n):
        z, x = cell(p)
        if z < 0 or x < 0 or z >= blocked.shape[0] or x >= blocked.shape[1] or blocked[z, x]:
            return False
    return True

paths = []
for key in rear:
    _, center, half, basis = next(h for h in houses if h[0] == key)
    door = center + np.array([-half[0]+1.2, -half[1]-1.4]) @ basis.T
    start = cell(door)
    if blocked[start]:
        raise ValueError(f"Door approach occupied: {key} {door}")
    queue = [(0., start)]; costs = {start: 0.}; previous = {start: None}; end = None
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != costs[node]:
            continue
        if on_road[node]:
            end = node; break
        z, x = node
        for dz, dx in ((-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)):
            n = (z+dz,x+dx)
            if n[0]<0 or n[1]<0 or n[0]>=blocked.shape[0] or n[1]>=blocked.shape[1] or blocked[n]:
                continue
            if dz and dx and (blocked[z+dz,x] or blocked[z,x+dx]):
                continue
            new = cost + math.hypot(dx,dz)
            if new < costs.get(n, math.inf):
                costs[n] = new; previous[n] = node; heapq.heappush(queue,(new,n))
    if end is None:
        raise ValueError(f"No clear access: {key}")
    nodes = []
    while end is not None:
        nodes.append(at(end)); end=previous[end]
    nodes.reverse(); nodes[0]=door
    simplified=[nodes[0]]; i=0
    while i<len(nodes)-1:
        j=len(nodes)-1
        while j>i+1 and not clear_line(nodes[i],nodes[j]):j-=1
        simplified.append(nodes[j]);i=j
    paths.append({"house":key,"width":1.4,"points":[p.tolist() for p in simplified]})

recipe = {"formal_sha256":data["sha256"],"tree_candidates":tree_candidates,"paths":paths}
(OUT/"access_recipe.json").write_text(json.dumps(recipe,indent=2),encoding="utf8")
fig, ax = plt.subplots(figsize=(14,12))
for road in roads:ax.add_patch(Polygon(road,color="#aa9b83"))
for key, center, half, basis in houses:
    ax.add_patch(Polygon(rectangle(center,half,basis),facecolor="#dddddd",edgecolor="black"))
    ax.text(*center,key[9:14],fontsize=8)
for path in paths:
    p=np.array(path["points"]);ax.plot(p[:,0],p[:,1],"r.-",linewidth=3)
for uuid,candidates in tree_candidates.items():
    ax.plot(*candidates[0],"go");ax.text(*candidates[0],uuid)
ax.set(xlim=(290,425),ylim=(165,286),aspect="equal");ax.invert_yaxis();ax.grid();fig.tight_layout();fig.savefig(OUT/"access_recipe.png")
print(json.dumps(recipe,ensure_ascii=False))
