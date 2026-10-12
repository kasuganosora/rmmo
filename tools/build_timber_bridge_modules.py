"""Original oak beam / braced rail kit. Runtime supplies shared PBR textures.
Blender -b --python this.py -- --output <external directory>
Project supplementary design; reference recorded in editor_extensions_20261012.md.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
if (output / 'timber_trestle.glb').exists():
    raise SystemExit('Refusing to overwrite an existing export; use a new candidate directory')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
materials = []
for role in ('deck', 'masonry', 'trim'):
    mat = bpy.data.materials.new('bridge_' + role)
    mat.diffuse_color = (.39, .27, .15, 1)
    materials.append(mat)
parts = []


def beam(a, b, width, depth, role=1, bevel=.015):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
    ob = bpy.context.object
    ob.dimensions = (width, depth, (b - a).length)
    ob.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(materials[role])
    if bevel:
        mod = ob.modifiers.new('Hand dressed edge', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=2)
    bpy.ops.object.mode_set(mode='OBJECT')
    parts.append(ob)
    ob.select_set(False)


def join(name):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    parts.clear()
    ob.select_set(False)


# Blender Z up, bridge runs X, deck is Z=0. No decorative solid arch blocks.
for y in (-2.8, -1.4, 0, 1.4, 2.8):
    beam((-4, y, -.6), (4, y, -.6), .42, .45)
    for end in (-1, 1):
        beam((end * 3.95, y, -2.5), (end * 2.25, y, -.75), .24, .25)
join('arch')
for y in (-2.8, 0, 2.8):
    beam((0, y, -5), (0, y, -.35), .42, .42)
beam((0, -3.35, -.6), (0, 3.35, -.6), .44, .45)
beam((0, -2.8, -3.3), (0, 2.8, -.95), .22, .24)
beam((0, 2.8, -3.3), (0, -2.8, -.95), .22, .24)
join('pier')
for y in (-2.8, 0, 2.8):
    beam((0, y, -5), (0, y, -.35), .45, .45)
beam((0, -3.4, -.5), (0, 3.4, -.5), .48, .5)
join('abutment')
# Exact module ends retain a continuous walking surface; seams are shallow grooves.
beam((-.5, 0, -.12), (.5, 0, -.12), 7, .24, role=0, bevel=0)
join('deck')
for z in (.45, 1.02):
    beam((-.5, 0, z), (.5, 0, z), .13, .16, role=2)
beam((-.5, 0, .45), (.5, 0, 1.02), .10, .12, role=2)
beam((0, 0, 0), (0, 0, 1.14), .16, .18, role=2)
join('parapet')
beam((0, 0, 0), (0, 0, 1.22), .25, .25, role=2)
join('post')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(output / 'timber_trestle.blend'))
bpy.ops.export_scene.gltf(filepath=str(output / 'timber_trestle.glb'), export_format='GLB', use_selection=True, export_yup=True, export_extras=True)
stats = {}
for ob in bpy.context.scene.objects:
    if ob.type == 'MESH':
        ob.data.calc_loop_triangles()
        stats[ob.name] = len(ob.data.loop_triangles)
report = {'source': 'Original project supplementary design', 'triangles': stats, 'sha256': hashlib.sha256((output / 'timber_trestle.glb').read_bytes()).hexdigest(), 'embedded_images': 0}
(output / 'source.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
