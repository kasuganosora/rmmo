"""Non-destructive architectural PBR pass on the approved v12 guild.

Run with Blender --background --python; all output stays in review_artifacts.
No catalogue, user map, topology, collision, or door-pose changes.
"""
import argparse
import hashlib
import json
import math
import sys
import struct
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

BASE = Path('D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v12')
LIB = Path('D:/code/rmmo_runtime/packs/default/assets/materials')
OUT = Path('D:/code/rmmo/review_artifacts/axel_guild_materials_20261011')
P = argparse.ArgumentParser()
P.add_argument('--shots', default='exterior,entry,hall')
P.add_argument('--render-only', action='store_true')
P.add_argument('--repair-export', action='store_true')
ARGS = P.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
OUT.mkdir(parents=True, exist_ok=True)
source = OUT / 'axel_guild_whitebox_v13.blend'
target = OUT / 'axel_guild_materials_v1.blend'
bpy.ops.wm.open_mainfile(filepath=str(target if ARGS.render_only or ARGS.repair_export else source))
SC = bpy.context.scene


def geometry_signature():
    """Includes all objects, hierarchy, raw geometry, transforms and modifiers."""
    h = hashlib.sha256()
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        h.update(repr((o.name, o.type, o.parent.name if o.parent else '',
                       [list(row) for row in o.matrix_world])).encode())
        if o.type == 'MESH':
            h.update(repr([tuple(v.co) for v in o.data.vertices]).encode())
            h.update(repr([tuple(p.vertices) for p in o.data.polygons]).encode())
            h.update(repr([(m.name, m.type) for m in o.modifiers]).encode())
    return h.hexdigest()


def preserve_export_factors(specs):
    """Blender 4.5 drops MixRGB tint factors; preserve standard glTF PBR factors.

    This changes JSON only. Embedded source image and mesh BIN bytes are identical.
    """
    path = OUT/'axel_guild_materials_v1.glb'
    data = path.read_bytes()
    size, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20+size])
    binary_chunks = data[20+size:]
    changed = []
    for m in doc.get('materials', []):
        key = m.get('name', '').removeprefix('Guild PBR | ')
        spec = specs.get(key, {})
        pbr = m.get('pbrMetallicRoughness', {})
        if 'color' in spec and 'baseColorTexture' in pbr:
            pbr['baseColorFactor'] = list(spec['color']) + [1]
            changed.append(m['name'])
    payload = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    payload += b' ' * ((-len(payload)) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 20+len(payload)+len(binary_chunks))
    out += struct.pack('<II', len(payload), kind) + payload + binary_chunks
    path.write_bytes(out)
    assert path.read_bytes()[20+len(payload):] == binary_chunks
    return {'materials': changed, 'binary_chunk_unchanged': True,
            'reason': 'Blender 4.5 MixRGB export omits constant multiply tint; restore baseColorFactor'}


if ARGS.repair_export:
    path = OUT/'material_review.json'
    report = json.loads(path.read_text(encoding='utf-8'))
    report['export_factor_repair'] = preserve_export_factors(report['materials'])
    report['glb_sha256'] = hashlib.sha256((OUT/'axel_guild_materials_v1.glb').read_bytes()).hexdigest()
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('GUILD_EXPORT_FACTORS_REPAIRED', flush=True)
    sys.exit(0)


M = {}
SPECS = {}
IMAGES = {}


def image(path, color=False):
    path = Path(path).resolve()
    key = (str(path), color)
    if key not in IMAGES:
        im = bpy.data.images.load(str(path), check_existing=False)
        im.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
        im.pack()
        IMAGES[key] = im
    return IMAGES[key]


