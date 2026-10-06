"""Blender-authored diagonal-board door, metre scale, Godot +Y up/-Z front.
The 1.4 x 2.2 m leaf is adapted to existing openings at authoring time.
Sources and historic/reference distinction: docs/timber_door_20261005.md.
"""
import bpy, bmesh, json, math
from pathlib import Path
from mathutils import Vector

OUT=Path('D:/code/rmmo_runtime/art_sources/timber_door')
ASSET=Path('D:/code/rmmo_runtime/assets/timber_door')
OUT.mkdir(parents=True,exist_ok=True); ASSET.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def coord(p): return (p[0],-p[2],p[1])
mats=[]
for name,color,metal,rough in [('Oak',(.26,.14,.067,1),0,.82),('Forged iron',(.055,.047,.037,1),.72,.45)]:
    m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=color;bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough;mats.append(m)
wood=mats[0];wood.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(1,1,1,1)
tex=wood.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load('D:/code/rmmo_runtime/packs/default/assets/materials/wood/solid_timber/texture.png');tex.image.pack()
col=wood.node_tree.nodes.new('ShaderNodeVertexColor');col.layer_name='BoardTint'
mul=wood.node_tree.nodes.new('ShaderNodeMixRGB');mul.blend_type='MULTIPLY';mul.inputs[0].default_value=1
wood.node_tree.links.new(tex.outputs['Color'],mul.inputs[1]);wood.node_tree.links.new(col.outputs['Color'],mul.inputs[2]);wood.node_tree.links.new(mul.outputs[0],wood.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
TONES=[(1,.97,.91,1),(.63,.59,.52,1),(.35,.32,.28,1)]
def finish_wood(o,tone=1,half=0,index=0):
    if o is None:return None
    mesh=o.data;uv=mesh.uv_layers.new(name='GrainUV');color=mesh.color_attributes.new(name='BoardTint',type='FLOAT_COLOR',domain='CORNER')
    uv=mesh.uv_layers['GrainUV'];color=mesh.color_attributes['BoardTint']
    for loop in mesh.loops:
        p=mesh.vertices[loop.vertex_index].co;x,y=p.x,p.z
        # Texture grain runs along V. Rotate with each diagonal board.
        across=(x+half*y)/math.sqrt(2) if half else x
        along=(-half*x+y)/math.sqrt(2) if half else y
        uv.data[loop.index].uv=(across/.8+.083+index*.091,along/2.4+.137)
        color.data[loop.index].color=TONES[tone]
    return o

def poly(name,points,front,back,slot=0):
    # Rectangle clipping can repeat an exact corner or produce a collinear
    # boundary. Remove those before extrusion so the export has no zero faces.
    clean=[]
    for point in points:
        if not clean or (Vector(point)-Vector(clean[-1])).length>1e-8:clean.append(point)
    if len(clean)>1 and (Vector(clean[0])-Vector(clean[-1])).length<1e-8:clean.pop()
    changed=True
    while changed and len(clean)>2:
        changed=False
        for i in range(len(clean)):
            a=Vector(clean[i])-Vector(clean[i-1]);b=Vector(clean[(i+1)%len(clean)])-Vector(clean[i])
            if abs(a.x*b.y-a.y*b.x)<1e-10:
                clean.pop(i);changed=True;break
    points=clean
    if len(points)<3:return None
    n=len(points);v=[coord((x,y,z)) for z in [front,back] for x,y in points]
    f=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],f);mesh.update();o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mats[slot]);o['slot']=slot
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
    return o
def rect(name,x,y,w,h,z0,z1,slot=0): return poly(name,[(x-w/2,y-h/2),(x+w/2,y-h/2),(x+w/2,y+h/2),(x-w/2,y+h/2)],z0,z1,slot)
def clip(points,a,b,c):
    result=[]
    for p,q in zip(points,points[1:]+points[:1]):
        u=a*p[0]+b*p[1]-c;v=a*q[0]+b*q[1]-c
        if u<=0:result.append(p)
        if (u<0)!=(v<0):
            t=u/(u-v);result.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
    return result
