"""Audit v10 roof coverage and authored access using the saved Blender master."""
import bpy,bmesh,json,hashlib,struct
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

base=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild'
out=base/'whitebox_v10'
bpy.ops.wm.open_mainfile(filepath=str(out/'axel_guild_whitebox.blend'))
deps=bpy.context.evaluated_depsgraph_get()
vs=[];fs=[];closed=[]
for o in bpy.data.objects:
    if o.type!='MESH' or o.get('semantic_group')!='50_Roof':continue
    ev=o.evaluated_get(deps);me=ev.to_mesh();start=len(vs)
    vs.extend([o.matrix_world@v.co for v in me.vertices])
    fs.extend([tuple(start+i for i in p.vertices) for p in me.polygons])
    if any(o.name.startswith(n) for n in ['Central frontage roof','Secondary gable roof','Small dormer roof','Rear dormer roof']):
        bm=bmesh.new();bm.from_mesh(me)
        closed.append({'name':o.name,'boundary_edges':sum(not e.is_manifold for e in bm.edges)})
        bm.free()
    ev.to_mesh_clear()
bvh=BVHTree.FromPolygons(vs,fs)
holes=[];samples=0
for i in range(127):
    x=.25+i*.25
    for j in range(55):
        y=.25+j*.25;samples+=1
        hit,normal,index,distance=bvh.ray_cast(Vector((x,y,30)),Vector((0,0,-1)),25)
        if hit is None:holes.append([x,y])
current=json.loads((out/'manifest.json').read_text(encoding='utf8'))
previous=json.loads((base/'whitebox_v9/manifest.json').read_text(encoding='utf8'))
raw=(out/'axel_guild_whitebox.glb').read_bytes();size=struct.unpack_from('<I',raw,12)[0]
gltf=json.loads(raw[20:20+size])
nodes=gltf['nodes'];checks={
    'roof_coverage_no_holes':not holes,
    'twenty_closed_gable_roof_halves':len(closed)==20 and not any(c['boundary_edges'] for c in closed),
    'two_balcony_hinge_roots':sum(n.get('name','').startswith('Balcony door hinge') for n in nodes)==2,
    'two_main_door_hinge_roots':sum(n.get('name','').startswith('Main door hinge') and 'mesh' not in n for n in nodes)==2,
    'no_textures':not gltf.get('images') and not gltf.get('textures'),
    'room_dimensions_unchanged':current['rooms']==previous['rooms'],
    'existing_statue_unchanged':current['fab_statue']==previous['fab_statue'],
    'export_hash_matches':hashlib.sha256(raw).hexdigest()==current['exports']['axel_guild_whitebox.glb'],
}
report=dict(checks=checks,failures=[k for k,v in checks.items() if not v],roof_samples=samples,
            roof_holes=holes,closed_roof_meshes=closed,glb_sha256=hashlib.sha256(raw).hexdigest(),
            references=['U01','U19','U20','U21'],
            caveats=['Balcony door, meeting-room access gallery and exact rear-entry position are authored interpretation.',
                     'Original v9 upper-floor/eave/ridge dimensions retained for third-person clearance.',
                     'Neutral whitebox only; no texture or runtime catalog publication.'])
(out/'exterior_geometry_review.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
if report['failures']:raise RuntimeError(str(report['failures']))
