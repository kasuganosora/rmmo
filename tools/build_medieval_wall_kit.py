"""Blender wall kit: original continuous masonry profiles + owned Dexsoft buttress.

Unit bounds [-.5,.5] after export; runtime maps along shared wall curves.
Textures stay in the default pack and are shared, not embedded per module.
"""
import bpy, math, json, sys, argparse, hashlib
from pathlib import Path
from mathutils import Vector
p=argparse.ArgumentParser(); p.add_argument('--source',required=True,type=Path); p.add_argument('--output',required=True,type=Path)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]); a.output.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
mats=[]
for role,color in [('stone',(.48,.45,.39,1)),('trim',(.62,.59,.51,1)),('door',(.24,.13,.065,1)),('iron',(.055,.05,.045,1))]:
 m=bpy.data.materials.new(role); m.diffuse_color=color; mats.append(m)
pieces=[]; modules=[]
def mesh(name,verts,faces,role=0,bevel=0):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
 ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); me.materials.append(mats[role]); pieces.append(ob)
 bpy.context.view_layer.objects.active=ob; ob.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
 if bevel:
  mod=ob.modifiers.new('Stone edge wear','BEVEL'); mod.width=bevel; mod.segments=2; bpy.ops.object.modifier_apply(modifier=mod.name)
 ob.select_set(False); return ob
def prism(name,poly,y0,y1,role=0,bevel=.025):
 n=len(poly); return mesh(name,[(x,y,z) for y in (y0,y1) for x,z in poly],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],role,bevel)
def box(name,x0,x1,y0,y1,z0,z1,role=0,bevel=.025): return prism(name,[(x0,z0),(x1,z0),(x1,z1),(x0,z1)],y0,y1,role,bevel)
def finish(name,dimensions):
 bpy.ops.object.select_all(action='DESELECT')
 for ob in pieces: ob.select_set(True)
 bpy.context.view_layer.objects.active=pieces[0]; bpy.ops.object.join(); ob=bpy.context.object; ob.name=name
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
 uv=ob.data.uv_layers.active or ob.data.uv_layers.new(name='UVMap')
 for poly in ob.data.polygons:
  axis=max(range(3),key=lambda k:abs(poly.normal[k]))
  for li in poly.loop_indices:
   v=ob.data.vertices[ob.data.loops[li].vertex_index].co
   uv.data[li].uv=((v.x,v.y) if axis==2 else ((v.x,v.z) if axis==1 else (v.y,v.z)))
 for v in ob.data.vertices:
  v.co=Vector((v.co.x/dimensions[0],v.co.y/dimensions[1],v.co.z/dimensions[2]-.5))
 ob.select_set(False); pieces.clear(); modules.append(ob)

# Exact shared end planes: no rounding on the main wall joins.
box('Wall core',-2,2,-1.02,1.02,0,6,0,0)
box('Plinth',-2,2,-1.25,1.25,0,.65,0,0)
for side in (-1,1):
 # Sloping weather course and upper stringcourse.
 mesh('Battered foundation',[(-2,side*1.25,.65),(2,side*1.25,.65),(2,side*1.02,1.05),(-2,side*1.02,1.05)],[(0,1,2,3)],0)
 box('Crown stringcourse',-2,2,side*1.10-.055,side*1.10+.055,5.65,5.83,1,.012)
 # Retain the purchased sculpted buttress, not its collision/LOD duplicates.
 before=set(bpy.context.scene.objects)
 bpy.ops.import_scene.fbx(filepath=str(a.source/'SM_CastleWallSupport2.fbx'))
 imported=list(set(bpy.context.scene.objects)-before)
 donor=next(o for o in imported if o.type=='MESH' and 'LOD0' in o.name)
 for ob in imported:
  if ob!=donor: bpy.data.objects.remove(ob,do_unlink=True)
 coords=[donor.matrix_world @ v.co for v in donor.data.vertices]
 low=Vector([min(v[k] for v in coords) for k in range(3)]); high=Vector([max(v[k] for v in coords) for k in range(3)])
 donor.matrix_world.identity()
 for v,c in zip(donor.data.vertices,coords):
  q=(c-low); v.co=Vector(((q.x/(high.x-low.x)-.5)*.78,side*(.91+q.y/(high.y-low.y)*.34),.55+q.z/(high.z-low.z)*4.95))
 donor.data.materials.clear(); donor.data.materials.append(mats[0]); pieces.append(donor)
finish('wall',(4,2.5,6))

box('Parapet masonry',-1.2,1.2,-.17,.17,0,.37,0,.015)
box('Parapet weather cap',-1.2,1.2,-.2,.2,.37,.45,1,.02)
finish('parapet',(2.4,.4,.45))
box('Merlon',-.6,.6,-.175,.175,0,.61,0,.025)
box('Merlon cap',-.6,.6,-.2,.2,.61,.7,1,.024)
finish('battlement',(1.2,.4,.7))