finish_wood(rect('Solid timber core',0,0,1.4,2.2,-.026,.033),2)
# Three tones repeat across continuous chevrons. Upper and lower boards meet
# at the same vertex and shade; no transverse rail interrupts the pattern.
for half in [-1,1]:
    for i in range(-5,13):
        region=[(-.66,0),(.66,0),(.66,1.07),(-.66,1.07)] if half==1 else [(-.66,-1.07),(.66,-1.07),(.66,0),(-.66,0)]
        region=clip(region,1,half,i*.22+.217);region=clip(region,-1,-half,-i*.22)
        if len(region)>2:
            o=poly('Oak chevron tone %d board %d half %d'%(i%3,i,half),region,-.036,-.026)
            finish_wood(o,i%3,half,i)
for x in [-.68,.68]:finish_wood(rect('Narrow edge stile',x,0,.04,2.2,-.04,.04),1)
for y in [-1.085,1.085]:finish_wood(rect('Edge rail',0,y,1.4,.03,-.04,.04),1)

def arc_band(name,points,width):
    left=[];right=[]
    for i,p in enumerate(points):
        a=Vector(points[max(0,i-1)]);b=Vector(points[min(len(points)-1,i+1)]);d=(b-a).normalized();n=Vector((-d.y,d.x))*width/2
        left.append(tuple(Vector(p)+n));right.append(tuple(Vector(p)-n))
    return poly(name,left+right[::-1],-.055,-.041,1)

def diamond(y):
    # User-approved simplification: a long solid rhombus instead of sampled
    # spear curves and crossed ridges. Six vertices, eight visible/cap triangles.
    center=-.50;half_length=.18;half_height=.042
    vertices=[coord(p) for p in [(center-half_length,y,-.056),(center,y-half_height,-.056),(center+half_length,y,-.056),(center,y+half_height,-.056),(center,y,-.084),(center,y,-.049)]]
    faces=[(i,(i+1)%4,4) for i in range(4)]+[((i+1)%4,i,5) for i in range(4)]
    mesh=bpy.data.meshes.new('Low-poly elongated diamond');mesh.from_pydata(vertices,[],faces);mesh.update()
    o=bpy.data.objects.new('Near-edge solid elongated diamond',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mats[1]);o['slot']=1
    assert center-half_length>-.70, 'Diamond remains within the timber edge'
for y in [-.64,.64]:
    rect('Full-width thin iron strap',0,y,1.4,.019,-.057,-.042,1)
    for side in [-1,1]:
        points=[]
        for i in range(13):
            a=(math.pi/2)*i/12
            points.append((-.70+1.34*math.sin(a),y+side*.34*math.cos(a)))
        arc_band('Curved iron bow to door edge',points,.013)
    diamond(y)
    for x in [-.686,.14,.52]:poly('Small square fixing',[(x-.009,y),(x,y-.009),(x+.009,y),(x,y+.009)],-.064,-.057,1)
    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.031,depth=.14,location=coord((-.70,y,0)))
    o=bpy.context.object;o.name='Edge hinge barrel';o.data.materials.append(mats[1]);o['slot']=1;o.select_set(False)
for face in [-1,1]:
    z=face*.045
    rect('Dark handle backplate',.51,-.035,.075,.25,min(z,face*.06),max(z,face*.06),1)
    for y in [-.12,.05]:rect('Pull fixing foot',.51,y,.028,.028,min(z,face*.11),max(z,face*.11),1)
    rect('Vertical iron pull',.51,-.035,.027,.20,min(face*.10,face*.13),max(face*.10,face*.13),1)
