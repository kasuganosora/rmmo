"""Original banner streetlamp. Blender --background --factory-startup --python <this>.
Blender source and review render stay outside the Godot import tree.
Model coordinates are metres, Z up, pole foot at origin; glTF export converts Y up.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'rmmo_runtime/art_sources/banner_streetlamp'
ASSET = ROOT.parent / 'rmmo_runtime/assets/banner_streetlamp'
SOURCE.mkdir(parents=True, exist_ok=True)
ASSET.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
mats = []
for name, color, metal, rough in [
    ('Blackened bronze', (.085,.049,.027,1),.72,.43),
    ('Rubbed brass edges', (.40,.23,.065,1),.76,.35),
    ('Oxblood woven cloth', (.31,.016,.026,1),0,.9),
    ('Gold thread', (.75,.45,.12,1),.18,.65),
    ('Smoky glass', (.28,.35,.31,.24),.05,.18),
    ('Arcane blue crystal', (.025,.28,.68,.5),.05,.2),
    ('Arcane crystal heart', (.07,.4,.68,1),.05,.24)]:
    m=bpy.data.materials.new(name); m.diffuse_color=color; m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=color; p.inputs['Metallic'].default_value=metal
    p.inputs['Roughness'].default_value=rough
    if name in ['Smoky glass','Arcane blue crystal']:
        p.inputs['Alpha'].default_value=color[3]
        m.surface_render_method='DITHERED'
    mats.append(m)

def mat(o,i): o.data.materials.append(mats[i]); o['slot']=i; return o
def cylinder(name,p,r,depth,slot=0,n=8,r2=None):
    bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=depth,location=p)
    o=bpy.context.object; o.name=name
    # Blender's 4-gon starts on an axis (diamond); lantern frames use square corners.
    if n==4:o.rotation_euler.z=math.pi/4
    return mat(o,slot)
def sphere(name,p,r,slot=1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=r,location=p)
    o=bpy.context.object;o.name=name;return mat(o,slot)
def beam(name,a,b,r=.02,slot=0,n=6):
    a,b=Vector(a),Vector(b);o=cylinder(name,(a+b)/2,r,(b-a).length,slot,n)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def mesh(name,vs,fs,slot):
    m=bpy.data.meshes.new(name);m.from_pydata(vs,[],fs);m.update()
    o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);return mat(o,slot)
def tube(name,points,r=.014,slot=0):
    cleaned=[]
    for p in points:
        if not cleaned or (Vector(p)-Vector(cleaned[-1])).length>1e-6:cleaned.append(p)
    points=cleaned
    vs=[];fs=[]
    for i,p in enumerate(points):
        v=Vector(p); tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        tangent.normalize();u=Vector((0,1,0));w=tangent.cross(u).normalized()
        for j in range(4): vs.append(v+r*(u*math.cos(j*math.tau/4)+w*math.sin(j*math.tau/4)))
    for i in range(len(points)-1):
        for j in range(4):fs.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
    fs.extend([tuple(range(3,-1,-1)),tuple((len(points)-1)*4+j for j in range(4))])
    return mesh(name,vs,fs,slot)

# Foot with real plate, fixing heads, tapered socket and thin shaft.
cylinder('Octagonal anchor plate',(0,0,.025),.19,.05,0,8)
cylinder('Foot moulding',(0,0,.073),.15,.046,1,12,r2=.115)
cylinder('Pedestal socket',(0,0,.24),.105,.29,0,12,r2=.072)
cylinder('Socket shoulder',(0,0,.40),.095,.06,1,12,r2=.065)
cylinder('Tapered lamp column',(0,0,1.71),.052,2.6,0,12,r2=.038)
for z,r in [(.48,.071),(.53,.062),(1.01,.06),(1.055,.06),(2.85,.07),(2.92,.064),(3.03,.083)]:
    cylinder('Turned collar',(0,0,z),r,.03,1)
for x in [-.105,.105]:
    for y in [-.105,.105]:cylinder('Anchor bolt',(x,y,.056),.018,.018,0,6)
# Raised ribs stop at collars; not separate runtime nodes after export.
for i in range(8):
    a=i*math.tau/8;beam('Base flute',(.092*math.cos(a),.092*math.sin(a),.14),(.074*math.cos(a),.074*math.sin(a),.33),.009,1,6)

# Banner arm supported from two collars and scroll stays.
beam('Banner horizontal spar',(-1.02,0,2.88),(.035,0,2.88),.025)
sphere('Spar finial',(-1.045,0,2.88),.045)
beam('Load bearing diagonal',(-.01,0,2.57),(-.40,0,2.88),.02)
pts=[]
for i in range(23):
    t=i/22; a=-math.pi/2+t*math.pi*2.1; r=.16*(1-.73*t)
    pts.append((-.35+r*math.cos(a),.012,2.68+r*math.sin(a)))
tube('Forged inner scroll',[(0,.012,2.57),(-.35,.012,2.52)]+pts,.013)
mount=cylinder('Upper scroll arm socket',(-.94,0,2.88),.037,.07,0,12)
mount.rotation_euler.y=math.pi/2
pts=[(-.94,0,2.90),(-.94,0,2.965)]
for i in range(29):
    t=i/28;a=math.pi-t*math.pi*1.75;r=.15*(1-.72*t*t)
    pts.append((-.79+r*math.cos(a),0,3.03+r*math.sin(a)))
tube('Continuous upper volute',pts,.014)
sphere('Finished volute tip',pts[-1],.015,0)
# Hanging straps loop visibly over the pole; the pointed cloth is mildly draped.
for x in [-.88,-.34]:
    pts=[(x,.032*math.sin(a),2.866+.042*math.cos(a)) for a in [i*math.tau/12 for i in range(13)]]
    tube('Banner suspension loop',pts,.015,1)
def cloth(u,v,offset=0):
    width=.67*(1-.99*max(0,(v-.17)/.83))
    x=-.61+(u-.5)*width;z=2.835-v*1.14
    y=-.038+.032*math.sin(u*math.pi*2+.4)*math.sin(math.pi*v)+.025*v*v+offset
    return (x,y,z)
vs=[cloth(i/8,j/14) for j in range(15) for i in range(9)]
fs=[(j*9+i,j*9+i+1,(j+1)*9+i+1,(j+1)*9+i) for j in range(14) for i in range(8)]
o=mesh('Heavy pointed banner',vs,fs,2)
solid=o.modifiers.new('Stitched cloth thickness','SOLIDIFY');solid.thickness=.004
bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=solid.name)
for side in [0,1]:
    vs=[];fs=[]
    for j in range(15):
        for u in ([.035,.085] if side==0 else [.915,.965]):vs.append(cloth(u,j/14,-.012))
    for j in range(14):fs.append((2*j,2*j+1,2*j+3,2*j+2))
    mesh('Embroidered gold border',vs,fs,3)
for v in [.027,.057]:tube('Top gold stitch',[cloth(i/6,v,-.006) for i in range(7)],.004,3)
# Original abstract paired-ring crest, not copied insignia.
for cx in [-.682,-.542]:
    pts=[(cx+.09*math.cos(a),-.078,2.58+.12*math.sin(a)) for a in [i*math.tau/20 for i in range(21)]]
    tube('Twin loop crest',pts,.009,3)
tube('Crest stem',[(-.612,-.078,2.66),(-.612,-.078,2.34),(-.66,-.078,2.28)],.009,3)
for z in [2.25,2.1]:
    mesh('Woven diamond',[(-.612,-.071,z+.035),(-.584,-.071,z),(-.612,-.071,z-.035),(-.64,-.071,z)],[(0,1,2,3)],3)

# Four-panel lantern: sill and roof frames support every upright/glass pane.
cylinder('Lantern pedestal',(0,0,3.10),.10,.12,0,8,r2=.14)
cylinder('Lower lantern sill',(0,0,3.18),.245,.07,1,4)
corners=[(-.153,-.153),(.153,-.153),(.153,.153),(-.153,.153)]
for x,y in corners:beam('Lantern corner stile',(x*.8,y*.8,3.20),(x,y,3.70),.019,0)
for i,(x,y) in enumerate(corners):
    nx,ny=corners[(i+1)%4]
    mesh('Inset smoky glass',[(x*.81,y*.81,3.216),(nx*.81,ny*.81,3.216),(nx*.96,ny*.96,3.675),(x*.96,y*.96,3.675)],[(0,1,2,3)],4)
    beam('Lower glazing rail',(x*.8,y*.8,3.218),(nx*.8,ny*.8,3.218),.012,1,6)
    beam('Upper glazing rail',(x,y,3.67),(nx,ny,3.67),.009,1,6)
cylinder('Lantern cornice',(0,0,3.71),.263,.065,1,4)
cylinder('Pyramidal weather hood',(0,0,3.825),.295,.20,0,4,r2=.09)
cylinder('Ventilator neck',(0,0,3.965),.064,.09,0,8)
cylinder('Rain cap',(0,0,4.015),.092,.04,1,8,r2=.02)
sphere('Finial',(0,0,4.065),.033)
cylinder('Crystal socket',(0,0,3.265),.044,.08,1,8,r2=.025)
def crystal(name,center,height,radius,slot):
    vs=[(0,0,center-height/2),(0,0,center+height/2)]
    vs += [(radius*math.cos(i*math.tau/8),radius*math.sin(i*math.tau/8),center) for i in range(8)]
    fs=[]
    for i in range(8):j=(i+1)%8;fs.extend([(0,2+j,2+i),(1,2+i,2+j)])
    return mesh(name,vs,fs,slot)
crystal('Faceted blue crystal',3.46,.32,.074,5)
crystal('Diamond inner heart',3.46,.18,.029,6)

# Keep fabric and embroidery in one replaceable, wind-driven slot.
for label,slots in [('StreetlampOpaque',[0,1]),('BannerCloth',[2,3]),('LanternGlass',[4]),('ArcaneCrystal',[5,6])]:
    bpy.ops.object.select_all(action='DESELECT')
    objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('slot') in slots]
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join()
    o=bpy.context.object;o.name=label
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    for poly in o.data.polygons:poly.use_smooth=False
    if label == 'BannerCloth':
        o['rmmo_banner_slot'] = True
        uv = o.data.uv_layers.new(name='BannerDesign')
        for loop in o.data.loops:
            v = o.data.vertices[loop.vertex_index].co
            uv.data[loop.index].uv = ((v.x + .945) / .67, (v.z - 1.695) / 1.14)

stats={}
for o in bpy.context.scene.objects:
    if o.type=='MESH':o.data.calc_loop_triangles();stats[o.name]={'vertices':len(o.data.vertices),'triangles':len(o.data.loop_triangles),'materials':len(o.data.materials)}
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(ASSET/'banner_streetlamp.glb'),export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_yup=True,export_extras=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'banner_streetlamp.blend'))
(SOURCE/'mesh_stats.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
# Simple neutral studio: the reusable .blend was saved before review-only objects.
floor=mesh('Review ground',[(-200,-200,-.008),(200,-200,-.008),(200,200,-.008),(-200,200,-.008)],[(0,1,2,3)],5)
floor.data.materials.clear()
ground=bpy.data.materials.new('Studio neutral');ground.diffuse_color=(.22,.25,.24,1);floor.data.materials.append(ground)
world=bpy.context.scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.4,.46,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45
def area(name,pos,power,size):
    bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((-.25,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
area('Key',(-3,-4,7),650,5);area('Rim',(3,2,5),900,3)
bpy.ops.object.camera_add(location=(5,-10,5.0));cam=bpy.context.object;cam.rotation_euler=(Vector((-.35,0,2.05))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=4.65;bpy.context.scene.camera=cam
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
scene.render.resolution_x=760;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.render.filepath=str(SOURCE/'banner_streetlamp_review.png');scene.view_settings.view_transform='AgX'
bpy.ops.render.render(write_still=True)
print('BANNER_STREETLAMP_EXPORTED',json.dumps(stats))