def material(key, color, roughness=.8, metallic=0, library=None, tile=(1, 1), strength=.4):
    m = bpy.data.materials.new('Guild PBR | ' + key)
    m.use_nodes = True
    m.diffuse_color = (*color, 1)
    nt = m.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    spec = {'color': color, 'roughness': roughness, 'metallic': metallic,
            'tile_m': tile, 'normal_strength': strength}
    if library:
        folder = LIB / library
        config = json.loads((folder / 'material.json').read_text(encoding='utf-8-sig'))
        props = config['material']
        spec['source'] = str(folder / 'material.json')
        spec['source_metadata'] = config.get('source', {})
        # Do not silently load DirectX normals as OpenGL.
        assert props.get('normal_format', 'opengl') in ('opengl', 'directx'), library
        for field, socket, is_color in [('texture_path', 'Base Color', True),
                                         ('roughness_path', 'Roughness', False),
                                         ('normal_path', 'Normal', False)]:
            if field not in props:
                continue
            im = image(folder / props[field], is_color)
            if socket == 'Normal' and props.get('normal_format') == 'directx':
                # Channel conversion only; never alter the library source image.
                converted = im.copy()
                converted.name = key + ' OpenGL normal'
                pixels = np.empty(len(im.pixels), dtype=np.float32)
                im.pixels.foreach_get(pixels)
                pixels[1::4] = 1.0 - pixels[1::4]
                converted.pixels.foreach_set(pixels)
                converted.filepath_raw = str(OUT / (key.replace(' ', '_') + '_normal_opengl.png'))
                converted.file_format = 'PNG'
                converted.save()
                converted.pack()
                im = converted
                spec['normal_conversion'] = 'DirectX to OpenGL: invert G; original source preserved'
            n = nt.nodes.new('ShaderNodeTexImage')
            n.image = im
            n.extension = 'REPEAT'
            if socket == 'Normal':
                nm = nt.nodes.new('ShaderNodeNormalMap')
                nm.inputs['Strength'].default_value = strength
                nt.links.new(n.outputs['Color'], nm.inputs['Color'])
                nt.links.new(nm.outputs['Normal'], p.inputs[socket])
            elif socket == 'Base Color' and tuple(color) != (1, 1, 1):
                # The glTF exporter recognizes multiply as baseColorFactor.
                mul = nt.nodes.new('ShaderNodeMixRGB')
                mul.blend_type = 'MULTIPLY'
                mul.inputs[0].default_value = 1
                mul.inputs[2].default_value = (*color, 1)
                nt.links.new(n.outputs['Color'], mul.inputs[1])
                nt.links.new(mul.outputs[0], p.inputs[socket])
            else:
                nt.links.new(n.outputs['Color'], p.inputs[socket])
    SPECS[key] = spec
    M[key] = m
    return m


def add_materials():
    material('exterior limestone', (1, .97, .88), library='walls/stone_tiles_facade', tile=(2, 2), strength=.45)
    material('interior stone', (.65, .70, .69), library='walls/stone_tiles_facade', tile=(2, 2), strength=.4)
    material('cut limestone trim', (.64, .60, .48), roughness=.82)
    material('terracotta', (1, 1, 1), library='roofs/terracotta_warm', tile=(1, .72), strength=.5)
    material('structural oak', (.62, .52, .41), library='wood/solid_timber', tile=(.8, 2.4), strength=.35)
    material('door oak', (.8, .65, .48), library='wood/solid_timber', tile=(.8, 2.4), strength=.3)
    material('upper planks', (.68, .57, .44), library='wood/worn_planks', tile=(2, 2), strength=.35)
    material('flagstone', (.65, .72, .74), library='paving/sandstone_floor', tile=(2.8, 2.8), strength=.3)
    material('forged iron', (.065, .071, .065), roughness=.53, metallic=.85)
    material('aged brass', (.42, .29, .11), roughness=.42, metallic=.92)
    material('roof flashing', (.14, .115, .09), roughness=.68, metallic=.8)
    material('window glass', (.075, .18, .18), roughness=.24)
    material('ivory lantern glass', (.68, .59, .38), roughness=.36)
    material('banner blue', (.025, .19, .24), roughness=.95)
    material('banner red', (.29, .032, .024), roughness=.95)
    material('banner gold', (.68, .47, .13), roughness=.9)
    material('aged bone', (.48, .43, .32), roughness=.86)
    # Existing authored textile patterns; these are project designs, not official glyphs.
    for key, name in [('tapestry', 'Guild woven wool tapestry'), ('long banner', 'Guild embroidered oxblood banner')]:
        path = BASE.parent / 'textiles_sanitary_v1/guild_furniture.blend'
        with bpy.data.libraries.load(str(path), link=False) as (data_from, data_to):
            assert name in data_from.materials, name
            data_to.materials = [name]
        M[key] = data_to.materials[0]
        SPECS[key] = {'source': str(path), 'tile_m': [1, 1], 'preserve_existing_uv': True}