# Remove only buried wood contacts; retain front seams and silhouette edges.
# Normalize before removing closed caps, so open front skins keep orientation.
optimization=[]
for o in list(bpy.context.scene.objects):
    if o.type!='MESH':continue
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
    o.data.calc_loop_triangles();before=len(o.data.loop_triangles)
    if o.name.startswith('Oak chevron'):
        bm=bmesh.new();bm.from_mesh(o.data);buried=[]
        for face in bm.faces:
            points=[v.co for v in face.verts]
            if (all(abs(p.y-.026)<1e-7 for p in points)
                or all(abs(p.z)<1e-7 for p in points)
                or any(all(abs(p.x-edge)<1e-7 for p in points) for edge in [-.66,.66])
                or any(all(abs(p.z-edge)<1e-7 for p in points) for edge in [-1.07,1.07])):buried.append(face)
        bmesh.ops.delete(bm,geom=buried,context='FACES');bm.to_mesh(o.data);bm.free()
    if o.get('slot')==1:
        # Near-zero angle: simplify coplanar caps/strips, not the forged relief.
        modifier=o.modifiers.new('Dissolve coplanar redundancy','DECIMATE');modifier.decimate_type='DISSOLVE';modifier.angle_limit=.0001;modifier.delimit={'MATERIAL'}
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    o.data.calc_loop_triangles();optimization.append({'part':o.name,'before':before,'after':len(o.data.loop_triangles)})
# Consolidate by material; no unapplied subdivision/bevel modifiers.
for slot in range(2):
    bpy.ops.object.select_all(action='DESELECT');objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('slot')==slot]
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=['OakLeaf','Ironwork'][slot];o['slot']=slot
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for material in mats:material.use_backface_culling=True
data={'size':[1.4,2.2,.065],'surfaces':[]}
for slot in range(2):
    o=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('slot')==slot);o.data.calc_loop_triangles()
    vertices=[];uvs=[];colors=[];normals=[];triangles=[]
    for tri in o.data.loop_triangles:
        indices=[]
        for loop_index in [tri.loops[0],tri.loops[2],tri.loops[1]]:
            p=o.data.vertices[o.data.loops[loop_index].vertex_index].co
            indices.append(len(vertices));vertices.append([round(p.x,6),round(p.z,6),round(-p.y,6)])
            normal=o.data.corner_normals[loop_index].vector;normals.append([normal.x,normal.z,-normal.y])
            uvs.append(list(o.data.uv_layers.active.data[loop_index].uv) if slot==0 else [0,0])
            colors.append(list(o.data.color_attributes['BoardTint'].data[loop_index].color) if slot==0 else [1,1,1,1])
        triangles.append(indices)
    data['surfaces'].append({'vertices':vertices,'triangles':triangles,'uvs':uvs,'colors':colors,'normals':normals})

data['triangles']=sum(len(s['triangles']) for s in data['surfaces'])
assert data['triangles']<=900
for surface in data['surfaces']:
    for triangle in surface['triangles']:
        a,b,c=(Vector(surface['vertices'][i]) for i in triangle)
        assert (b-a).cross(c-a).length>1e-10, 'Degenerate triangle'
tones={tuple(round(v,3) for v in color) for color in data['surfaces'][0]['colors']}
assert len(tones)==3, 'Three board tones must survive consolidation'
(OUT/'validation.json').write_text(json.dumps({'triangles':data['triangles'],'materials':2,'wood_tones':sorted(tones),'nondegenerate':True,'formal_town_published':False},indent=2),encoding='utf8')
(OUT/'optimization.json').write_text(json.dumps({'reference_triangles':1680,'generated_before_contact_cleanup':sum(row['before'] for row in optimization),'after':data['triangles'],'reduction_percent':round((1680-data['triangles'])/1680*100,3),'parts':optimization},indent=2),encoding='utf8')
(ASSET/'timber_door_mesh.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'timber_door.blend'))
bpy.ops.export_scene.gltf(filepath=str(ASSET/'timber_door.glb'),export_format='GLB',export_yup=True,export_vertex_color='NAME',export_vertex_color_name='BoardTint')
print('TIMBER_DOOR',data['triangles'],'triangles, 2 materials, 3 board tones')

