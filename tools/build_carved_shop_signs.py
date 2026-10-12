"""Blender: modular no-text trade signs. Shared board origin and hanging sockets."""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'art_sources/mmorpg_shop_signs/carved_20261007';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC';assets=[];allmods=[]
def mat(name,c,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=.72;b.inputs['Metallic'].default_value=metal;return m
iron=mat('Forged dark iron',(.034,.030,.025),.7);gold=mat('Aged warm brass',(.52,.32,.09),.6)
cream=mat('Ivory mineral paint',(.78,.67,.43));red=mat('Vermilion mineral paint',(.43,.045,.02));blue=mat('Blue mineral paint',(.025,.16,.30));green=mat('Green mineral paint',(.045,.23,.10));leather=mat('Ochre paint',(.37,.16,.045));silver=mat('Pale pewter',(.46,.51,.50),.5)
wood=mat('Owned solid timber',(.16,.075,.03));nt=wood.node_tree;b=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
for f,s in [('texture.png','Base Color'),('normal.png','Normal'),('roughness.png','Roughness')]:
 t=nt.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(ROOT/'packs/default/assets/materials/wood/solid_timber'/f));t.image.pack()
 if s!='Base Color':t.image.colorspace_settings.name='Non-Color'
 if s=='Normal':
  n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.22;nt.links.new(t.outputs[0],n.inputs['Color']);nt.links.new(n.outputs[0],b.inputs[s])
 elif s=='Roughness':
  n=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(t.outputs[0],n.inputs[0]);nt.links.new(n.outputs['Red'],b.inputs[s])
 else:nt.links.new(t.outputs[0],b.inputs[s])
current=[]
def poly(name,points,material,y=-.053,depth=.014,bevel=.004):
 y-=len(current)*.0003
 n=len(points);v=[(x,yy,z) for yy in [y,y+depth] for x,z in points];f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update();o=bpy.data.objects.new(name,me);sc.collection.objects.link(o);me.materials.append(material);current.append(o)
 uv=me.uv_layers.new(name='UVMap')
 for loop in me.loops:
  c=me.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(c.x+.5,c.z+.5)
 if bevel:
  m=o.modifiers.new('Soft worked edge','BEVEL');m.width=bevel;m.segments=3;allmods.append(m);o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
 return o
def rect(x,z,w,h,m=cream,y=-.055):return poly('Pictogram',[(x-w/2,z-h/2),(x+w/2,z-h/2),(x+w/2,z+h/2),(x-w/2,z+h/2)],m,y)
def disk(x,z,rx,rz=None,m=cream,y=-.055):return poly('Pictogram',[(x+rx*math.cos(i*math.tau/40),z+(rz or rx)*math.sin(i*math.tau/40)) for i in range(40)],m,y)
def line(points,m=cream,width=.014,y=-.066,name='Pictogram stroke'):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=2;cu.bevel_depth=width;cu.bevel_resolution=3;cu.use_fill_caps=True
 closed=len(points)>2 and math.dist(points[0],points[-1])<1e-6
 if closed:points=points[:-1]
 sp=cu.splines.new('POLY');sp.use_cyclic_u=closed;sp.points.add(len(points)-1)
 for p,(x,z) in zip(sp.points,points):p.co=(x,y,z,1)
 o=bpy.data.objects.new(name,cu);sc.collection.objects.link(o);cu.materials.append(m);current.append(o);return o
def circle(x,z,r,m=gold,width=.015,y=-.075):return line([(x+r*math.cos(i*math.tau/48),z+r*math.sin(i*math.tau/48)) for i in range(49)],m,width,y)
def sword(angle=0):
 start=len(current);poly('Sword blade',[(-.035,-.10),(.035,-.10),(.035,.22),(0,.31),(-.035,.22)],silver);rect(0,-.13,.24,.045,gold);rect(0,-.22,.045,.14,leather);disk(0,-.30,.038,m=gold)
 for o in current[start:]:o.rotation_euler.y=angle
