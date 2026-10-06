"""Author an original low-poly wall candle bracket in Blender; no downloaded mesh.
Run Blender --background --factory-startup --python tools/build_blender_candle_sconce.py
Reference: Met 55.40.2 (pricket and drip dish); Fab lighting examples (see docs).
Godot local +Z faces into the room, the backplate touches z=-0.21.
"""
import bpy, json, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/'rmmo_runtime/art_sources/candle_sconce'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def coord(p): return (p[0],-p[2],p[1])
materials=[]
for name,color,metal,rough in [('Forged iron',(.095,.079,.064,1),.78,.52),('Warm beeswax',(.82,.68,.38,1),0,.79),('Charred wick',(.022,.013,.008,1),0,1)]:
    m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=color;p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    materials.append(m)
def material(o,slot): o.data.materials.append(materials[slot]);o['material_slot']=slot
def box(name,p,size,slot=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=coord(p));o=bpy.context.object;o.name=name;o.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);material(o,slot);return o
def beam(name,a,b,width):
    a,b=Vector(coord(a)),Vector(coord(b));o=box(name,(0,0,0),(width,(b-a).length,width));o.location=(a+b)/2;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def cylinder(name,p,radius,depth,n,slot=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=radius,depth=depth,location=coord(p));o=bpy.context.object;o.name=name;material(o,slot);return o
box('Forged wall plate',(0,0,-.195),(.105,.46,.03))
for y in [-.165,.165]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.018,location=coord((0,y,-.175)))
    o=bpy.context.object;o.name='Wall fixing rivet';material(o,0)
beam('Bracket upper arm',(0,-.045,-.18),(0,-.045,.12),.035)
beam('Bracket diagonal stay',(0,-.19,-.18),(0,-.045,.12),.028)
cylinder('Candle support socket',(0,-.005,.12),.045,.085,8)
cylinder('Drip dish',(0,-.037,.12),.12,.018,12)
# Raised rim is a shallow open bowl, not a solid floating plate.
verts=[];faces=[]
for r,y in [(.12,-.043),(.12,-.007),(.104,-.009)]:
    for i in range(12):
        a=i*math.tau/12;verts.append(coord((math.cos(a)*r,y,.12+math.sin(a)*r)))
for row in range(2):
    for i in range(12):j=(i+1)%12;faces.append((row*12+i,row*12+j,(row+1)*12+j,(row+1)*12+i))
m=bpy.data.meshes.new('Dish rim');m.from_pydata(verts,[],faces);m.update();o=bpy.data.objects.new('Raised wax-catching lip',m);bpy.context.collection.objects.link(o);material(o,0)
cylinder('Beeswax candle',(0,.125,.12),.037,.22,12,1)
for i in range(3):
    a=i*2.1;length=.025+i*.012;cylinder('Wax rivulet',(math.cos(a)*.033,.22-length/2,.12+math.sin(a)*.033),.006,length,5,1)
cylinder('Wick',(0,.242,.12),.003,.022,5,2)
data={'source':'Blender wall-mounted candle sconce','size':[.26,.54,.46],'flame':[0,.278,.12],'surfaces':[]}
# Export each material separately. Godot uses clockwise triangle winding.
for slot in range(3):
    vertices=[];normals=[];triangles=[]
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH' or o.get('material_slot')!=slot:continue
        mesh=o.data;mesh.calc_loop_triangles();offset=len(vertices)
        for v in mesh.vertices:
            p=o.matrix_world@v.co;vertices.append([round(p.x,6),round(p.z,6),round(-p.y,6)])
        for tri in mesh.loop_triangles:triangles.append([offset+tri.vertices[0],offset+tri.vertices[2],offset+tri.vertices[1]])
    data['surfaces'].append({'vertices':vertices,'triangles':triangles})
(ROOT/'scripts/world3d/candle_sconce_data.gd').write_text('extends RefCounted\n## Original Blender-authored wall bracket. Regenerate with tools/build_blender_candle_sconce.py.\nconst DATA = '+json.dumps(data,separators=(',',':'))+'\n',encoding='utf-8')
(OUT/'candle_sconce_mesh.json').write_text(json.dumps(data),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'candle_sconce.blend'))
print('CANDLE_SCONCE_EXPORTED', [len(s['triangles']) for s in data['surfaces']])