def choose(o):
    name, group = o.name.lower(), o.get('semantic_group', '')
    old = o.data.materials[0].name if o.data.materials else ''
    # Whitebox prop baking merged different physical materials. Do not recolor them wholesale.
    if name.startswith('guild_'):
        return None
    if group in ('32_Furniture_L1', '41_Furniture_L0', '42_Independent_Props'):
        return None
    if group.startswith(('60_', '70_', '71_', '80_', '90_')) or not group:
        return None
    if name.startswith('guild shield banner'): return 'banner blue'
    if name.startswith('guild bird'): return 'banner gold'
    if name.startswith('banner narrow border'): return 'banner red'
    if name.startswith('banner hanging loop'): return 'banner gold'
    if name.startswith('slope cloth bay'): return 'tapestry'
    if name.startswith('round bottom long banner'): return 'long banner'
    if 'slope cloth corner tie' in name: return 'banner gold'
    if group == '44_Hanging_Landmark':
        if name.startswith('neural spine'): return 'aged bone'
        if any(w in name for w in ('cable', 'armature', 'ferrule', 'collar', 'pin', 'fixing', 'clamp')): return 'forged iron'
        if any(w in name for w in ('crossbeam', 'crossbar', 'banner suspension')): return 'structural oak'
        return 'aged bone'
    if 'lantern glass' in name: return 'ivory lantern glass'
    if 'lantern' in name: return 'aged brass'
    if 'flashing' in name: return 'roof flashing'
    if 'glass' in name or 'glazing' in old or 'daylight rooflight' in name: return 'window glass'
    if any(w in name for w in ('finial', 'handle', 'hinge strap', 'banner wall arm', 'banner suspension rod')): return 'forged iron'
    if group == '43_Entrance_Doors': return 'door oak'
    if group == '31_Doors_L1': return 'door oak'
    if group == '50_Roof' and (' roof' in name or 'canopy' in name) and 'bracket' not in name and 'light' not in name: return 'terracotta'
    if any(w in name for w in ('verge', 'rim', 'tracery', 'lintel', 'stone jamb', 'stone window', 'pilaster', 'plinth', 'capital', 'parapet cap', 'column foot', 'support foot', 'chimney cap')): return 'cut limestone trim'
    if group == '40_Reception_L0':
        return 'structural oak' if 'timber' in name else 'interior stone'
    if group == '00_Foundation': return 'flagstone'
    if group in ('20_Floor_L1', '21_Stair', '22_Rails', '23_Supports', '33_Ceilings_L1', '51_Trusses'): return 'structural oak' if group not in ('20_Floor_L1','33_Ceilings_L1') else 'upper planks'
    if group == '30_Rooms_L1': return 'interior stone'
    if any(w in name for w in ('mullion', 'transom', 'rail', 'baluster', 'bracket', 'timber', 'rooflight frame')): return 'structural oak'
    if old == 'WB inset clay': return 'forged iron'
    return 'exterior limestone'


def uv_project(o, key):
    if SPECS[key].get('preserve_existing_uv') and o.data.uv_layers:
        return
    mesh = o.data
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name='GuildMetresUV')
    coords = [v.co for v in mesh.vertices]
    ranges = [max(c[i] for c in coords)-min(c[i] for c in coords) for i in range(3)]
    long_axis = max(range(3), key=lambda i: ranges[i])
    normal_matrix = o.matrix_world.to_3x3().inverted().transposed()
    for p in mesh.polygons:
        surface = key
        n = (normal_matrix @ p.normal).normalized()
        if key == 'exterior limestone' and o.get('semantic_group') in ('10_Exterior_L0', '11_Exterior_Upper'):
            center = o.matrix_world @ p.center
            if ((center.y < .5 and n.y > .5) or (center.y > 13.5 and n.y < -.5)
                    or (center.x < .5 and n.x > .5) or (center.x > 31.5 and n.x < -.5)):
                p.material_index = 1
                surface = 'interior stone'
        if key == 'terracotta' and n.z < -.3:
            p.material_index = 1
            surface = 'structural oak'
        tile = SPECS[surface]['tile_m']
        wood = surface in ('structural oak', 'door oak', 'upper planks')
        if wood:
            axis = max(range(3), key=lambda i: abs(p.normal[i]))
            axes = [i for i in range(3) if i != axis]
            if long_axis in axes:
                axes.remove(long_axis)
                axes.append(long_axis)
            scales = o.matrix_world.to_scale()
            for li in p.loop_indices:
                co = coords[mesh.loops[li].vertex_index]
                uv.data[li].uv = (co[axes[0]]*scales[axes[0]]/tile[0], co[axes[1]]*scales[axes[1]]/tile[1])
        else:
            if surface == 'terracotta' and n.z > .3:
                # Horizontal eaves / uphill tile rows, measured along the actual slope.
                u = Vector((1,0,0)) if abs(n.y) >= abs(n.x) else Vector((0,1,0))
                v = n.cross(u).normalized()
                if v.z < 0: v = -v
            elif abs(n.z) > .7:
                u, v = Vector((1,0,0)), Vector((0,1,0))
            else:
                u = Vector((1,0,0)) if abs(n.y) >= abs(n.x) else Vector((0,1,0))
                v = Vector((0,0,1))
            for li in p.loop_indices:
                co = o.matrix_world @ coords[mesh.loops[li].vertex_index]
                uv.data[li].uv = (co.dot(u)/tile[0], co.dot(v)/tile[1])