def icon(kind):
 if kind=='weapons':sword(-.55);sword(.55)
 elif kind=='armor':
  poly('Breastplate',[(-.22,.22),(-.11,.29),(-.07,.20),(.07,.20),(.11,.29),(.22,.22),(.15,.08),(.15,-.20),(0,-.27),(-.15,-.20),(-.15,.08)],silver);line([(0,.16),(0,-.20)],gold,.016)
 elif kind=='smith':
  poly('Anvil',[(-.29,.05),(-.30,.14),(.28,.14),(.20,.02),(.10,0),(.07,-.17),(.20,-.22),(.20,-.28),(-.20,-.28),(-.20,-.22),(-.07,-.17),(-.10,.02)],silver);line([(-.12,.20),(.16,.35)],leather,.026);rect(.10,.31,.21,.095,gold)
 elif kind=='tailor':
  circle(-.14,-.19,.07,cream,.025);circle(.14,-.19,.07,cream,.025);line([(-.10,-.14),(.20,.28)],silver,.028);line([(.10,-.14),(-.20,.28)],silver,.028);disk(0,0,.032,m=gold,y=-.095)
 elif kind=='leather':
  poly('Boot',[(-.17,.28),(.06,.28),(.05,-.05),(.22,-.14),(.27,-.24),(-.20,-.24)],leather);line([(-.20,-.25),(.28,-.25)],cream,.026);line([(-.14,.22),(.03,.22)],cream,.015)
 elif kind=='potion':
  poly('Potion bottle',[(-.06,.28),(.06,.28),(.06,.12),(.20,-.08),(.17,-.27),(-.17,-.27),(-.20,-.08),(-.06,.12)],blue);rect(0,.29,.17,.06,leather);disk(0,-.10,.11,.09,green,y=-.078);line([(-.10,-.03),(-.12,-.14)],cream,.016,y=-.097)
 elif kind=='magic':
  line([(-.16,-.29),(.12,.17)],leather,.026);poly('Crystal',[(.12,.32),(.22,.19),(.12,.07),(.02,.19)],blue);line([(.12,.29),(.12,.10)],cream,.012);line([(-.22,.17),(-.22,.31)],gold,.012);line([(-.29,.24),(-.15,.24)],gold,.012)
 elif kind=='scroll':
  poly('Blank parchment',[(-.20,-.23),(.18,-.23),(.18,.24),(-.20,.24)],cream);line([(-.24,.24),(.24,.24)],gold,.034);line([(-.24,-.23),(.24,-.23)],gold,.034);disk(.08,-.07,.060,m=red,y=-.082);poly('Seal tails',[(.04,-.09),(.03,-.22),(.08,-.18),(.13,-.22),(.12,-.09)],red,y=-.081)
 elif kind=='jewelry':
  circle(0,-.08,.17,gold,.043);poly('Cut gem',[(-.13,.17),(-.075,.27),(.075,.27),(.13,.17),(0,.04)],blue,y=-.087);line([(-.12,.17),(.12,.17)],cream,.009,y=-.104)
 elif kind=='general':
  poly('Travel satchel',[(-.23,-.22),(.23,-.22),(.23,.16),(-.23,.16)],leather);line([(-.09,.17),(-.09,.28),(.09,.28),(.09,.17)],cream,.022);poly('Bag flap',[(-.23,.16),(.23,.16),(.16,.00),(-.16,.00)],cream,y=-.083);rect(0,-.02,.065,.085,gold,y=-.102)
 elif kind=='inn':
  rect(0,-.09,.50,.13,cream);rect(-.24,-.10,.055,.35,leather);rect(.24,-.16,.055,.23,leather);rect(.06,-.01,.31,.15,blue);disk(-.14,.04,.08,.043,cream);circle(.16,.27,.07,gold,.013)
 elif kind=='tavern':
  line([(.15,.16),(.28,.16),(.28,-.08),(.16,-.10)],gold,.032);poly('Tankard',[(-.19,.18),(.16,.18),(.14,-.23),(-.17,-.23)],gold);line([(-.10,.09),(-.09,-.17)],cream,.014);line([(.04,.09),(.04,-.17)],cream,.014)
 elif kind=='bakery':
  disk(0,-.03,.27,.17,leather);line([(-.14,-.03),(-.09,.07)],cream,.019);line([(-.02,-.03),(.03,.07)],cream,.019);line([(.10,-.03),(.15,.07)],cream,.019)
 elif kind=='butcher':
  poly('Cleaver blade',[(-.25,.04),(.07,.04),(.07,.24),(-.25,.24)],silver);rect(.18,.14,.24,.06,leather);poly('Meat cut',[(-.23,-.12),(-.13,-.25),(.12,-.26),(.23,-.13),(.13,-.03),(-.11,-.05)],red);disk(.06,-.15,.045,m=cream,y=-.083)
 elif kind=='fish':
  poly('Fish body',[(-.23,0),(-.10,.14),(.13,.10),(.21,0),(.13,-.10),(-.10,-.14)],blue);poly('Fish tail',[(.17,0),(.32,.14),(.32,-.14)],cream);disk(-.13,.035,.023,m=gold,y=-.084);line([(-.055,.09),(-.025,0),(-.055,-.09)],cream,.012)
 elif kind=='stable':
  line([(-.18,.23)]+[(.20*math.cos(t),.0+.24*math.sin(t)) for t in [math.pi+i*math.pi/30 for i in range(31)]]+[(.18,.23)],silver,.049)
  for x in [-.18,.18]:
   for z in [-.08,.06,.19]:disk(x,z,.018,m=iron,y=-.123)
 elif kind=='bank':
  for x,z in [(-.12,-.17),(.12,-.17),(0,.04)]:
   disk(x,z,.105,.064,gold);line([(x-.09,z-.03),(x+.09,z-.03)],cream,.01,y=-.084)
  poly('Key handle diamond',[(-.20,.27),(-.15,.32),(-.10,.27),(-.15,.22)],cream);line([(-.10,.27),(.22,.27),(.22,.19)],cream,.019)
 elif kind=='auction':
  rect(0,-.24,.40,.08,gold);line([(-.13,-.11),(.12,.17)],leather,.025);o=rect(.08,.13,.28,.13,silver);o.rotation_euler.y=-.55

