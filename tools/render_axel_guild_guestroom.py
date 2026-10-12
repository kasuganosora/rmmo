"""Material presentation of independent U15/U22 props. Not a measured room plan."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/guestroom_v1')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'guild_furniture.blend'))
SC=bpy.context.scene
col=bpy.data.collections.new('U15_U22 presentation');SC.collection.children.link(col)
data=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
for kind in data['assets']:
 for q in ['master','game']:
  bpy.data.collections[kind+'_'+q].hide_render=True
def place(kind,location,yaw=0):
 source=bpy.data.collections[kind+'_game'];root=next(o for o in source.objects if o.type=='EMPTY')
 nr=root.copy();col.objects.link(nr);nr.location=location;nr.rotation_euler.z=math.radians(yaw)
 for p in source.objects:
  if p==root:continue
  o=p.copy();o.data=p.data;col.objects.link(o);o.parent=nr
def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.83
 return m
wood=next(m for m in bpy.data.materials if m.name.startswith('Guild owned natural'))
stone=mat('Preview warm stone',(.32,.285,.22));mortar=mat('Preview mortar',(.18,.17,.14))
def box(name,loc,size,material,bevel=.006):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
 if bevel:
  m=o.modifiers.new('Soft edges','BEVEL');m.width=bevel;m.segments=2
 return o
for i in range(21):box('Preview floor board',(-2+i*.20,0,-.045),(.197,4.6,.09),wood,.002)
# Cutaway corner, no claim that this is the final room envelope.
for x,w in [(-1.5,1.2),(1.35,1.5)]:box('Rear mortar side',(x,2.30,1.5),(w,.10,3),mortar)
for z,h in [(.6,1.2),(2.85,.3)]:box('Rear mortar middle',(-.15,2.30,z),(1.5,.10,h),mortar)
for row in range(10):
 for k in range(10):
  x=-2.3+k*.5+(.25 if row%2 else 0);lo=max(-2.1,x-.244);hi=min(2.1,x+.244)
  intervals=[(lo,hi)]
  if 4<=row<9:intervals=[(lo,min(hi,-.90)),(max(lo,.60),hi)]
  for aa,bb in intervals:
   if bb>aa:box('Rear stone block',((aa+bb)/2,2.225,row*.30+.15),(bb-aa,.08,.286),stone,.007)
for x in [-2.1,2.1]:box('Timber upright',(x,2.11,1.5),(.13,.15,3.0),wood)
for z in [.14,1.05,2.95]:box('Timber wall rail',(0,2.11,z),(4.3,.13,.12),wood)
for x in [-.91,.61]:box('Window jamb',(x,2.12,1.95),(.10,.17,1.6),wood)
for z in [1.2,2.70]:box('Window lintel/sill',(-.15,2.10,z),(1.60,.21,.12),wood)
box('Window centre mullion',(-.15,2.085,1.95),(.04,.05,1.45),wood)
box('Window transom',(-.15,2.085,1.95),(1.5,.05,.04),wood)
for index,(a,b) in enumerate([((-.85,2.12,1.25),(.55,2.12,2.65)),((-.85,2.12,2.65),(.55,2.12,1.25))]):
 aa,bb=Vector(a),Vector(b);aa.y+=index*.006;bb.y+=index*.006;o=box('Diagonal window bar',(aa+bb)/2,(.035,.04,(bb-aa).length),wood,.002);o.rotation_euler=(bb-aa).to_track_quat('Z','Y').to_euler()
place('guest_bed',(1.15,.86,0))
place('guest_nightstand',(.17,1.83,0));place('guest_candlestick',(.17,1.83,.96))
place('guest_desk',(-1.55,1.15,0),90);place('guest_chair',(-.83,1.08,0),-90)
place('guest_low_cabinet',(-1.53,-.73,0),90)
# Independent wall lamp displayed on a small timber mount along the open left edge.
box('Sconce mounting post',(-2.13,.03,1.3),(.13,.13,2.6),wood)
place('guest_candle_sconce',(-2.01,.03,1.83),90)
cam=SC.camera;cam.location=(5.9,-8.5,5.3);target=Vector((0,.65,1.05));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=6.8
SC.render.resolution_x=1440;SC.render.resolution_y=1080;SC.cycles.samples=40
SC.render.filepath=str(OUT/'guestroom_arrangement.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guestroom_arrangement.blend'),compress=True)
bpy.ops.render.render(write_still=True)
