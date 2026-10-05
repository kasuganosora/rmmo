"""Blender-authored interior door review asset; not enabled in map generation.

Godot coordinates: +Y up, -Z front. Leaf hinge is the screen-right edge (-0.6, 0, 0).
The matching fixed frame is a separate mesh. See docs/interior_timber_door_20261005.md.
"""
import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector

SOURCE = Path('D:/code/rmmo_runtime/art_sources/interior_timber_door')
ASSET = Path('D:/code/rmmo_runtime/assets/interior_timber_door')
REVIEW = Path('D:/code/rmmo_runtime/review_artifacts/interior_timber_door')
for directory in [SOURCE, ASSET, REVIEW]:
    directory.mkdir(parents=True, exist_ok=True)
reference = Path('C:/Users/luna/AppData/Local/Temp/codex-clipboard-8206d678-ada7-41cf-8ca2-9d7c6da9b818.png')
if reference.exists():
    shutil.copy2(reference, SOURCE / 'user_reference.png')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def coord(p):
    return (-p[0], -p[2], p[1])

wood = bpy.data.materials.new('Dark oak along each board')
wood.use_nodes = True
bsdf = next(node for node in wood.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Roughness'].default_value = .75
texture = wood.node_tree.nodes.new('ShaderNodeTexImage')
texture.image = bpy.data.images.load('D:/code/rmmo_runtime/packs/default/assets/materials/wood/solid_timber/texture.png')
texture.image.pack()
color = wood.node_tree.nodes.new('ShaderNodeVertexColor')
color.layer_name = 'BoardTint'
multiply = wood.node_tree.nodes.new('ShaderNodeMixRGB')
multiply.blend_type = 'MULTIPLY'
multiply.inputs[0].default_value = 1
wood.node_tree.links.new(texture.outputs['Color'], multiply.inputs[1])
wood.node_tree.links.new(color.outputs['Color'], multiply.inputs[2])
wood.node_tree.links.new(multiply.outputs[0], bsdf.inputs['Base Color'])
brass = bpy.data.materials.new('Aged warm brass')
brass.diffuse_color = (.40, .285, .12, 1)
brass.use_nodes = True
bsdf = next(node for node in brass.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Base Color'].default_value = brass.diffuse_color
bsdf.inputs['Metallic'].default_value = .73
bsdf.inputs['Roughness'].default_value = .38
for material in [wood, brass]:
    material.use_backface_culling = True

buffers = {name: {'vertices': [], 'faces': [], 'uvs': [], 'colors': []} for name in ['DoorLeafWood', 'DoorLeafBrass', 'FixedDoorFrame']}
TONES = [(.92, .83, .70, 1), (.66, .56, .45, 1), (.79, .67, .54, 1)]

def face(name, points, normal, tone=0, direction=(0, 1), offset=0, smooth=False):
    """Append a convex polygon with intentional outward normal and board-local UVs."""
    if len(points) < 3:
        return
    points = list(points)
    actual = (Vector(points[1]) - Vector(points[0])).cross(Vector(points[2]) - Vector(points[0]))
    if actual.dot(Vector(normal)) < 0:
        points.reverse()
    group = buffers[name]
    first = len(group['vertices'])
    group['vertices'].extend(points)
    group['faces'].append((list(range(first, first + len(points))), smooth))
    dx, dy = direction
    for x, y, z in points:
        if abs(normal[0])>.5 and all(abs(p[0]-points[0][0])<1e-8 for p in points):
            uv=(z/.30+offset,y/2.4+.12)
        elif abs(normal[1])>.5 and all(abs(p[1]-points[0][1])<1e-8 for p in points):
            uv=(z/.30+offset,x/2.4+.12)
        else:
            uv=((dy*x-dx*y)/.85+offset,(dx*x+dy*y)/2.4+.12)
        group['uvs'].append(uv)
        group['colors'].append(((.16,.12,.09,1) if tone == 99 else TONES[tone % len(TONES)]) if name != 'DoorLeafBrass' else (1, 1, 1, 1))

def box(name, x, y, w, h, front, back, tone=0, horizontal=False):
    x0, x1, y0, y1 = x-w/2, x+w/2, y-h/2, y+h/2
    direction = (1, 0) if horizontal else (0, 1)
    for z, n in [(front, (0, 0, -1)), (back, (0, 0, 1))]:
        face(name, [(x0,y0,z),(x1,y0,z),(x1,y1,z),(x0,y1,z)], n, tone, direction)
    face(name, [(x0,y0,front),(x0,y1,front),(x0,y1,back),(x0,y0,back)], (-1,0,0), tone, direction)
    face(name, [(x1,y0,front),(x1,y1,front),(x1,y1,back),(x1,y0,back)], (1,0,0), tone, direction)
    face(name, [(x0,y0,front),(x1,y0,front),(x1,y0,back),(x0,y0,back)], (0,-1,0), tone, direction)
    face(name, [(x0,y1,front),(x1,y1,front),(x1,y1,back),(x0,y1,back)], (0,1,0), tone, direction)

def clip(points, a, b, c):
    result=[]
    for p,q in zip(points, points[1:]+points[:1]):
        u=a*p[0]+b*p[1]-c
        v=a*q[0]+b*q[1]-c
        if u <= 0:
            result.append(p)
        if (u < 0) != (v < 0):
            t=u/(u-v)
            result.append((p[0]+t*(q[0]-p[0]), p[1]+t*(q[1]-p[1])))
    clean=[]
    for p in result:
        if not clean or (Vector(p)-Vector(clean[-1])).length > 1e-7:
            clean.append(p)
    if len(clean)>1 and (Vector(clean[0])-Vector(clean[-1])).length<1e-7:
        clean.pop()
    return clean

# Structural frame, real thickness and inset panel, no paper-thin door.
for x in [-.53, .53]:
    box('DoorLeafWood', x, 0, .14, 2.2, -.0375, .0375, 1)
for y, h in [(-1.045,.11), (1.045,.11), (-.17,.13)]:
    box('DoorLeafWood', 0, y, .92, h, -.0375, .0375, 0, horizontal=True)

panel_bounds = [(-.46,.46,-.99,-.235,-1), (-.46,.46,-.105,.99,1)]
for x0,x1,y0,y1,sign in panel_bounds:
    # Continuous core supports shallow physical seams on both sides.
    box('DoorLeafWood', 0, (y0+y1)/2, x1-x0, y1-y0, -.020,.020, 99)
    dx, dy = .55, sign*math.sqrt(1-.55**2)
    across = (dy, -dx)
    for i in range(-9,10):
        points=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
        points=clip(points,*across,i*.20+.196)
        points=clip(points,-across[0],-across[1],-i*.20)
        if len(points)<3:
            continue
        for side in [-1,1]:
            z=side*.024
            face('DoorLeafWood',[(x,y,z) for x,y in points],(0,0,side),i,(dx,dy),i*.073)
            # Only seam returns remain. Panel ends disappear under joinery.
            for p,q in zip(points,points[1:]+points[:1]):
                if abs((q[0]-p[0])*across[0]+(q[1]-p[1])*across[1]) < 1e-5:
                    n=(q[1]-p[1],p[0]-q[0],0)
                    face('DoorLeafWood',[(p[0],p[1],z),(q[0],q[1],z),(q[0],q[1],side*.020),(p[0],p[1],side*.020)],n,i,(dx,dy),i*.073)
    # One narrow chamfer surrounding each panel on both faces. Single ring,
    # instead of subdivision/beveling every plank and hidden contact face.
    outer=[(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
    inner=[(x0+.010,y0+.010),(x1-.010,y0+.010),(x1-.010,y1-.010),(x0+.010,y1-.010)]
    for side in [-1,1]:
        for i in range(4):
            j=(i+1)%4
            face('DoorLeafWood',[(outer[i][0],outer[i][1],side*.0375),(outer[j][0],outer[j][1],side*.0375),(inner[j][0],inner[j][1],side*.024),(inner[i][0],inner[i][1],side*.024)],(0,0,side),1,(1,0) if i in [0,2] else (0,1))

# Static U-shaped jamb, genuine open passage, deliberately no threshold.
for x in [-.661,.661]:
    box('FixedDoorFrame',x,0,.106,2.212,-.077,.077,1)
box('FixedDoorFrame',0,1.16,1.428,.108,-.077,.077,1,horizontal=True)

def knob(side):
    # Low-poly revolved rounded knob, circular silhouette with radial normals.
    x,y=-.53,-.17
    box('DoorLeafBrass',x,y,.083,.170, min(side*.038,side*.045),max(side*.038,side*.045))
    profile=[(.045,.021),(.059,.021),(.069,.037),(.095,.044),(.109,.033)]
    segments=12
    for (z0,r0),(z1,r1) in zip(profile,profile[1:]):
        for i in range(segments):
            a,b=2*math.pi*i/segments,2*math.pi*(i+1)/segments
            points=[(x+math.cos(a)*r0,y+math.sin(a)*r0,side*z0),(x+math.cos(b)*r0,y+math.sin(b)*r0,side*z0),(x+math.cos(b)*r1,y+math.sin(b)*r1,side*z1),(x+math.cos(a)*r1,y+math.sin(a)*r1,side*z1)]
            face('DoorLeafBrass',points,(math.cos((a+b)/2),math.sin((a+b)/2),0),smooth=True)
    # Modest domed face with twelve triangles; no UV sphere tessellation.
    z,r=profile[-1]
    for i in range(segments):
        a,b=2*math.pi*i/segments,2*math.pi*(i+1)/segments
        face('DoorLeafBrass',[(x+math.cos(a)*r,y+math.sin(a)*r,side*z),(x+math.cos(b)*r,y+math.sin(b)*r,side*z),(x,y,side*.114)],(0,0,side),smooth=True)
for side in [-1,1]:
    knob(side)

# Two compact exposed hinge barrels aligned on +X edge, no broad exterior ironwork.
for y in [-.72,.72]:
    radius=.014
    for i in range(8):
        a,b=2*math.pi*i/8,2*math.pi*(i+1)/8
        points=[(.6+radius*math.cos(a),y-.055,radius*math.sin(a)),(.6+radius*math.cos(b),y-.055,radius*math.sin(b)),(.6+radius*math.cos(b),y+.055,radius*math.sin(b)),(.6+radius*math.cos(a),y+.055,radius*math.sin(a))]
        face('DoorLeafBrass',points,(math.cos((a+b)/2),0,math.sin((a+b)/2)),smooth=True)
    for yy,n in [(y-.055,(0,-1,0)),(y+.055,(0,1,0))]:
        face('DoorLeafBrass',[(.6+radius*math.cos(i*math.pi/4),yy,radius*math.sin(i*math.pi/4)) for i in range(8)],n)

data={'size':[1.2,2.2,.075],'hinge':[-.6,0,0],'front':[0,0,-1],'surfaces':[]}
root=bpy.data.objects.new('InteriorDoorReview',None)
bpy.context.collection.objects.link(root)
for name,group in buffers.items():
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata([coord(p) for p in group['vertices']],[],[p[0][::-1] for p in group['faces']])
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent=root
    obj['motion_group']='static_frame' if name=='FixedDoorFrame' else 'door_leaf'
    obj['hinge_godot']=[-.6,0,0]
    mesh.materials.append(brass if name=='DoorLeafBrass' else wood)
    uv=mesh.uv_layers.new(name='GrainUV')
    tint=mesh.color_attributes.new(name='BoardTint',type='FLOAT_COLOR',domain='CORNER')
    uv=mesh.uv_layers['GrainUV']
    for loop in mesh.loops:
        uv.data[loop.index].uv=group['uvs'][loop.vertex_index]
        tint.data[loop.index].color=group['colors'][loop.vertex_index]
    for polygon,source_face in zip(mesh.polygons,group['faces']):
        polygon.use_smooth=source_face[1]
    # Weld coincident normal vertices, preserving UV seams and per-loop tint.
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=.000001)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)
    uv=mesh.uv_layers['GrainUV']
    tint=mesh.color_attributes['BoardTint']
    mesh.calc_loop_triangles()
    surface={'name':name,'motion_group':obj['motion_group'],'material':1 if name=='DoorLeafBrass' else 0,'vertices':[],'uvs':[],'colors':[],'normals':[],'triangles':[]}
    for tri in mesh.loop_triangles:
        indices=[]
        for li in [tri.loops[0],tri.loops[2],tri.loops[1]]:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            n=mesh.corner_normals[li].vector
            indices.append(len(surface['vertices']))
            surface['vertices'].append([p.x,p.z,-p.y])
            surface['normals'].append([n.x,n.z,-n.y])
            surface['uvs'].append(list(uv.data[li].uv))
            surface['colors'].append(list(tint.data[li].color))
        surface['triangles'].append(indices)
    data['surfaces'].append(surface)

data['triangles']=sum(len(s['triangles']) for s in data['surfaces'])
assert data['triangles'] <= 900, data['triangles']
for surface in data['surfaces']:
    for triangle in surface['triangles']:
        a,b,c=(Vector(surface['vertices'][i]) for i in triangle)
        assert (b-a).cross(c-a).length>1e-10, 'Degenerate triangle'
(ASSET/'interior_timber_door_mesh.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf8')
report={'triangles':data['triangles'],'per_group':{s['name']:len(s['triangles']) for s in data['surfaces']},'materials':2,'meshes':3,'nondegenerate':True,'leaf_size_m':data['size'],'hinge_godot_m':data['hinge'],'static_frame_separate':True,'backside_complete':True,'formal_town_published':False,'user_art_approval':'pending','optimization':'12-segment revolved knobs, 8-segment hinge barrels, single-segment panel chamfer, no hidden plank back caps, no subdivision or modifiers'}
(SOURCE/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'interior_timber_door.blend'))
bpy.ops.export_scene.gltf(filepath=str(ASSET/'interior_timber_door.glb'),export_format='GLB',export_yup=True,export_vertex_color='NAME',export_vertex_color_name='BoardTint')
print('INTERIOR_DOOR',json.dumps(report))