specs=[('weapons','武器店'),('armor','护甲店'),('smith','铁匠铺'),('tailor','裁缝店'),('leather','皮具店'),('potion','药水店'),('magic','魔法用品店'),('scroll','卷轴店'),('jewelry','珠宝店'),('general','杂货店'),('inn','旅馆'),('tavern','酒馆'),('bakery','面包店'),('butcher','肉铺'),('fish','鱼铺'),('stable','坐骑店'),('bank','银行'),('auction','拍卖行')]
def carve_into(board,cutter,back=False):
 bpy.ops.object.select_all(action='DESELECT');cutter.select_set(True);bpy.context.view_layer.objects.active=cutter
 bpy.ops.object.convert(target='MESH');cutter=bpy.context.object
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 ys=[v.co.y for v in cutter.data.vertices];lo=min(ys);span=max(ys)-lo
 depth_extra=min(.009,max(0,-lo-.060)*.35)
 for v in cutter.data.vertices:
  v.co.y=-.058+(v.co.y-lo)/max(span,1e-6)*(.040+depth_extra)
  if back:v.co.y=-v.co.y;v.co.x=-v.co.x
 bm=bmesh.new();bm.from_mesh(cutter.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(cutter.data);bm.free()
 cutter.modifiers.clear();bpy.context.view_layer.objects.active=board
 mod=board.modifiers.new('Carved into solid wood','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.data.objects.remove(cutter,do_unlink=True)
for idx,(key,label) in enumerate(specs):
 current=[];shape=[];radius=.065
 for cx,cz,start in [(.495,.335,0),(-.495,.335,90),(-.495,-.335,180),(.495,-.335,270)]:
  for j in range(9):
   t=math.radians(start+j*90/8);shape.append((cx+radius*math.cos(t),cz+radius*math.sin(t)))
 board=poly('Rounded rectangular carved timber',shape,wood,-.035,.07,.009)
 # Actual recessed silhouettes on both faces: no colored or attached symbol pieces.
 start=len(current);icon(key);cutters=list(current[start:]);current=current[:start]
 for cutter in cutters:
  back=cutter.copy();back.data=cutter.data.copy();sc.collection.objects.link(back)
  carve_into(board,cutter);carve_into(board,back,True)
 # Two subtle horizontal join lines remain clear of suspension hardware.
 for z in [-.135,.135]:
  cutter=poly('Board seam cutter',[(-.57,z-.0015),(.57,z-.0015),(.57,z+.0015),(-.57,z+.0015)],wood,-.058,.04,0)
  current.remove(cutter);back=cutter.copy();back.data=cutter.data.copy();sc.collection.objects.link(back)
  carve_into(board,cutter);carve_into(board,back,True)
 for loop in board.data.loops:
  c=board.data.vertices[loop.vertex_index].co;board.data.uv_layers.active.data[loop.index].uv=(c.z+.5,c.x+.5)
 for x in [-.30,.30]:circle(x,.445,.047,iron,.013,y=0)
 assets.append(dict(id='sign_'+key,label=label,kind='board',objects=list(current)))

# All hanging frames share exactly the same two lower connection centers.
for variant in range(3):
 current=[]
 # Wood bracket matching the supplied reference; metal restricted to chains and pins.
 poly('Wood upright',[(-.80,.52),(-.65,.52),(-.65,1.18),(-.80,1.18)],wood,-.10,.20,.017)
 poly('Wood crossbeam',[(-.80,.98),(.57,.98),(.57,1.13),(-.80,1.13)],wood,-.09,.18,.017)
 if variant==0:
  poly('Wood diagonal brace',[(-.66,.55),(-.66,.74),(-.30,1.02),(-.10,1.02)],wood,-.07,.14,.012)
 elif variant==1:
  poly('Wood long brace',[(-.66,.51),(-.66,.66),(.10,1.01),(.35,1.01)],wood,-.07,.14,.012)
 else:
  poly('Wood upper brace',[(-.69,1.15),(-.69,1.32),(.31,1.13),(.08,1.13)],wood,-.07,.14,.012)
 for z in [.67,1.06]:disk(-.72,z,.019,m=iron,y=-.115)
 for x in [-.30,.30]:
  line([(x,1.06),(x,.92)],iron,.012,y=0,name='Suspension pin')
  for j in range(5):
   link=circle(x,.895-j*.09,.055,iron,.012,y=0)
   if j%2:
    for point in link.data.splines[0].points:
     dx=point.co.x-x;point.co.x=x;point.co.y=dx
 assets.append(dict(id='frame_'+str(variant+1),label=['短斜撑木挂架','长斜撑木挂架','上撑木挂架'][variant],kind='frame',objects=list(current)))

# Arrange modular pairs as a contact sheet; no text objects in scene.
for idx,a in enumerate(assets):
 if a['kind']=='board':offset=Vector(((idx%6)*1.85,0,-(idx//6)*2.05));a['offset']=list(offset)
 else:offset=Vector((0,0,-7));a['offset']=list(offset)
 for o in a['objects']:o.location+=offset
for idx in range(18):
 frame=assets[18+idx%3];off=Vector(assets[idx]['offset'])-Vector(frame['offset'])
 for o in frame['objects']:
  dup=o.copy();dup.data=o.data;sc.collection.objects.link(dup);dup.location+=off;dup['review_only']=True
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.50,.55,.62,1);bg.inputs[1].default_value=.35
bpy.ops.object.light_add(type='AREA',location=(-2,-4,6));l=bpy.context.object;l.data.energy=1600;l.data.size=3;l.rotation_euler=(Vector((4,0,-2))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(4.5,-18,3));cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=11.8;cam.rotation_euler=(Vector((4.45,0,-1.45))-cam.location).to_track_quat('-Z','Y').to_euler()
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True;sc.render.resolution_x=2100;sc.render.resolution_y=1300;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
def render(name):sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
def count(objects):
 deps=bpy.context.evaluated_depsgraph_get();total=0
 for o in objects:
  ev=o.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles();total+=len(me.loop_triangles);ev.to_mesh_clear()
 return total
for a in assets:a['master_triangles']=count(a['objects'])
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'shop_signs_master.blend'),compress=True);render('master_overview')
for o in sc.objects:
 for m in o.modifiers:
  if m.type=='BEVEL':m.segments=2
 if o.type=='CURVE':o.data.bevel_resolution=2
render('optimized_overview')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'shop_signs_optimized.blend'),compress=True)
reports=[]
for a in assets:
 bpy.ops.object.select_all(action='DESELECT');obs=a['objects']
 for o in obs:o.location-=Vector(a['offset']);o.select_set(True)
 tri=count(obs);file=OUT/(a['id']+'.glb')
 bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join();joined=bpy.context.object;joined.name=a['id'];joined['module_type']=a['kind'];joined['socket_standard']='shop_sign_060_v1';joined['rmmo_collision']='none';joined['no_text']=True
 bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
 reports.append(dict(id=a['id'],label=a['label'],kind=a['kind'],master_triangles=a['master_triangles'],triangles=tri,sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
 joined.hide_render=True
(OUT/'manifest.json').write_text(json.dumps(dict(status='offline review',assets=reports,sockets=[[-.30,0,.47],[.30,0,.47]],interface='Shared board-centered Blender XYZ origin; pair any frame with any board without offsets.',no_text=True),ensure_ascii=False,indent=2),encoding='utf8')
print('SHOP_SIGNS_COMPLETE',flush=True)
