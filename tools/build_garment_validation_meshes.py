"""Blender: lossless garment topology import with review PBR materials (not cloth simulation)."""
import bpy
import argparse
import colorsys
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path

root = art_path('characters/source_models/garment_validation_set')
parser = argparse.ArgumentParser()
parser.add_argument('--only', help='Build one catalog group, leaving other exports unchanged')
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
for folder in sorted(root.glob('*/item_*')):
    if args.only and folder.parent.name != args.only: continue
    data = json.loads((folder / 'clothing_data.json').read_text(encoding='utf-8'))
    config = json.loads(next(folder.glob('*.vaj')).read_text(encoding='utf-8-sig'))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new('OriginalGarment')
    # Unity/DAZ clockwise faces -> Blender counterclockwise, same axes as body importer.
    mesh.from_pydata([(x, -z, y) for x, y, z in data['vertices']], [],
                     [list(reversed(f['vertices'])) for f in data['faces']])
    mesh.update()
    body = bpy.data.objects.new(folder.parent.name + '_' + folder.name, mesh)
    bpy.context.collection.objects.link(body)
    body['status'] = 'Original static garment; wrap and simulation not evaluated'
    uv = mesh.uv_layers.new(name='UVMap')
    for polygon, face, uvface in zip(mesh.polygons, data['faces'], data['uv_faces']):
        polygon.material_index = face['material']; polygon.use_smooth = True
        for loop, index in zip(polygon.loop_indices, reversed(uvface['vertices'])):
            uv.data[loop].uv = data['uv'][index]
    for name in data['materials']:
        material = bpy.data.materials.new(name); material.use_nodes = True
        material.use_backface_culling = False
        mesh.materials.append(material)
        settings = next((s for s in config['storables'] if s['id'].endswith('Material' + name)), {})
        nodes = material.node_tree.nodes; links = material.node_tree.links
        principled = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        color = settings.get('Diffuse Color', {'h': 0, 's': 0, 'v': .8})
        rgb = colorsys.hsv_to_rgb(*(float(color[k]) for k in ['h', 's', 'v']))
        principled.inputs['Base Color'].default_value = (*rgb, 1)
        principled.inputs['Roughness'].default_value = .65
        def texture(key, color_space):
            filename = settings.get(key)
            if not filename: return None
            path = folder / filename
            if not path.is_file(): raise FileNotFoundError(path)
            image = bpy.data.images.load(str(path), check_existing=False)
            image.colorspace_settings.name = color_space
            node = nodes.new('ShaderNodeTexImage'); node.image = image
            return node
        diffuse = texture('customTexture_MainTex', 'sRGB')
        if diffuse: links.new(diffuse.outputs['Color'], principled.inputs['Base Color'])
        normal = texture('customTexture_BumpMap', 'Non-Color')
        if normal:
            # Some source "Bump" maps are scalar height, not tangent-space normal maps.
            pixels = normal.image.pixels
            step = max(1, (len(pixels)//4)//64)
            samples = [pixels[i*4:i*4+3] for i in range(0, len(pixels)//4, step)]
            is_normal = sum(p[2] > p[0] + .1 and p[2] > p[1] + .1 for p in samples) > len(samples)/2
            if is_normal:
                node = nodes.new('ShaderNodeNormalMap');node.inputs['Strength'].default_value = .5
                links.new(normal.outputs['Color'], node.inputs['Color'])
            else:
                node = nodes.new('ShaderNodeBump');node.inputs['Distance'].default_value = .001
                links.new(normal.outputs['Color'], node.inputs['Height'])
            links.new(node.outputs['Normal'], principled.inputs['Normal'])
        alpha = texture('customTexture_AlphaTex', 'Non-Color')
        if alpha:
            links.new(alpha.outputs['Color'], principled.inputs['Alpha'])
            material.surface_render_method = 'DITHERED'
        # Full original gloss/spec/decal/simulation settings remain in the source VAJ.
    assert len(mesh.vertices) == len(data['vertices']) and len(mesh.polygons) == len(data['faces'])
    bpy.context.view_layer.objects.active = body;body.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(folder / 'garment_original.blend'))
    bpy.ops.export_scene.gltf(filepath=str(folder / 'garment_review.glb'), export_format='GLB', use_selection=True)
    print('PASS preserved mesh/UV/material slots:', folder.parent.name, folder.name)