# An actual through-hole, not a dark decal: 20cm slit, eye level 1.25-1.90m above the walk.
box('Embrasure sill',-.6,.6,-.2,.2,0,.80,0,.02)
box('Embrasure left',-.6,-.10,-.2,.2,.80,1.45,0,.02)
box('Embrasure right',.10,.6,-.2,.2,.80,1.45,0,.02)
box('Embrasure head',-.6,.6,-.2,.2,1.45,1.61,0,.02)
box('Embrasure weather cap',-.6,.6,-.2,.2,1.61,1.7,1,.022)
finish('embrasure',(1.2,.4,1.7))


# Arch head stays above the advertised rectangular gate clearance.
profile=[(-3+6*j/32,.60*math.sqrt(max(0,1-(j/16-1)**2))) for j in range(33)]+[(3,1.5),(-3,1.5)]
prism('Gate spandrel',profile,-1.19,1.19,0,0)
for side in (-1,1):
 for j in range(21):
  t0=math.pi*(j+.025)/21; t1=math.pi*(j+.975)/21
  q=lambda t,r:(-math.cos(t)*3,.60*math.sin(t)+r)
  prism('Cut arch voussoir',[q(t0,0),q(t1,0),q(t1,.26),q(t0,.26)],side*1.225-.024,side*1.225+.024,1,.012)
finish('gate_lintel',(6,2.5,1.5))

box('Gate backing',-1.5,1.5,-.055,.055,0,4.5,2,0)
for i in range(10): box('Oak plank',-1.5+i*.3+.009,-1.5+(i+1)*.3-.009,-.073,.073,0,4.5,2,.013)
for side in (-1,1):
 for z in (.55,2.1,3.7):
  box('Forged iron strap',-1.44,1.44,side*.083-.006,side*.083+.006,z,z+.12,3,.012)
  for x in (-1.27,-.65,0,.65,1.27): box('Iron rivet',x-.025,x+.025,side*.088-.004,side*.088+.004,z+.035,z+.085,3,.01)
finish('door',(3,.18,4.5))

# Three coaxial strap hinges per leaf. The pintle stays in the wall; sleeves rotate.
def cylinder(name,radius,z0,z1,role=3):
 n=24
 verts=[(radius*math.cos(i*math.tau/n),radius*math.sin(i*math.tau/n),z) for z in (z0,z1) for i in range(n)]
 faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh(name,verts,faces,role,.006)
for z in (.62,2.17,3.77):
 cylinder('Moving hinge sleeve',.072,z-.10,z+.10)
 box('Hinge eye lug',-.12,.12,-.036,.036,z-.055,z+.055,3,.012)
finish('hinge',(.28,.36,4.5))
for z in (.62,2.17,3.77):
 cylinder('Fixed pintle',.026,z-.18,z+.18)
 cylinder('Pintle head',.046,z+.15,z+.205)
 box('Jamb anchor',-.135,.135,-.175,-.13,z-.22,z+.22,3,.014)
 box('Pintle wall bracket',-.035,.035,-.15,.02,z-.16,z-.105,3,.01)
finish('hinge_mount',(.28,.36,4.5))


def tower(name,sides):
 # Normalized polygon inscribed in the original tower footprint.
 levels=[(0,2.5),(.65,2.5),(1.25,2.25),(7.3,2.25),(7.5,2.40),(7.8,2.5)]
 verts=[(r*math.cos(i*math.tau/sides),r*math.sin(i*math.tau/sides),z) for z,r in levels for i in range(sides)]
 faces=[tuple(reversed(range(sides))),tuple(range((len(levels)-1)*sides,len(levels)*sides))]
 faces +=[(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i) for j in range(len(levels)-1) for i in range(sides)]
 ob=mesh('Tower battered stone',verts,faces,0)
 ob.data.materials.append(mats[1])
 for face in ob.data.polygons:
  if face.index>2+(len(levels)-3)*sides:face.material_index=1
 finish(name,(5,5,7.8))
tower('round_tower',24)
box('Square tower',-2.3,2.3,-2.3,2.3,0,7.8,0,.045)
box('Tower footing',-2.5,2.5,-2.5,2.5,0,.8,0,.035)
box('Tower cornice',-2.5,2.5,-2.5,2.5,7.48,7.8,1,.025)
finish('corner_tower',(5,5,7.8))
box('Masonry joint',-.5,.5,-.5,.5,0,1,0,0); finish('joint',(1,1,1))
bpy.ops.object.select_all(action='SELECT')
native=a.output.parents[2]/'sources'/'authored'/'fortifications'; native.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(native/'medieval_wall.blend'))
target=a.output/'medieval_wall.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_normals=True,export_texcoords=True)
(a.output/'source.json').write_text(json.dumps({'format':'rmmo_fortification_kit','version':1,'source':'Owned Dexsoft Medieval Castle sculpted buttress; other procedural kit geometry authored in Blender for RMMO','listing':'https://www.fab.com/listings/94b2c6c1-93a7-4291-9af9-ecc84884e751','purchased_module':'SM_CastleWallSupport2.fbx','source_sha256':hashlib.sha256((a.source/'SM_CastleWallSupport2.fbx').read_bytes()).hexdigest(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'modules':[o.name for o in modules]},indent=2),encoding='utf-8')
print('WALL_KIT_BUILT',target)

