"""Offline source-collider binding to the approved body; no mesh alterations."""
import json
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation

assets = Path("D:/code/rmmo_runtime/assets/characters")
source = json.loads((assets / "source_hair/koikatu/body_collider_reference.json").read_text())
rig = json.loads((assets / "base/female_base_v2/female_axis_rig.json").read_text())
rests = {n["name"]: np.array(n["rest"]) for n in rig["nodes"]}
mirror = np.diag([-1., 1., 1., 1.])

def matrix(t):
    p, q, s = (t[k] for k in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale"))
    m = np.eye(4)
    m[:3, :3] = Rotation.from_quat([q[a] for a in "xyzw"]).as_matrix() @ np.diag([s[a] for a in "xyz"])
    m[:3, 3] = [p[a] for a in "xyz"]
    return m

specs = []
for item in source:
    name = item["name"]
    if name not in ("cf_hit_head", "cf_hit_neck", "cf_hit_shoulder_L", "cf_hit_shoulder_R", "cf_hit_spine03", "cf_hit_spine03_2"):
        continue
    chain = item["chain_leaf_first"]
    worlds, world = {}, np.eye(4)
    for t in reversed(chain):
        world = world @ matrix(t)
        worlds[t["name"]] = mirror @ world @ mirror
    anchor_name = next(t["name"] for t in chain if t["name"].startswith("cf_j_"))
    anchor = worlds[anchor_name]
    target = {"cf_j_head": "head", "cf_j_neck": "neck", "cf_j_spine03": "chest"}.get(anchor_name)
    if target is None:
        target = "rCollar" if anchor[0, 3] > 0 else "lCollar"
    # A uniform stature conversion is only the initial contact candidate.
    # Per-region surface coverage is assessed in the runtime capture, not assumed.
    source_height = worlds["cf_j_spine03"][1, 3]
    ratio = rests["chest"][1, 3] / source_height
    shape = item["collider"]
    center = np.array([shape["m_Center"][a] for a in "xyz"] + [1.])
    center[0] *= -1
    axis = np.zeros(3)
    axis[shape["m_Direction"]] = 1.
    half = max(0., shape["m_Height"] / 2 - shape["m_Radius"])
    endpoints = []
    frame = worlds[name]
    for sign in [-1, 1]:
        p = center.copy()
        p[:3] += sign * axis * half
        # Source and target bones have different rest axes. Preserve the
        # canonical world direction before expressing it in the target joint.
        offset = (frame @ p)[:3] - anchor[:3, 3]
        local = np.linalg.inv(rests[target][:3, :3]) @ (offset * ratio)
        endpoints.append(local.tolist())
    radius = shape["m_Radius"] * max(np.linalg.norm(frame[:3, :3], axis=0)) * ratio
    specs.append({"source": name, "bone": target, "a": endpoints[0], "b": endpoints[1], "radius": radius,
                  "inside": shape["m_Bound"] != 0, "stature_ratio": ratio})
assert len(specs) == 6
out = assets / "hair/female_base_v2/body_contacts.json"
out.write_text(json.dumps({"status": "candidate; source dimensions retargeted, surface coverage not accepted", "shapes": specs}, indent=2), encoding="utf-8")
print(json.dumps(specs, indent=2))
