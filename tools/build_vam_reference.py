"""Blender: convert the extracted original body, with loop UVs and materials."""
import bpy
import json
from pathlib import Path
from mathutils import Vector
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path

root = art_path('characters/source_models/vam_base_reference')
for gender in ['female', 'male']:
    folder = root / gender
    raw = json.loads((folder / 'original_data.json').read_text(encoding='utf-8'))
    d = raw['geometry_component']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    vertices = [(v['x'], -v['z'], v['y']) for v in d['_baseVertices']]
    faces = [p['vertices'] for p in d['_basePolyList']]
    # Source DAZ polygon order is retained; check signed volume before export.
    signed = sum(Vector(vertices[p[0]]).dot(Vector(vertices[p[i]]).cross(Vector(vertices[p[i+1]])))
                 for p in faces for i in range(1, len(p)-1)) / 6
    reverse = signed < 0
    if reverse: faces = [list(reversed(p)) for p in faces]
    mesh = bpy.data.meshes.new('OriginalBody');mesh.from_pydata(vertices, [], faces);mesh.update()
    body = bpy.data.objects.new('OriginalBody', mesh);bpy.context.collection.objects.link(body)
    body['source_geometry'] = d['geometryId']
    body['unmodified_shape'] = True
    body['rig_status'] = 'Static extraction; source axis-specific weights preserved in original_data.json'
    for name in d['_materialNames']:
        mat = bpy.data.materials.new(name);mat.diffuse_color = (.52,.52,.52,1)
        mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name='UVMap')
    for index, poly in enumerate(mesh.polygons):
        poly.material_index = d['_basePolyList'][index]['materialNum'];poly.use_smooth = True
        ids = d['_UVPolyList'][index]['vertices']
        if reverse: ids = list(reversed(ids))
        for loop, uid in zip(poly.loop_indices, ids):
            coord=d['_OrigUV'][uid];uv.data[loop].uv=(coord['x'],coord['y'])
    assert len(mesh.vertices)==21556 and len(mesh.polygons)==21098
    bpy.context.view_layer.objects.active=body;body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(folder/'base_original.glb'),export_format='GLB',use_selection=True)
    # Optional non-destructive inspection subdivision, not baked into geometry.
    modifier=body.modifiers.new('Preview subdivision (not baked)','SUBSURF');modifier.levels=1;modifier.render_levels=1
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/'base_original.blend'))
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=650;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.world=bpy.data.worlds.new('Grey studio');scene.world.use_nodes=True
    next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.12,.12,.12,1)
    for location,power,size in [((3,-4,5),450,4),((-3,-1,3),180,3),((2,4,4),400,3)]:
        light=bpy.data.lights.new('Softbox','AREA');light.energy=power;light.shape='DISK';light.size=size
        obj=bpy.data.objects.new('Softbox',light);scene.collection.objects.link(obj);obj.location=location
        obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat('-Z','Y').to_euler()
    camera_data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
    camera_data.type='ORTHO';camera_data.ortho_scale=2.2
    center=Vector((0,0,(max(v[2] for v in vertices)+min(v[2] for v in vertices))*.5))
    for label,offset in [('front',(0,-5,0)),('side',(5,0,0)),('back',(0,5,0))]:
        camera.location=center+Vector(offset);camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(folder/('review_'+label+'.png'));bpy.ops.render.render(write_still=True)
    print('PASS original body, UV and editable source:', gender)
