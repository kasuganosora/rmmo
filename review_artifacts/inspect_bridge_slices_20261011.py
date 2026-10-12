"""Read-only arrays/trace audit. Writes its own report only; no map/cache edits."""
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path("D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009")
TRACE = Path("D:/code/rmmo_runtime/review_artifacts/loading_collision_none_warm_20261011.json")
UUID = "stone_e_0be972769041dbc9"
source = json.loads((ROOT / "source_audit.json").read_text(encoding="utf-8"))
record = json.loads((ROOT / "original_record.json").read_text(encoding="utf-8"))
triangles = []
for surface in source["meshes"][1]["surfaces"]:
    slots = {}
    for slot in surface["slots"]:
        if slot["slot"] not in (0, 12):
            continue
        raw = (ROOT / slot["file"]).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == slot["sha256"]
        slots[slot["slot"]] = np.frombuffer(raw, dtype="<i4" if slot["slot"] == 12 else "<f4")
    vertices = slots[0].reshape(-1, 3)
    triangles.append(vertices[slots[12]].reshape(-1, 3))
faces = np.concatenate(triangles)
# Same Y rotation convention; diagnostic bounds use float64, not byte equality.
yaw = np.deg2rad(record["rotation"][1])
basis = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
world_faces = faces @ basis.T + np.array(record["position"])
slices = []
for start in range(0, len(faces), 3072):
    local = faces[start : start + 3072]
    world = world_faces[start : start + 3072]
    slices.append({"slice": len(slices), "vertices": len(local), "local_min": local.min(axis=0).tolist(), "local_max": local.max(axis=0).tolist(), "world_min": world.min(axis=0).tolist(), "world_max": world.max(axis=0).tolist()})
spans = np.array([np.array(row["local_max"]) - row["local_min"] for row in slices])
trace = json.loads(TRACE.read_text(encoding="utf-8"))
events = trace["monitor"]["trace"]["events"]
gates = [e for e in events if e["label"] == "entry.geometry_gate" and e.get("details", {}).get("terrain_uuid") == UUID]
publication = [e for e in events if e["label"] == "deferred.publication" and e.get("details", {}).get("uuid") == UUID]
queries = []
for x in [-25, -15, 0, 15, 25]:
    # XZ broadphase only, on bridge local centreline. AABB candidates are not contacts.
    candidates = [s["slice"] for s in slices if s["local_min"][0] <= x <= s["local_max"][0] and s["local_min"][2] <= 0 <= s["local_max"][2]]
    queries.append({"local_x": x, "local_z": 0, "xz_aabb_candidates": len(candidates)})
report = {"source_rmres_sha256": source["compact"]["rmmo_ref"]["sha256"], "source_trace": str(TRACE), "note": "Static slice bounds and historical trace; not a physics query benchmark. sync_us includes all Stream.sync work, not only set_faces.", "triangles": len(faces) // 3, "face_vertices": len(faces), "slice_count": len(slices), "slices_longer_than_30m": int(np.count_nonzero(spans[:, 0] > 30)), "local_x_span_percentiles_m": np.percentile(spans[:, 0], [0, 50, 90, 100]).tolist(), "xz_aabb_query_examples": queries, "publication": publication, "bridge_geometry_gates": gates, "slices": slices}
output = Path("review_artifacts/bridge_collision_slice_audit_20261011.json")
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({k: v for k, v in report.items() if k not in ("slices", "publication", "bridge_geometry_gates")}, ensure_ascii=False))
for gate in gates:
    row = gate["details"]
    print({k: row.get(k) for k in ("terrain_cursor", "terrain_vertices", "terrain_worker", "sync_us", "terrain_prepared_face_hits", "face_prefetch")})
