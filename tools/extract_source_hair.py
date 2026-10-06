"""Read-only Koikatu hair extraction; preserve native rig/material provenance.

Run with rmmo_runtime/tools/vam_extract_env/Scripts/python.exe (UnityPy).
Outputs authoring data, NOT a runtime-ready or approved hair replacement.
"""
import argparse
import hashlib
import json
from pathlib import Path

import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler


def dump(path, data):
    # Unity path IDs are signed 64-bit. Godot JSON numbers are doubles: keeping
    # these numeric silently aliases bone/material references above 2**53.
    def exact(value, key=""):
        if key in ("m_PathID", "root") and isinstance(value, int):
            return str(value)
        if isinstance(value, dict):
            return {k: exact(v, k) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [exact(v) for v in value]
        return value
    path.write_text(json.dumps(exact(data), ensure_ascii=False), encoding="utf-8")


def extract(bundle, output, numbers):
    env = UnityPy.load(str(bundle))
    objects = {o.path_id: o for o in env.objects}
    trees = {}

    def tree(pid):
        if pid not in trees:
            trees[pid] = objects[pid].read_typetree()
        return trees[pid]

    part = bundle.stem.split("_")[2]
    wanted = {f"p_cf_hair_{part}_{n:02d}" for n in numbers}
    report = []
    for asset, ptr in sorted(env.container.items()):
        name = Path(asset).stem
        if name not in wanted:
            continue
        folder = output / name
        folder.mkdir(parents=True, exist_ok=True)
        picked = {}
        mesh_ids, material_ids, texture_ids = set(), set(), set()

        def reference(ref):
            assert ref["m_FileID"] == 0, f"External dependency: {ref}"
            return ref["m_PathID"]

        def walk(go_id):
            go = tree(go_id)
            picked[str(go_id)] = {"type": "GameObject", "data": go}
            for entry in go["m_Component"]:
                pid = reference(entry["component"])
                obj, data = objects[pid], tree(pid)
                picked[str(pid)] = {"type": obj.type.name, "data": data}
                if obj.type.name == "Transform":
                    for child in data["m_Children"]:
                        walk(reference(tree(reference(child))["m_GameObject"]))
                elif obj.type.name in ("SkinnedMeshRenderer", "MeshFilter"):
                    mesh_ids.add(reference(data["m_Mesh"]))
                if obj.type.name in ("SkinnedMeshRenderer", "MeshRenderer"):
                    material_ids.update(reference(r) for r in data["m_Materials"])

        walk(ptr.path_id)
        for item in list(picked.values()):
            if item["type"] == "SkinnedMeshRenderer":
                for ref in item["data"]["m_Bones"]:
                    assert str(reference(ref)) in picked, "Bone outside prefab"
        meshes = {}
        for pid in sorted(mesh_ids):
            mesh = objects[pid].read()
            h = MeshHandler(mesh)
            h.process()
            triangles = h.get_triangles()
            assert len(h.m_Vertices) > 0
            if h.m_BoneWeights:
                assert max(abs(sum(w) - 1) for w in h.m_BoneWeights) < 0.002
            meshes[str(pid)] = {
                "name": mesh.m_Name, "vertices": h.m_Vertices,
                "normals": h.m_Normals, "uv": h.m_UV0,
                "uv2": h.m_UV1 or [],
                "tangents": h.m_Tangents or [],
                "triangles": triangles, "bone_indices": h.m_BoneIndices,
                "bone_weights": h.m_BoneWeights,
                "bind_poses": tree(pid)["m_BindPose"],
            }
            (folder / f"{pid}.obj").write_text(mesh.export(), encoding="utf-8")
        materials = {}
        for pid in sorted(material_ids):
            mat = tree(pid)
            materials[str(pid)] = mat
            for _, value in mat["m_SavedProperties"]["m_TexEnvs"]:
                tid = reference(value["m_Texture"])
                if tid:
                    texture_ids.add(tid)
        textures = {}
        for pid in sorted(texture_ids):
            tex = objects[pid].read()
            filename = f"{pid}.png"
            tex.image.save(folder / filename)
            textures[str(pid)] = {"name": tex.m_Name, "file": filename}
        dump(folder / "source.json", {
            "schema": 1, "source": str(bundle), "asset": asset,
            "sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
            "coordinate_system": "original Unity coordinates; no fitted transforms",
            "root": ptr.path_id, "objects": picked, "meshes": meshes,
            "materials": materials, "textures": textures,
        })
        report.append({"id": name, "meshes": len(meshes),
                       "vertices": sum(len(m["vertices"]) for m in meshes.values()),
                       "transforms": sum(o["type"] == "Transform" for o in picked.values()),
                       "textures": len(textures)})
    assert {r["id"] for r in report} == wanted, "Missing requested prefab"
    return report


def extract_lighting_textures(source, output):
    """Hair gloss is assigned by ChaControl at load time, not in the prefab."""
    folder = output / "lighting"
    folder.mkdir(exist_ok=True)
    report = []
    for name in ("mt_hairgloss_00", "mt_ramp_00"):
        path = source / f"{name}.unity3d"
        textures = []
        for obj in UnityPy.load(str(path)).objects:
            if obj.type.name != "Texture2D":
                continue
            texture = obj.read()
            filename = f"{texture.m_Name}.png"
            texture.image.save(folder / filename)
            textures.append({"id": str(obj.path_id), "name": texture.m_Name,
                             "file": filename, "width": texture.m_Width, "height": texture.m_Height})
        report.append({"source": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "textures": textures})
    dump(folder / "manifest.json", report)
    list_path = source.parent / "list/characustom/00.unity3d"
    for obj in UnityPy.load(str(list_path)).objects:
        if obj.type.name != "TextAsset":
            continue
        asset = obj.read()
        if asset.m_Name not in ("mt_hairgloss_00", "mt_ramp_00"):
            continue
        raw = asset.m_Script.encode("utf-8", errors="surrogateescape") if isinstance(asset.m_Script, str) else bytes(asset.m_Script)
        (folder / f"{asset.m_Name}.msgpack").write_bytes(raw)
    dump(folder / "list_provenance.json", {"source": str(list_path), "sha256": hashlib.sha256(list_path.read_bytes()).hexdigest()})


def extract_head_reference(source, output):
    head_path = source / "bo_head_00.unity3d"
    env = UnityPy.load(str(head_path))
    mesh = next(o.read() for o in env.objects if o.type.name == "Mesh" and o.read().m_Name == "cf_O_face")
    handler = MeshHandler(mesh)
    handler.process()
    rig_path = source / "oo_base.unity3d"
    rig = UnityPy.load(str(rig_path))
    # ChaReference.RefObjKey.HairParent == 1; CreateReferenceInfo maps it to
    # cf_J_FaceUp_ty. LoadCharaFbxData parents hair there with local pose kept.
    parent = next(o.read() for o in rig.objects if o.type.name == "GameObject" and o.read().m_Name == "cf_J_FaceUp_ty")
    pointer = next(c.component for c in parent.m_Component if c.component.type.name == "Transform")
    chain = []
    while pointer.path_id:
        transform = pointer.read()
        tree = pointer.read_typetree()
        chain.append({"name": transform.m_GameObject.read().m_Name,
                      **{k: tree[k] for k in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale")}})
        pointer = transform.m_Father
    dump(output / "head_reference.json", {
        "source": str(head_path), "sha256": hashlib.sha256(head_path.read_bytes()).hexdigest(),
        "rig_source": str(rig_path), "rig_sha256": hashlib.sha256(rig_path.read_bytes()).hexdigest(),
        "mesh": mesh.m_Name, "vertices": handler.m_Vertices,
        "hair_parent_chain_leaf_first": chain,
    })
    objects = {o.path_id: o for o in rig.objects}
    transforms = {}
    for obj in rig.objects:
        if obj.type.name == "Transform":
            tree = obj.read_typetree()
            transforms[tree["m_GameObject"]["m_PathID"]] = tree
    colliders = []
    for obj in rig.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        data = obj.read_typetree()
        if not all(k in data for k in ("m_Center", "m_Radius", "m_Height", "m_Bound")):
            continue
        gid = data["m_GameObject"]["m_PathID"]
        parent_chain, t = [], transforms[gid]
        while True:
            parent_chain.append({"name": objects[t["m_GameObject"]["m_PathID"]].read().m_Name,
                                 **{k: t[k] for k in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale")}})
            pid = t["m_Father"]["m_PathID"]
            if not pid:
                break
            t = objects[pid].read_typetree()
        if parent_chain[-1]["name"] == "p_cf_body_bone":
            colliders.append({"name": objects[gid].read().m_Name, "collider": data,
                              "chain_leaf_first": parent_chain})
    dump(output / "body_collider_reference.json", colliders)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("D:/Games/Koikatu/abdata/chara"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--numbers", nargs="+", type=int, default=[1, 2, 3, 4, 5, 6])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for part in ("f", "b"):
        results += extract(args.source / f"bo_hair_{part}_00.unity3d", args.output, args.numbers)
    extract_head_reference(args.source, args.output)
    extract_lighting_textures(args.source, args.output)
    dump(args.output / "manifest.json", results)
    print(json.dumps(results, ensure_ascii=False, indent=2))