def run_pass():
    before = geometry_signature()
    add_materials()
    changed = []
    for o in list(bpy.data.objects):
        if o.type != 'MESH': continue
        key = choose(o)
        if key is None: continue
        if o.data.users > 1: o.data = o.data.copy()
        o.data.materials.clear()
        o.data.materials.append(M[key])
        for p in o.data.polygons: p.material_index = 0
        if key == 'terracotta': o.data.materials.append(M['structural oak'])
        if key == 'exterior limestone' and o.get('semantic_group') in ('10_Exterior_L0', '11_Exterior_Upper'):
            o.data.materials.append(M['interior stone'])
        uv_project(o, key)
        o['material_pass'] = 'architecture_v1'
        o['material_role'] = key
        changed.append({'object': o.name, 'role': key})
    after = geometry_signature()
    assert before == after, 'Geometry or hierarchy changed during material assignment'
    for im in bpy.data.images:
        if im.source == 'FILE' and im.has_data: im.pack()
    report = {'source': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'geometry_before': before, 'geometry_after': after, 'geometry_unchanged': before == after,
              'assigned_meshes': len(changed), 'assignments': changed, 'materials': SPECS,
              'remaining': ['Furniture whitebox meshes need per-material restoration from existing prop masters.',
                            'Roof tile pattern is rounded rectangular; reference fish-scale tile pending.',
                            'Window stained glass detail, wear variation, final lamps and engine publication pending.'],
              'user_map_modified': False, 'published_to_editor': False}
    (OUT/'material_review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(target), compress=True)
    # Keep exact independent roots and activity semantics. Studio/context excluded as in v12.
    for c in bpy.data.collections: c.hide_viewport = False
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.data.objects:
        g = o.get('semantic_group', '')
        if not g.startswith(('70_', '71_', '80_', '90_')) and o.type not in ('LIGHT','CAMERA','FONT'):
            o.hide_set(False)
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'axel_guild_materials_v1.glb'), export_format='GLB',
                             use_selection=True, export_extras=True, export_apply=True)
    report['export_factor_repair'] = preserve_export_factors(SPECS)
    report['glb_sha256'] = hashlib.sha256((OUT/'axel_guild_materials_v1.glb').read_bytes()).hexdigest()
    (OUT/'material_review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('MATERIALS_EXPORTED', len(changed), flush=True)


if not ARGS.render_only: run_pass()

# Use the original camera/lighting for structural and material comparison.
SC.render.engine = 'CYCLES'
SC.cycles.samples = 24
SC.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for d in prefs.devices: d.use = d.type == 'OPTIX'
    SC.cycles.device = 'GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:
    SC.cycles.device = 'CPU'
SC.render.resolution_x = 1400
SC.render.resolution_y = 900
SC.render.resolution_percentage = 100
SC.render.image_settings.file_format = 'PNG'
SC.view_settings.view_transform = 'AgX'
CAM = SC.camera
shots = {
    'exterior': ((48,-43,30),(16,6,6),45),
    'entry': ((23,-15,8),(16,0,5),14),
    'hall': ((29,2.3,1.7),(7,8,3.8),0),
    'rear': ((-26,48,26),(16,7,6),45),
    'stairs': ((12.5,6.2,3.8),(6,9.9,2.5),0),
}
saved_hides = {c.name:c.hide_render for c in bpy.data.collections}
door_roots = [o for o in bpy.data.objects if o.type == 'EMPTY' and o.name.startswith('Main door hinge')]
angles = [o.rotation_euler.z for o in door_roots]
for shot in ARGS.shots.split(','):
    if shot not in shots: continue
    for c in bpy.data.collections:
        c.hide_render = c.name.startswith(('60_', '70_', '71_', '80_'))
    exterior = shot in ('exterior','entry','rear')
    for o, angle in zip(door_roots, angles): o.rotation_euler.z = 0 if exterior else angle
    for o in bpy.data.objects:
        if o.type == 'LIGHT' and o.data.type == 'AREA' and o.location.y > 0: o.hide_render = exterior
    eye, aim, ortho = shots[shot]
    CAM.location = eye
    CAM.rotation_euler = (Vector(aim)-CAM.location).to_track_quat('-Z','Y').to_euler()
    CAM.data.type = 'ORTHO' if ortho else 'PERSP'
    CAM.data.ortho_scale = ortho or 45
    CAM.data.lens = 23
    SC.render.filepath = str(OUT/(shot+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDERED', shot, flush=True)
for c in bpy.data.collections: c.hide_render = saved_hides[c.name]
for o, angle in zip(door_roots, angles): o.rotation_euler.z = angle
print('GUILD_MATERIAL_PASS_DONE', OUT, flush=True)
