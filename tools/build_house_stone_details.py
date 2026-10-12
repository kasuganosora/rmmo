"""Blender: limestone oculus and compatible open door/window surrounds.
Metres; front is -Y. Existing owned scanned limestone, editable master retained.
"""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path('D:/code/rmmo_runtime');out=root/'art_sources/house_stone_details';out.mkdir(parents=True,exist_ok=True)
(out/'models').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC'
src=(Path(__file__).parent/'build_street_edge_stones.py').read_text(encoding='utf8')
exec(src[src.index('def surface('):src.index('stone=surface(')])
stone=surface('Owned scanned limestone','terrain/beach_cliff')
wood=surface('Weathered timber','wood/worn_planks')
def plain(name,c,rough=.6,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal;return m
glass=plain('Subdued old glass',(.085,.13,.145),.24,.15)
lead=plain('Dark lead cames',(.06,.058,.05),.55,.65)
groups=[];current=[];bevels=[]
def mesh(name,v,f,m,bevel=.007):
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 o=bpy.data.objects.new(name,me);sc.collection.objects.link(o);me.materials.append(m);current.append(o)
 uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  axis=max(range(3),key=lambda k:abs(p.normal[k]))
  for li in p.loop_indices:
   c=me.vertices[me.loops[li].vertex_index].co
   uv.data[li].uv=((c.x,c.y) if axis==2 else ((c.x,c.z) if axis==1 else (c.y,c.z)))
 if bevel:
  mod=o.modifiers.new('Subtle worked arris','BEVEL');mod.width=bevel;mod.segments=4;bevels.append(mod);o.modifiers.new('Planar normals','WEIGHTED_NORMAL')
 return o
def box(name,x,z,w,h,m=stone,y=0,d=.27):
 return mesh(name,[(x+sx*w/2,y+sy*d/2,z+sz*h/2) for sz in [-1,1] for sy in [-1,1] for sx in [-1,1]],[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],m)
def sector(name,r0,r1,a,b,z=0,m=stone,y=0,d=.27,steps=6,gap=0):
 pts=[]
 for r,seq in [(r0,range(steps+1)),(r1,range(steps,-1,-1))]:
  pts.extend([(r*math.cos(a+gap+(b-a-2*gap)*i/steps),z+r*math.sin(a+gap+(b-a-2*gap)*i/steps)) for i in seq])
 n=len(pts);return mesh(name,[(x,yy,zz) for yy in [y-d/2,y+d/2] for x,zz in pts],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],m,.005)
def end(key,label,offset):
 global current
 groups.append(dict(id=key,label=label,objects=current,offset=offset));current=[]
for i in range(12):sector('Radial limestone voussoir',.56,.75,i*math.tau/12,(i+1)*math.tau/12,gap=.005)
sector('Continuous inner oak rebate',.515,.56,0,math.tau,m=wood,y=.035,d=.07,steps=96)
# Separate insert. The perimeter is open in the surround, not a painted-on window.
n=96;points=[(.51*math.cos(i*math.tau/n),.51*math.sin(i*math.tau/n)) for i in range(n)]
mesh('Recessed glass insert',[(x,.077,z) for x,z in points],[tuple(range(n))],glass,0)
box('Central mullion',0,0,.046,1.04,wood,y=.033,d=.055)
box('Transom',0,0,1.04,.035,wood,y=.035,d=.047)
for x in [-.27,.27]:
 h=2*math.sqrt(.51**2-x*x);box('Slim vertical came',x,0,.012,h,lead,y=.047,d=.022)
end('gable_oculus','石砌圆形山墙窗',(-3,0,1.55))
def jambs(w,h):
 for side in [-1,1]:
  for i in range(math.ceil(h/.32)):
   count=math.ceil(h/.32);dz=h/count
   box('Jointed limestone jamb',side*(w/2+.105),(i+.5)*dz,.21,dz-.005)
def sill(w):box('Projecting stone sill',0,-.07,w+.5,.14,y=-.05,d=.39)
jambs(.95,1.35);sill(.95);box('Load-bearing stone lintel',0,1.46,1.39,.22)
end('window_square_surround','方窗石砌窗套',(0,0,.70))
jambs(1.15,1.9)
for i in range(11):sector('Door arch voussoir',.575,.795,i*math.pi/11,(i+1)*math.pi/11,z=1.9,gap=.004)
end('door_arch_surround','圆拱石砌门套',(3,0,.03))
def triangles(objects):
 dg=bpy.context.evaluated_depsgraph_get();total=0
 for o in objects:
  ev=o.evaluated_get(dg);me=ev.to_mesh();me.calc_loop_triangles();total+=len(me.loop_triangles);ev.to_mesh_clear()
 return total
for g in groups:
 for o in g['objects']:o.location=g['offset']
 g['master_triangles']=triangles(g['objects'])
floor=box('Review floor',0,-.14,14,.12,plain('Neutral floor',(.29,.31,.29)),y=0,d=8);current=[]
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True
sc.render.resolution_x=1500;sc.render.resolution_y=720;sc.render.resolution_percentage=100
sc.world.color=(.25,.25,.25);sc.view_settings.view_transform='AgX'
bpy.ops.object.light_add(type='AREA',location=(-3,-5,7));bpy.context.object.data.energy=1500;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=5
bpy.ops.object.camera_add(location=(4,-12,4.2));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=10.6;sc.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(out/'master.blend'))
sc.render.filepath=str(out/'master.png');bpy.ops.render.render(write_still=True)
for m in bevels:m.segments=2
for g in groups:g['game_triangles']=triangles(g['objects'])
sc.render.filepath=str(out/'optimized.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'optimized.blend'))
for g in groups:
 bpy.ops.object.select_all(action='DESELECT')
 copies=[]
 for o in g['objects']:
  clone=o.copy();clone.data=o.data.copy();clone.location=(0,0,0);sc.collection.objects.link(clone);clone.select_set(True);copies.append(clone)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
 joined=bpy.context.object;joined.name=g['id']
 file=out/'models'/f"{g['id']}.glb"
 bpy.ops.export_scene.gltf(filepath=str(file),use_selection=True,export_apply=True,export_format='GLB',export_extras=True)
 bpy.data.objects.remove(joined,do_unlink=True)
 g['sha256']=hashlib.sha256(file.read_bytes()).hexdigest();g.pop('objects')
(out/'manifest.json').write_text(json.dumps(dict(assets=groups,dimensions='oculus clear diameter 1.12m; square opening .95 x 1.35m; door opening 1.15m x 2.475m',sources=['https://historicengland.org.uk/listing/the-list/list-entry/1040240','https://heritagerecords.nationaltrust.org.uk/HBSMR/MonRecord.aspx?skin=printerfriendly&uid=MNA143421']),ensure_ascii=False,indent=2),encoding='utf8')
