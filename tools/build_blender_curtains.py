"""Blender 4.5 background authoring: continuous gathered linen with a rod pocket.

Run: blender --background --factory-startup --python tools/build_blender_curtains.py
The editable blend retains subdivision and a 1.2 mm Solidify modifier. Runtime
uses the smooth, two-sided 126-triangle cloth skin to stay inside face painting
limits. Coordinates exported in Godot axes, metres at the reference dimensions.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / "rmmo_runtime/art_sources/linen_curtain"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
W, H, D = .44, 1.8, .16
NX = 9
# A continuous pocket wraps behind, over, and in front of the 45 mm square rod.
ROWS = ["back", "top_back", "top_front", "bottom_front", .06, .42, .74, 1.0]
verts, uv, quads = [], [], []
for j, row in enumerate(ROWS):
    for i in range(NX + 1):
        u = i / NX
        if isinstance(row, str):
            x = (u - .5) * W * .76
            y = H / 2 + (-.032 if row in ("back", "bottom_front") else .029)
            z = .030 if row in ("top_front", "bottom_front") else -.030
            v = 0
        else:
            v = row
            fullness = .76 + .24 * math.sin(v * math.pi / 2)
            x = (u - .5) * W * fullness + .019 * math.sin(v * math.pi)
            phase = u * math.tau * 2.1 + .30 * math.sin(v * math.pi)
            # Asymmetric folds grow and relax down the hanging cloth.
            z = .035 * math.sin(phase) * (.65 + .35 * v)
            z += .010 * math.sin(u * math.pi + v * 3.2)
            y = H / 2 - v * H
            y -= (.022 * math.sin(u * math.pi) + .012 * math.sin(phase)) * v * v
        # Blender Z up; positive Blender -Y is the front of the curtain.
        verts.append((x, -z, y))
        uv.append((u * W / .25, (j / (len(ROWS) - 1)) * H / .25))
for j in range(len(ROWS) - 1):
    for i in range(NX):
        a = j * (NX + 1) + i
        quads.append((a, a + NX + 1, a + NX + 2, a + 1))
mesh = bpy.data.meshes.new("LinenPocket_continuous_126_triangles")
mesh.from_pydata(verts, [], quads)
mesh.update()
layer = mesh.uv_layers.new(name="Linen_25cm")
for poly in mesh.polygons:
    poly.use_smooth = True
    for loop in poly.loop_indices:
        layer.data[loop].uv = uv[mesh.loops[loop].vertex_index]
obj = bpy.data.objects.new("Curtain_editable_continuous_cloth", mesh)
bpy.context.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
sub = obj.modifiers.new("Optional smooth authoring high mesh", "SUBSURF")
sub.levels = sub.render_levels = 2
solid = obj.modifiers.new("Linen thickness 1.2mm", "SOLIDIFY")
solid.thickness = .0012
solid.offset = 0
mat = bpy.data.materials.new("Ivory woven flax")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (.78, .73, .62, 1)
bsdf.inputs["Roughness"].default_value = 1
bsdf.inputs["Sheen Weight"].default_value = .18
tex = Path("D:/code/rmmo_runtime/packs/default/assets/materials/details/linen_curtain/linen_v2.png")
if tex.exists():
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(str(tex))
    node.image.pack()
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
mesh.materials.append(mat)
mesh.calc_loop_triangles()
data = {
    "generator": "Blender 4.5 / tools/build_blender_curtains.py",
    "reference_size": [W, H, D],
    "triangles": [], "vertices": [], "uv": uv,
    "note": "Continuous double-sided runtime skin; editable blend includes 1.2mm solidify and subdivision. Top pocket wraps 45mm rod. UV repeats every .25m."
}
for vertex in mesh.vertices:
    data["vertices"].append([round(vertex.co.x, 7), round(vertex.co.z, 7), round(-vertex.co.y, 7)])
for tri in mesh.loop_triangles:
    # Blender CCW -> Godot clockwise after the proper rotation into Y up.
    data["triangles"].append(list(reversed(list(tri.vertices))))
assert len(data["triangles"]) == 126
(OUT / "linen_pocket_mesh.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
(ROOT / "scripts/world3d/linen_curtain_data.gd").write_text("extends RefCounted\n## Blender-authored CPU mesh; regenerate with tools/build_blender_curtains.py.\nconst DATA = " + json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
obj["runtime_export"] = "linen_pocket_mesh.json (126 triangles, two sided)"
obj["reference_dimensions_metres"] = [W, H, D]
obj["reference"] = "V&A textiles collection: woven linen construction; dimensions adjusted for the existing 45mm curtain rod."
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "linen_pocket.blend"))
print("BLENDER_CURTAIN_EXPORT", len(data["vertices"]), len(data["triangles"]))
