"""Blender: derive a smooth review mesh, leaving the canonical binding topology intact."""
import bpy
import hashlib
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path

source = art_path('characters/source_models/vam_base_reference/female/base_original.blend')
target = art_path('characters/base/female_base_v2')
bpy.ops.wm.open_mainfile(filepath=str(source))
body = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
assert len(body.data.vertices) == 21556
assert len(body.data.polygons) == 21098
modifiers = [m for m in body.modifiers if m.type == 'SUBSURF']
assert len(modifiers) == 1
modifier = modifiers[0]
modifier.levels = modifier.render_levels = 1
modifier.show_viewport = modifier.show_render = True
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.context.view_layer.objects.active = body
output = target / 'female_base_v2_display.glb'
bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', use_selection=True, export_apply=True)
# Keep an editable copy with its modifier unapplied.
bpy.ops.wm.save_as_mainfile(filepath=str(target / 'female_base_v2_display.blend'))
manifest = {'source': str(source), 'subdivision': 'Catmull-Clark level 1',
            'source_vertices': 21556, 'source_polygons': 21098,
            'binding_mesh': 'female_base_v2.glb', 'display_mesh': output.name,
            'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'purpose': 'Static close-up review only; never use subdivided indices as clothing binding indices.'}
(target / 'display_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('PASS derived display mesh; original topology untouched')
