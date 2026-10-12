"""Restore authored prop PBR per face without changing approved scene geometry.

Reads existing game-quality Blender masters. Never edits runtime masters or maps.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
from axel_guild_lantern_finish import apply_lantern_finish
from mathutils import Vector
from mathutils.kdtree import KDTree

OUT = Path('D:/code/rmmo/review_artifacts/axel_guild_materials_20261011')
LIB = Path('D:/code/rmmo_runtime/art_sources/axel_guild')
P = argparse.ArgumentParser()
P.add_argument('--render-only', action='store_true')
P.add_argument('--shots', default='hall,guestroom,reception,stairs')
ARGS = P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
TARGET = OUT/'axel_guild_materials_v2.blend'
bpy.ops.wm.open_mainfile(filepath=str(TARGET if ARGS.render_only else OUT/'axel_guild_materials_v1.blend'))
SC = bpy.context.scene
original = list(bpy.data.objects)


def signature():
    h = hashlib.sha256()
    for o in sorted(original, key=lambda o:o.name):
        h.update(repr((o.name, o.type, o.parent.name if o.parent else '', [list(r) for r in o.matrix_world])).encode())
        if o.type == 'MESH':
            h.update(repr([tuple(v.co) for v in o.data.vertices]).encode())
            h.update(repr([tuple(p.vertices) for p in o.data.polygons]).encode())
            h.update(repr([(m.name,m.type) for m in o.modifiers]).encode())
    return h.hexdigest()


def points(o, root):
    # Local hierarchy avoids world-placement rounding (32m building).
    mat = o.matrix_local.copy()
    parent = o.parent
    while parent != root:
        assert parent is not None, o.name
        mat = parent.matrix_local @ mat
        parent = parent.parent
    return [mat @ v.co for v in o.data.vertices]


def face_key(vs):
    return tuple(sorted(tuple(round(x,4) for x in v) for v in vs))


loaded = {}
def source_collection(folder, kind):
    cache = (folder,kind)
    if cache in loaded:return loaded[cache]
    panel = folder == 'decorative_panel_v1'
    path = LIB/folder/('guild_decorative_panel.blend' if panel else 'guild_furniture.blend')
    name = 'Game independent panel' if panel else kind+'_game'
    with bpy.data.libraries.load(str(path), link=False) as (src,dst):
        assert name in src.collections, (folder,name)
        dst.collections = [name]
    col = dst.collections[0]
    SC.collection.children.link(col)
    col.hide_viewport = False
    col.hide_render = True
    for o in col.all_objects:
        o.animation_data_clear()
        if o.get('hinge_pivot_local'):o.rotation_euler = (0,0,0)
    bpy.context.view_layer.update()
    root = next(o for o in col.all_objects if o.type == 'EMPTY' and o.parent is None)
    faces = []
    exact = {}
    for o in col.all_objects:
        if o.type != 'MESH':continue
        vs = points(o,root)
        for poly in o.data.polygons:
            pv = [vs[i] for i in poly.vertices]
            mat = o.data.materials[poly.material_index]
            index = len(faces)
            faces.append((pv,mat))
            exact.setdefault(face_key(pv),[]).append(index)
    kd = KDTree(len(faces))
    for i,(pv,_) in enumerate(faces):kd.insert(sum(pv,Vector())/len(pv),i)
    kd.balance()
    loaded[cache] = (col,faces,exact,kd)
    return loaded[cache]


def restore():
    before = signature()
    records = []
    done = set()
    roots = [o for o in original if o.get('asset_source') and 'fab_knight' not in o.get('asset_source')]
    for root in roots:
        src = root['asset_source'].replace('\\','/')
        folder = src.split('/')[1]
        kind = Path(src).stem.removeprefix('guild_')
        col,faces,exact,kd = source_collection(folder,kind)
        restored = 0
        for obj in root.children_recursive:
            if obj.type != 'MESH':continue
            obj['material_pass'] = 'interior_v2'
            if obj.data.as_pointer() in done:continue
            done.add(obj.data.as_pointer())
            vs = points(obj,root)
            assignments = []
            for poly in obj.data.polygons:
                pv = [vs[i] for i in poly.vertices]
                candidates = exact.get(face_key(pv),[])
                if not candidates:
                    center = sum(pv,Vector())/len(pv)
                    candidates = [i for _,i,_ in kd.find_range(center,.00008)]
                matches = []
                for i in candidates:
                    sv,mat = faces[i]
                    if len(pv)==len(sv) and all(min((v-s).length for s in sv)<.00008 for v in pv):
                        matches.append(mat)
                assert matches, ('Unmatched face',root.name,obj.name,poly.index,list(poly.center))
                # Coincident faces occasionally belong to opposite sides of thin detailing.
                assert len({m.name for m in matches}) == 1, ('Ambiguous materials',obj.name,poly.index,[m.name for m in matches])
                assignments.append(matches[0])
            obj.data.materials.clear()
            slots = {}
            for poly,mat in zip(obj.data.polygons,assignments):
                if mat.name not in slots:
                    slots[mat.name] = len(slots)
                    obj.data.materials.append(mat)
                poly.material_index = slots[mat.name]
            restored += len(assignments)
        if kind=='hall_lantern':apply_lantern_finish(root.children_recursive)
        records.append({'root':root.name,'source':src,'newly_restored_faces':restored})
        print('RESTORED',root.name,restored,flush=True)
    # Approved Fab geometry retains polygon order and original UVs.
    statue_path = LIB/'fab_knight_statue_v1/source/Knight Statue.blend'
    with bpy.data.libraries.load(str(statue_path),link=False) as (src,dst):
        dst.objects = ['Knight_Statue_Sword','Sword']
    for source,label in zip(dst.objects,['Body','Sword']):
        obj = bpy.data.objects['Fab_Knight_Statue_'+label]
        assert len(obj.data.polygons)==len(source.data.polygons)
        assert all(tuple(a.vertices)==tuple(b.vertices) for a,b in zip(obj.data.polygons,source.data.polygons))
        obj.data.materials.clear()
        for mat in source.data.materials:obj.data.materials.append(mat)
        for a,b in zip(obj.data.polygons,source.data.polygons):a.material_index=b.material_index
        obj['material_pass']='interior_v2'
        records.append({'root':obj.name,'source':str(statue_path),'newly_restored_faces':len(obj.data.polygons)})
    # Remove temporary donor objects, leaving material/image datablocks used by the scene.
    for obj in list(bpy.data.objects):
        if obj not in original:bpy.data.objects.remove(obj,do_unlink=True)
    for col,*_ in loaded.values():bpy.data.collections.remove(col)
    bpy.context.view_layer.update()
    after=signature()
    assert before==after,'Geometry/placement/hierarchy changed'
    for im in bpy.data.images:
        if im.source=='FILE' and im.has_data:im.pack()
    report={'geometry_before':before,'geometry_after':after,'geometry_unchanged':True,
            'matching_tolerance_metres':.00008,'instances':records,'source':'axel_guild_materials_v1.blend',
            'user_map_modified':False,'published_to_editor':False,
            'limitations':['Existing authored PBR restored; final weathering and reference polish pending.',
                          'Scene lighting preview only; runtime candle/day-night binding not changed.']}
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),compress=True)
    for c in bpy.data.collections:c.hide_viewport=False
    bpy.ops.object.select_all(action='DESELECT')
    for o in original:
        if not o.get('semantic_group','').startswith(('70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT'):
            o.hide_set(False);o.select_set(True)
    path=OUT/'axel_guild_materials_v2.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
    # Preserve the architectural tint workaround from v1 without touching binary buffers.
    data=path.read_bytes();size,kind=struct.unpack_from('<II',data,12)
    doc=json.loads(data[20:20+size]);binary=data[20+size:]
    specs=json.loads((OUT/'material_review.json').read_text(encoding='utf8'))['materials']
    for mat in doc.get('materials',[]):
        key=mat.get('name','').removeprefix('Guild PBR | ')
        pbr=mat.get('pbrMetallicRoughness',{})
        if key in specs and 'color' in specs[key] and 'baseColorTexture' in pbr:pbr['baseColorFactor']=list(specs[key]['color'])+[1]
    payload=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
    path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),kind)+payload+binary)
    report['glb_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    report['interior_meshes']=sum(o.get('material_pass')=='interior_v2' for o in original)
    (OUT/'interior_material_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print('INTERIOR_EXPORTED',report['interior_meshes'],flush=True)


if not ARGS.render_only:restore()
SC.render.engine='CYCLES';SC.cycles.samples=24;SC.cycles.use_denoising=True
SC.render.resolution_x=1400;SC.render.resolution_y=900;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG';SC.view_settings.view_transform='AgX'
for c in bpy.data.collections:c.hide_render=c.name.startswith(('60_','70_','71_','80_'))
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=False
shots={
    'hall':((29,2.3,1.7),(7,8,3.8),23),
    'guestroom':((24.25,.95,6.20),(23.4,3.35,5.35),23),
    'reception':((27.5,4.5,2.1),(23.8,9.3,2),23),
    'stairs':((12.5,6.2,3.8),(6,9.9,2.5),23),
    'washroom':((28,9.85,6.9),(30,12,5.5),23),
}
for name in ARGS.shots.split(','):
    if name not in shots:continue
    preview_lights=[]
    if name in ('guestroom','washroom'):
        # Review lighting only, deliberately added after saving/exporting.
        # Closed guest rooms have no studio area lights inside their walls.
        configs = [((23.35,1.1,7.25),(23.7,3.3,5.3),190,2.0),
                   ((24.65,3.75,6.9),(22.5,2.5,5.6),65,1.5)] if name=='guestroom' else [((29.7,10.2,7.3),(29.5,11.5,5.3),240,2.0)]
        for eye_light,aim_light,power,size in configs:
            data=bpy.data.lights.new('Temporary interior review softbox','AREA')
            data.energy=power;data.size=size;data.color=(1,.87,.71)
            light=bpy.data.objects.new(data.name,data);SC.collection.objects.link(light)
            light.location=eye_light
            light.rotation_euler=(Vector(aim_light)-light.location).to_track_quat('-Z','Y').to_euler()
            preview_lights.append(light)
    eye,aim,lens=shots[name];cam=SC.camera;cam.location=eye
    cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='PERSP';cam.data.lens=lens
    SC.render.filepath=str(OUT/('interior_'+name+'.png'))
    bpy.ops.render.render(write_still=True)
    print('INTERIOR_RENDERED',name,flush=True)
    for light in preview_lights:bpy.data.objects.remove(light,do_unlink=True)
