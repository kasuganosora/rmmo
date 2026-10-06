"""Verify extracted native hair skin references and rest bind transforms."""
import json
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation

root = Path("D:/code/rmmo_runtime/assets/characters/source_hair/koikatu")
results = []
for path in sorted(root.glob("*/source.json")):
    data = json.loads(path.read_text(encoding="utf-8"))
    objects, cache = data["objects"], {}

    def world(key):
        if key in cache:
            return cache[key]
        t = objects[key]["data"]
        q, s, p = (t[k] for k in ("m_LocalRotation", "m_LocalScale", "m_LocalPosition"))
        m = np.eye(4)
        m[:3, :3] = Rotation.from_quat([q[a] for a in "xyzw"]).as_matrix() @ np.diag([s[a] for a in "xyz"])
        m[:3, 3] = [p[a] for a in "xyz"]
        parent = t["m_Father"]["m_PathID"]
        if parent != "0":
            m = world(parent) @ m
        cache[key] = m
        return m

    transforms = {o["data"]["m_GameObject"]["m_PathID"]: key
                  for key, o in objects.items() if o["type"] == "Transform"}
    worst = 0.0
    for obj in objects.values():
        if obj["type"] != "SkinnedMeshRenderer":
            continue
        renderer = obj["data"]
        mesh = data["meshes"][renderer["m_Mesh"]["m_PathID"]]
        target = world(transforms[renderer["m_GameObject"]["m_PathID"]])
        assert len(renderer["m_Bones"]) == len(mesh["bind_poses"])
        for bone, pose in zip(renderer["m_Bones"], mesh["bind_poses"]):
            bind = np.array([[pose[f"e{i}{j}"] for j in range(4)] for i in range(4)])
            worst = max(worst, float(np.abs(world(bone["m_PathID"]) @ bind - target).max()))
        assert np.isfinite(mesh["vertices"]).all()
        assert min(min(v) for v in mesh["bone_indices"]) >= 0
        assert max(max(v) for v in mesh["bone_indices"]) < len(renderer["m_Bones"])
        assert np.max(np.abs(np.sum(mesh["bone_weights"], axis=1) - 1)) < 0.002
    results.append({"id": path.parent.name, "rest_bind_max_error": worst})
assert len(results) == 12
(root / "rig_audit.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
assert max(r["rest_bind_max_error"] for r in results) < 0.0001, results
print(f"PASS: {len(results)} prefabs; worst rest bind error {max(r['rest_bind_max_error'] for r in results):.9g}")
