"""Blender 4.5 CPU authoring of the complete Axel undershot watermill.

All authoring coordinates below are Godot metres: +Y up, +Z entrance.
Only this asset's art/review directories are written. No renders or map edits.
"""
import bpy, bmesh, math, json, hashlib, sys, struct, re
from pathlib import Path
from mathutils import Vector

OUT = Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill')
REVIEW = Path('D:/code/rmmo/review_artifacts/axel_landmarks_20261016/watermill')
MATROOT = Path('D:/code/rmmo_runtime/packs/default/assets/materials')
VERSION = 'v11'
DEST = OUT / VERSION
DEST.mkdir(parents=True, exist_ok=True)
REVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1
def C(p): return Vector((p[0], -p[2], p[1]))
def G(p): return [p[0], p[2], -p[1]]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
MATERIAL_SOURCES=[]
ROOTS={}
MESHES=[]

def material(name, relative=None, color=(1,1,1,1), rough=.8, metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=color
    m.use_backface_culling=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=color;bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    m['uv_tile_m']=[1.,1.]
    if relative:
        definition=MATROOT/relative/'material.json';j=json.loads(definition.read_text(encoding='utf-8'));p=j['material'];m['uv_tile_m']=p.get('tile_size',[1.,1.])
        bs.inputs['Base Color'].default_value=tuple(p.get('color',[1,1,1,1]));bs.inputs['Roughness'].default_value=p.get('roughness',1.)
        row={'material':name,'definition':str(definition),'definition_sha256':sha(definition),'source':j.get('source',{}),'maps':{}}
        for key,channel in [('texture_path','Base Color'),('roughness_path','Roughness'),('normal_path','Normal')]:
            if key not in p:continue
            path=(definition.parent/p[key]).resolve();im=bpy.data.images.load(str(path),check_existing=True)
            if key!='texture_path':im.colorspace_settings.name='Non-Color'
            im.pack();tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
            if key=='normal_path':
                n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=p.get('normal_strength',1.)
                m.node_tree.links.new(tex.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],bs.inputs['Normal'])
            else:m.node_tree.links.new(tex.outputs['Color'],bs.inputs[channel])
            row['maps'][key]={'path':str(path),'sha256':sha(path),'width':im.size[0],'height':im.size[1]}
        MATERIAL_SOURCES.append(row)
    return m

STONE=material('Mill limestone masonry','walls/stone_tiles_facade')
PLASTER=material('Mill lime plaster','walls/exterior_limewash')
# Limewash covers the coarse cement colour scan; retain restrained hand-trowelled
# relief at a smaller, physically plausible scale rather than marble-like waves.
PLASTER['uv_tile_m']=[.45,.45]
next(n for n in PLASTER.node_tree.nodes if n.type=='NORMAL_MAP').inputs['Strength'].default_value=.18
MATERIAL_SOURCES[-1]['candidate_overrides']={'uv_tile_m':[.45,.45],'normal_strength':.18,'reason':'Warm limewash with fine restrained trowel relief; coarse cement base colour is not exposed.'}
WOOD=material('Mill oak timber','wood/solid_timber')
ROOF=material('Mill terracotta tiles','roofs/terracotta_plain')
IRON=material('Mill forged iron',color=(.043,.038,.032,1),rough=.54,metal=.83)
FLOUR=material('Mill pale grain sack',color=(.44,.34,.20,1),rough=.94)
GLASS=material('Mill thin clear glass',color=(.97,.985,.98,.035),rough=.09)
GLASS.surface_render_method='DITHERED'
next(n for n in GLASS.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Alpha'].default_value=.035

def root(name, floor=0, role='body', origin=(0,0,0)):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=C(origin)
    o['uuid']='watermill_'+name;o['asset_id']='axel_watermill';o['semantic_group']=name
    o['author_floor']=floor;o['author_role']=role
    ROOTS[name]=o
    bpy.context.view_layer.update()
    return o

for group,floor,role in [('foundation',0,'floor'),('exterior_l0',0,'body'),('timber_l0',0,'body'),('floor_l1',1,'floor'),('exterior_l1',1,'body'),('timber_l1',1,'body'),('stairs',0,'stairs'),('rails_l1',1,'body'),('roof',1,'roof'),('roof_trusses',1,'roof'),('porch',0,'body'),('windows_l0',0,'body'),('windows_l1',1,'body'),('machinery_fixed',0,'body'),('machinery_guard',0,'body'),('milling_furniture',1,'body'),('storage',0,'body'),('wheel_support',0,'body')]:root(group,floor,role)
for group in ['river_foundation_east','river_foundation_west','river_foundation_front','river_foundation_rear','river_foundation_inner_pier_front','river_foundation_inner_pier_rear','river_foundation_outer_bearing']:root(group,0,'body')
root('waterwheel',0,'rotor',(6.85,1.1,0))
root('drive_axle',0,'rotor',(6.85,1.1,0))
root('pitwheel',0,'rotor',(3.6,1.1,0))
root('wallower',0,'rotor',(3.27,2.05,0))
root('great_spur',0,'rotor',(3.27,2.90,0))
root('stone_nut',0,'rotor',(1.75,2.90,0))
root('runner_stone',1,'rotor',(1.75,4.08,0))

def mesh(name,vs,fs,mat,group,collision='block',bevel=0,uv_axes=None):
    me=bpy.data.meshes.new(name);me.from_pydata([C(p) for p in vs],[],fs);me.update()
    o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free()
    o['uuid']=re.sub(r'[^A-Za-z0-9_-]','_','watermill_'+group+'_'+name);o['semantic_group']=group;o['rmmo_collision']=collision
    o['author_floor']=ROOTS[group]['author_floor'];o['author_role']=ROOTS[group]['author_role']
    o.parent=ROOTS[group];o.matrix_parent_inverse=ROOTS[group].matrix_world.inverted()
    # A planar projection per hard architectural face. Beams get grain along their long axis.
    uv=me.uv_layers.new(name='UVMap');tile=list(mat.get('uv_tile_m',[1,1]))
    for poly in me.polygons:
        n=G(poly.normal);axis=max(range(3),key=lambda q:abs(n[q]));axes=uv_axes or ((2,1) if axis==0 else (0,2) if axis==1 else (0,1))
        for li in poly.loop_indices:
            p=G(me.vertices[me.loops[li].vertex_index].co)
            uv.data[li].uv=(p[axes[0]]/tile[0],p[axes[1]]/tile[1])
    if bevel:
        bpy.context.view_layer.objects.active=o;o.select_set(True)
        mod=o.modifiers.new('Small physically rounded edge','BEVEL');mod.width=bevel;mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name);o.select_set(False)
    MESHES.append(o);return o

def box(name,p,size,mat=WOOD,group='timber_l0',collision='block',bevel=.008):
    x,y,z=p;a,b,c=[v/2 for v in size]
    vs=[(x+dx*a,y+dy*b,z+dz*c) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],mat,group,collision,bevel)

def beam(name,a,b,width=.16,depth=None,mat=WOOD,group='timber_l0',collision='block'):
    a=Vector(a);b=Vector(b);v=(b-a).normalized();up=Vector((0,1,0))
    if abs(v.dot(up))>.98:up=Vector((0,0,1))
    u=v.cross(up).normalized()*width/2;w=u.normalized().cross(v).normalized()*(depth or width)/2
    vs=[tuple(p+su*u+sw*w) for p in [a,b] for su,sw in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    o=mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,group,collision,.008)
    # Beam-local projection aligns the scan's vertical grain with the member.
    uv=o.data.uv_layers.active;tile=list(mat.get('uv_tile_m',[.8,2.4]))
    for face in o.data.polygons:
        for li in face.loop_indices:
            q=Vector(G(o.data.vertices[o.data.loops[li].vertex_index].co))-a
            fn=Vector(G(face.normal))
            if abs(fn.dot(v))>.90:
                uv.data[li].uv=(q.dot(u.normalized())/tile[0],q.dot(w.normalized())/tile[1])
            else:
                cross=w.normalized() if abs(fn.dot(u.normalized()))>.7 else u.normalized()
                uv.data[li].uv=(q.dot(cross)/tile[0],q.dot(v)/tile[1])
    return o

def cyl(name,center,radius,depth,axis='y',mat=WOOD,group='machinery_fixed',segments=32,collision='block'):
    c=Vector(center);ax={'x':Vector((1,0,0)),'y':Vector((0,1,0)),'z':Vector((0,0,1))}[axis]
    u={'x':Vector((0,1,0)),'y':Vector((1,0,0)),'z':Vector((1,0,0))}[axis];v=ax.cross(u)
    vs=[tuple(c+ax*d+radius*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))) for d in [-depth/2,depth/2] for i in range(segments)]
    fs=[tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]+[(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    return mesh(name,vs,fs,mat,group,collision,.003)

def ring(name,c,outer,inner,width,axis='x',mat=WOOD,group='waterwheel',segments=64,collision='none'):
    c=Vector(c);ax={'x':Vector((1,0,0)),'y':Vector((0,1,0)),'z':Vector((0,0,1))}[axis]
    u=Vector((0,1,0)) if axis=='x' else Vector((1,0,0));v=ax.cross(u)
    vs=[tuple(c+ax*d+r*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))) for d,r in [(-width/2,outer),(-width/2,inner),(width/2,outer),(width/2,inner)] for i in range(segments)]
    fs=[]
    for i in range(segments):
        j=(i+1)%segments
        fs.extend([(i,j,j+segments,i+segments),(i+2*segments,i+3*segments,j+3*segments,j+2*segments),(i,i+2*segments,j+2*segments,j),(i+segments,j+segments,j+3*segments,i+3*segments)])
    return mesh(name,vs,fs,mat,group,collision)

OPENINGS=[]
def wall(side,level,holes):
    y0,y1=(0,3.8) if level==0 else (3.8,6.7)
    cross=side in ['front','back'];pos=5.4 if side in ['front','right'] else -5.4
    length=10.8 if cross else 10.12
    us={-length/2,length/2};ys={y0,y1}
    if level==0:ys.add(1.05)
    for h in holes:us.update([h[0]-h[1]/2,h[0]+h[1]/2]);ys.update([h[2],h[2]+h[3]])
    us=sorted(us);ys=sorted(ys)
    for i,(a,b) in enumerate(zip(us,us[1:])):
        for j,(lo,hi) in enumerate(zip(ys,ys[1:])):
            if any(h[0]-h[1]/2-1e-6<(a+b)/2<h[0]+h[1]/2+1e-6 and h[2]-1e-6<(lo+hi)/2<h[2]+h[3]+1e-6 for h in holes):continue
            p=((a+b)/2,(lo+hi)/2,pos) if cross else (pos,(lo+hi)/2,(a+b)/2)
            size=(b-a,hi-lo,.34) if cross else (.34,hi-lo,b-a)
            box(f'{side}_L{level}_wall_{i}_{j}',p,size,STONE if hi<=1.051 else PLASTER,f'exterior_l{level}',bevel=0)
    for idx,h in enumerate(holes):
        u,w,bottom,height,kind=h
        OPENINGS.append({'side':side,'floor':level,'u':u,'width':w,'bottom':bottom,'height':height,'kind':kind})
        if kind=='shaft':continue
        def P(a,y,offset=0):return (a,y,pos+offset) if cross else (pos+offset,y,a)
        g=f'timber_l{level}';sgn=1 if pos>0 else -1
        beam(f'{side}_{level}_{idx}_lintel',P(u-w/2-.15,bottom+height+.08,sgn*.10),P(u+w/2+.15,bottom+height+.08,sgn*.10),.21,.28,WOOD,g)
        for s in [-1,1]:beam(f'{side}_{level}_{idx}_jamb{s}',P(u+s*(w/2+.065),bottom),P(u+s*(w/2+.065),bottom+height),.13,.30,WOOD,g)
        if kind=='window':
            beam(f'{side}_{level}_{idx}_sill',P(u-w/2-.15,bottom-.055,sgn*.04),P(u+w/2+.15,bottom-.055,sgn*.04),.16,.44,STONE,g)
            wg=f'windows_l{level}'
            for s in [-1,0,1]:beam(f'{side}_{level}_{idx}_mullion{s}',P(u+s*(w/2-.04),bottom+.02),P(u+s*(w/2-.04),bottom+height-.02),.045,.06,WOOD,wg,'none')
            for yy in [bottom+.03,bottom+height/2,bottom+height-.03]:beam(f'{side}_{level}_{idx}_transom{yy}',P(u-w/2,yy),P(u+w/2,yy),.045,.06,WOOD,wg,'none')
            p=P(u,bottom+height/2);size=(w-.06,height-.06,.008) if cross else (.008,height-.06,w-.06)
            box(f'{side}_{level}_{idx}_glass',p,size,GLASS,wg,'none',0)

# A solid, under-floor foundation; the wheel channel is outside its footprint.
box('Foundation_raft',(0,-.27,0),(10.8,.54,10.8),STONE,'foundation','walk',.015)
# Separate river-side foundation modules. The reported polygons are the actual
# bottom-face contact, not the assembly AABB. Water and terrain remain untouched.
FOUNDATION_MODULES=[]
def river_footing(group,x0,x1,z0,z1,bottom,top):
    box(group+'_masonry',((x0+x1)/2,(bottom+top)/2,(z0+z1)/2),(x1-x0,top-bottom,z1-z0),STONE,group,'block',0)
    FOUNDATION_MODULES.append({'group':group,'support_polygon_xz':[[x0,z0],[x1,z0],[x1,z1],[x0,z1]],'bottom_y':bottom,'top_y':top,'origin':[0,0,0],'adjustment':'Independent rigid module; shorten or extend beneath existing raft to fit surveyed bank. Do not move or fill the riverbed.'})
river_footing('river_foundation_east',4.45,5.65,-5.65,5.65,-1.70,-.48)
river_footing('river_foundation_west',-5.65,-4.65,-5.65,5.65,-1.70,-.48)
river_footing('river_foundation_front',-4.65,4.45,5.05,5.65,-1.70,-.48)
river_footing('river_foundation_rear',-4.65,4.45,-5.65,-5.05,-1.70,-.48)
river_footing('river_foundation_inner_pier_front',-3.22,-2.42,2.20,3.00,-1.70,-.48)
river_footing('river_foundation_inner_pier_rear',-3.22,-2.42,-3.90,-3.10,-1.70,-.48)
river_footing('river_foundation_outer_bearing',8.00,8.60,-.64,.64,-1.95,-1.32)
for side in ['front','back','left','right']:
    if side=='front':holes=[(-1.5,2.4,0,3.0,'door'),(2.55,1.4,1.25,1.65,'window')]
    elif side=='back':holes=[(-2.2,1.6,0,2.8,'door'),(2.8,1.3,1.35,1.55,'window')]
    elif side=='right':holes=[(-3.45,1.25,1.35,1.5,'window'),(0,1.15,.55,1.1,'shaft'),(3.4,1.25,1.35,1.5,'window')]
    else:holes=[(-3.7,1.25,1.45,1.45,'window'),(3.3,1.25,1.45,1.45,'window')]
    wall(side,0,holes)
    wall(side,1,[(-3.2,1.35,4.65,1.5,'window'),(0,1.35,4.65,1.5,'window'),(3.2,1.35,4.65,1.5,'window')])

# Timber frames split at floor height and all openings; upper diagonal braces do not cross windows.
for floor,lo,hi in [(0,0,3.8),(1,3.8,6.7)]:
    g=f'timber_l{floor}'
    for x in [-5.4,5.4]:
        for z in [-5.4,-1.7,1.7,5.4]:beam(f'post_x{x}_z{z}_L{floor}',(x,lo,z),(x,hi,z),.22,.22,WOOD,g)
    for z in [-5.4,5.4]:
        for x in [-5.4,-3.0,.0,1.55,5.4]:
            # Front door occupies [-2.7,-.3]; no timber crosses its clear opening.
            if floor==0 and z==-5.4 and x==-3.0:continue
            beam(f'gable_post_{x}_{z}_L{floor}',(x,lo,z),(x,hi,z),.22,.22,WOOD,g)
    for z in [-5.4,5.4]:beam(f'end_plate_{z}_L{floor}',(-5.5,hi-.12,z),(5.5,hi-.12,z),.26,.27,WOOD,g)
    for x in [-5.4,5.4]:beam(f'side_plate_{x}_L{floor}',(x,hi-.12,-5.5),(x,hi-.12,5.5),.26,.27,WOOD,g)
    if floor==1:
        for z in [-5.44,5.44]:
            for a,b in [(-5.25,-4.05),(4.05,5.25)]:beam(f'brace_{z}_{a}',(a,4.0,z),(b,6.4,z),.14,.14,WOOD,g)
        for x in [-5.44,5.44]:
            for a,b in [(-5.15,-4.05),(4.05,5.15)]:beam(f'brace_side{x}_{a}',(x,4.0,a),(x,6.4,b),.14,.14,WOOD,g)

# Upper plank floor: a real stairwell and shaft aperture are omitted from its solid mesh.
stair_hole=(-4.90,-2.95,-4.20,3.15)
shaft_hole=(2.99,3.55,-.28,.28)
xs=sorted({-5.23,5.23,stair_hole[0],stair_hole[1],shaft_hole[0],shaft_hole[1]})
zs=sorted({-5.23,5.23,stair_hole[2],stair_hole[3],shaft_hole[2],shaft_hole[3]})
for i,(a,b) in enumerate(zip(xs,xs[1:])):
    for j,(c,d) in enumerate(zip(zs,zs[1:])):
        mx,mz=(a+b)/2,(c+d)/2
        if any(h[0]<mx<h[1] and h[2]<mz<h[3] for h in [stair_hole,shaft_hole]):continue
        box(f'floor1_{i}_{j}',(mx,3.69,mz),(b-a,.22,d-c),WOOD,'floor_l1','walk',0)
for z in [-4.7,-2.4,0,2.4,4.7]:
    beam(f'floor_joist_{z}',(-2.9,3.43,z),(5.23,3.43,z),.22,.25,WOOD,'timber_l0')
for x in [-2.82,4.6]:
    beam(f'floor_girder_{x}',(x,3.24,-5.15),(x,3.24,5.15),.30,.30,WOOD,'timber_l0')
    for z in [-3.5,2.6 if x==-2.82 else 3.5]:beam(f'floor_support_{x}_{z}',(x,0,z),(x,3.4,z),.28,.28,WOOD,'timber_l0')
# The relocated front post still seats under the same longitudinal girder.
# Two knee braces resist racking and support the girder above pedestrian height.
for z in [1.8,3.4]:beam(f'front_post_knee_{z}',(-2.82,2.55,2.6),(-2.82,3.24,z),.14,.18,WOOD,'timber_l0')

# Third person stairs: 1.65m clear tread, 20 x .19m rise / .35m run.
for i in range(20):
    y=(i+1)*.19;z=3.0-(i+.5)*.35
    box(f'stair_tread_{i:02}',(-3.94,y-.065,z),(1.65,.13,.36),WOOD,'stairs','walk',.005)
box('stair_top_landing',(-3.94,3.69,-4.15),(1.90,.22,.42),WOOD,'floor_l1','walk',0)
for x in [-4.80,-3.08]:
    beam(f'stair_stringer{x}',(x,.04,3.12),(x,3.69,-4.02),.15,.28,WOOD,'stairs')
    beam(f'stair_hand_rail{x}',(x,1.12,3.0),(x,4.84,-3.99),.085,.085,WOOD,'stairs')
    for i in [0,4,8,12,16,19]:
        y=(i+1)*.19;z=3.0-(i+.5)*.35
        beam(f'stair_baluster{x}_{i}',(x,y,z),(x,y+1.0,z),.065,.065,WOOD,'stairs')
for z in [3.2]:
    beam('well_guard_top',(-4.9,4.9,z),(-2.95,4.9,z),.085,.085,WOOD,'rails_l1')
    for x in [-4.9,-4.4,-3.9,-3.4,-2.95]:beam(f'well_guard{x}',(x,3.8,z),(x,4.9,z),.065,.065,WOOD,'rails_l1')
for x in [-4.91,-2.94]:
    beam(f'well_rail{x}',(x,4.9,-4.18),(x,4.9,3.19),.08,.08,WOOD,'rails_l1')
    for i in range(13):
        z=-4.05+i*.59;beam(f'well_baluster{x}_{i}',(x,3.8,z),(x,4.9,z),.055,.055,WOOD,'rails_l1')

# Gable masonry and complete roof, with a continuous projecting eave and ridge cap.
for z in [-5.4,5.4]:
    vs=[(x,y,zz) for zz in [z-.17,z+.17] for x,y in [(-5.4,6.7),(5.4,6.7),(0,9.25)]]
    mesh(f'gable_{z}',vs,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],PLASTER,'exterior_l1')
    beam(f'gable_king_{z}',(0,6.6,z),(0,9.25,z),.18,.20,WOOD,'timber_l1')
    for s in [-1,1]:beam(f'gable_diagonal_{z}_{s}',(s*5.4,6.7,z),(0,9.25,z),.20,.24,WOOD,'timber_l1')
for side in [-1,1]:
    x=side*5.95;y=6.58
    vs=[(0,9.46,-5.95),(x,y,-5.95),(x,y,5.95),(0,9.46,5.95),(0,9.30,-5.95),(x,y-.16,-5.95),(x,y-.16,5.95),(0,9.30,5.95)]
    o=mesh(f'roof_slope_{side}',vs,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],ROOF,'roof')
    o.data.materials.append(WOOD)
    for face in o.data.polygons:
        if face.index!=0:face.material_index=1
    uv=o.data.uv_layers.active
    slope=(Vector((5.95,6.58))-Vector((0,9.46))).length
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            p=G(o.data.vertices[o.data.loops[li].vertex_index].co)
            uv.data[li].uv=((p[2]/1.0,(abs(p[0])/5.95*slope)/.72) if poly.material_index==0 else (abs(p[0])/.8,p[2]/2.4))
    # Actual 30 mm timber roof boarding beneath the tile layer. Board grain runs
    # parallel to the eave and spans the rafters; 2 mm joints remain visible.
    for i in range(27):
        a=i/27;b=(i+1)/27-.002/slope
        xa=side*5.95*a;xb=side*5.95*b
        ya=9.30-2.88*a;yb=9.30-2.88*b
        deck=[(xa,ya,-5.95),(xb,yb,-5.95),(xb,yb,5.95),(xa,ya,5.95),
              (xa,ya-.03,-5.95),(xb,yb-.03,-5.95),(xb,yb-.03,5.95),(xa,ya-.03,5.95)]
        mesh(f'roof_boarding_{side}_{i:02}',deck,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],WOOD,'roof',uv_axes=(0,2))
    beam(f'eave_fascia_{side}',(x,6.51,-5.98),(x,6.51,5.98),.16,.19,WOOD,'roof')
for z in [-5.98,5.98]:
    for s in [-1,1]:beam(f'barge_board_{z}_{s}',(s*5.96,6.55,z),(0,9.44,z),.18,.22,WOOD,'roof')
for i in range(32):cyl(f'ridge_cap_{i:02}',(0,9.46,-5.76+i*.37),.13,.40,'z',ROOF,'roof',12)
for z in [-4.8,0,4.8]:
    beam(f'truss_tie_{z}',(-5.1,6.53,z),(5.1,6.53,z),.22,.28,WOOD,'roof_trusses')
    for s in [-1,1]:beam(f'truss_rafter_{z}_{s}',(s*5.35,6.62,z),(0,9.23,z),.20,.24,WOOD,'roof_trusses')
    beam(f'truss_king_{z}',(0,6.53,z),(0,9.23,z),.18,.18,WOOD,'roof_trusses')

def door(name,hinge,width,height,sign):
    g='door_'+name;root(g,0,'door',hinge)
    x,y,z=hinge;cx=x+sign*width/2
    box(name+'_core',(cx,y+height/2,z),(width,.0+height,.09),WOOD,g,'block',.008)
    for i in range(6):
        xx=x+sign*((i+.5)*width/6)
        box(name+f'_board{i}',(xx,y+height/2,z+.051),(width/6-.006,height-.04,.016),WOOD,g,'block',.002)
    for yy in [.38,height-.38]:
        box(name+f'_iron_strap{yy}',(cx,y+yy,z+.069),(width-.06,.075,.018),IRON,g,'block',.004)
        cyl(name+f'_hinge{yy}',(x,y+yy,z+.055),.040,.20,'y',IRON,g,16)
        for i in [0,2,4,5]:cyl(name+f'_rivet{yy}_{i}',(x+sign*(.06+i*(width-.12)/5),y+yy,z+.081),.018,.018,'z',IRON,g,8)
    beam(name+'_brace',(x+sign*.12,y+.22,z-.06),(x+sign*(width-.12),y+height-.22,z-.06),.10,.055,WOOD,g)
    beam(name+'_pull',(x+sign*(width-.18),y+1.05,z+.13),(x+sign*(width-.18),y+1.31,z+.13),.035,.035,IRON,g)
    ROOTS[g]['door_angle']=90.*sign;ROOTS[g]['door_pivot_godot']=list(hinge)
door('front_left',(-2.68,.025,5.4),1.17,2.94,1)
door('front_right',(-.32,.025,5.4),1.17,2.94,-1)
door('rear_service',(-2.98,.025,-5.4),1.56,2.74,1)

# Unobstructed entrance landing and weather porch, with visible diagonal bracing.
box('porch_landing',(-1.5,-.09,6.27),(3.9,.18,1.75),STONE,'porch','walk',.012)
box('porch_low_step',(-1.5,-.18,7.30),(3.9,.18,.45),STONE,'porch','walk',.012)
for x in [-3.30,.30]:
    box(f'porch_post_base{x}',(x,.18,7.05),(.36,.36,.36),STONE,'porch')
    beam(f'porch_post{x}',(x,.36,7.05),(x,3.35,7.05),.17,.17,WOOD,'porch')
    beam(f'porch_brace{x}',(x,2.65,7.05),(x,3.35,6.35),.12,.12,WOOD,'porch')
beam('porch_header',(-3.50,3.35,7.05),(.50,3.35,7.05),.18,.22,WOOD,'porch')
porch_roof=mesh('porch_shed_roof',[(-3.55,3.75,5.34),(.55,3.75,5.34),(.55,3.42,7.35),(-3.55,3.42,7.35),(-3.55,3.64,5.34),(.55,3.64,5.34),(.55,3.31,7.35),(-3.55,3.31,7.35)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],ROOF,'porch')
porch_roof.data.materials.append(WOOD)
for face in porch_roof.data.polygons:
    if face.index!=0:face.material_index=1

# Undershot wheel, open spokes, replaceable straight paddles, iron restraint bands.
cx,cy,cz=6.85,1.1,0
for xx in [cx-.64,cx+.64]:
    ring(f'wheel_oak_rim_{xx}',(xx,cy,cz),2.21,2.00,.16,'x',WOOD,'waterwheel',80)
    ring(f'wheel_iron_band_{xx}',(xx,cy,cz),2.225,2.205,.18,'x',IRON,'waterwheel',80)
    cyl(f'wheel_hub_{xx}',(xx,cy,0),.29,.29,'x',WOOD,'waterwheel',32,'none')
    for i in range(8):
        a=i*math.tau/8
        beam(f'wheel_spoke_{xx}_{i}',(xx,cy+.20*math.cos(a),.20*math.sin(a)),(xx,cy+2.10*math.cos(a),2.10*math.sin(a)),.16,.20,WOOD,'waterwheel','none')
for i in range(24):
    a=i*math.tau/24
    r=Vector((0,math.cos(a),math.sin(a)));t=Vector((0,-math.sin(a),math.cos(a)));center=Vector((cx,cy,0))+r*2.13
    vs=[tuple(center+Vector((sx*.75,0,0))+r*sr*.17+t*st*.048) for sx,sr,st in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    mesh(f'wheel_paddle_{i:02}',vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],WOOD,'waterwheel','none',.006)
    for xx in [cx-.64,cx+.64]:cyl(f'paddle_bolt_{i}_{xx}',(xx,cy+2.13*math.cos(a),2.13*math.sin(a)),.028,.20,'x',IRON,'waterwheel',8,'none')
cyl('waterwheel_axle',(5.75,1.1,0),.17,5.65,'x',IRON,'drive_axle',48,'none')
for x in [5.13,8.3]:
    box(f'bearing_masonry{x}',(x,-.37,0),(.58,2.06,.88),STONE,'wheel_support')
    box(f'bearing_timber{x}',(x,.76,0),(.70,.23,.64),WOOD,'wheel_support')
    # A true annular bearing fits around, rather than solidly intersecting, the shaft.
    ring(f'journal_bearing{x}',(x,1.10,0),.26,.185,.32,'x',IRON,'wheel_support',40,'block')
    for z in [-.32,.32]:beam(f'bearing_brace{x}_{z}',(x,.65,z),(x,1.1,z/2),.08,.08,IRON,'wheel_support')

# Pit wheel -> wallower -> great spur -> stone nut -> runner stone.
ring('pitwheel_rim',(3.6,1.1,0),.98,.76,.18,'x',WOOD,'pitwheel',64)
for i in range(8):
    a=i*math.tau/8;beam(f'pit_spoke{i}',(3.6,1.1,0),(3.6,1.1+.87*math.cos(a),.87*math.sin(a)),.12,.13,WOOD,'pitwheel','none')
for i in range(48):
    a=i*math.tau/48
    cyl(f'pit_face_peg{i}',(3.40,1.1+.88*math.cos(a),.88*math.sin(a)),.038,.26,'x',WOOD,'pitwheel',8,'none')
for yy in [1.84,2.26]:ring(f'wallower_disk{yy}',(3.27,yy,0),.29,.12,.09,'y',WOOD,'wallower',32)
for i in range(12):
    a=i*math.tau/12;cyl(f'wallower_stave{i}',(3.27+.245*math.cos(a),2.05,.245*math.sin(a)),.035,.42,'y',WOOD,'wallower',8,'none')
cyl('upright_shaft',(3.27,2.20,0),.115,3.18,'y',IRON,'great_spur',24,'none')
def spur(name,c,r,teeth,group):
    ring(name+'_ring',c,r-.04,r-.25,.17,'y',WOOD,group,64)
    for i in range(8):
        a=i*math.tau/8;beam(name+f'_spoke{i}',c,(c[0]+(r-.16)*math.cos(a),c[1],c[2]+(r-.16)*math.sin(a)),.12,.14,WOOD,group,'none')
    for i in range(teeth):
        a=(i+.5)*math.tau/teeth;d=Vector((math.cos(a),0,math.sin(a)))
        beam(name+f'_tooth{i}',tuple(Vector(c)+d*(r-.07)),tuple(Vector(c)+d*(r+.055)),.075,.16,WOOD,group,'none')
spur('great_spur',(3.27,2.9,0),1.15,60,'great_spur')
spur('stone_nut',(1.75,2.9,0),.37,20,'stone_nut')
cyl('stone_spindle',(1.75,3.38,0),.075,1.65,'y',IRON,'stone_nut',24,'none')
for x,z in [(2.9,-1.65),(4.6,-1.65),(2.9,1.65),(4.6,1.65)]:beam(f'mechanism_frame_{x}_{z}',(x,0,z),(x,3.40,z),.22,.22,WOOD,'machinery_fixed')
for z in [-1.65,1.65]:beam(f'mechanism_frame_top{z}',(2.75,3.37,z),(4.75,3.37,z),.23,.23,WOOD,'machinery_fixed')
for x in [2.9,4.6]:beam(f'mechanism_frame_tie{x}',(x,3.37,-1.70),(x,3.37,1.70),.22,.22,WOOD,'machinery_fixed')
# Lower gear guard encloses machinery, leaves entry and stair paths outside it.
for z in [-2.0,2.0]:
    beam(f'gear_guard_rail{z}',(.55,1.1,z),(4.85,1.1,z),.08,.08,WOOD,'machinery_guard')
    for x in [.55,1.55,2.55,3.55,4.85]:beam(f'gear_guard_post{x}_{z}',(x,0,z),(x,1.12,z),.075,.075,WOOD,'machinery_guard')
beam('gear_guard_west',(.55,1.1,-2.0),(.55,1.1,2.0),.08,.08,WOOD,'machinery_guard')
for z in [-2,-1,0,1,2]:beam(f'gear_guard_west_post{z}',(.55,0,z),(.55,1.12,z),.07,.07,WOOD,'machinery_guard')

cyl('bedstone',(1.75,3.94,0),.81,.28,'y',STONE,'milling_furniture',64)
cyl('runnerstone',(1.75,4.19,0),.81,.20,'y',STONE,'runner_stone',64,'none')
ring('runnerstone_iron_band',(1.75,4.19,0),.818,.802,.12,'y',IRON,'runner_stone',64)
ring('stone_tun',(1.75,4.15,0),.92,.86,.60,'y',WOOD,'milling_furniture',64,'block')
for x in [1.0,2.5]:
    for z in [-.70,.70]:beam(f'hopper_leg{x}_{z}',(x,3.80,z),(x,5.48,z),.085,.085,WOOD,'milling_furniture')
for z in [-.70,.70]:beam(f'hopper_frame{z}',(.95,5.30,z),(2.55,5.30,z),.11,.11,WOOD,'milling_furniture')
# Open-top hollow timber hopper, thin boards joining a small real outlet.
top=[(.99,5.50,-.72),(2.51,5.50,-.72),(2.51,5.50,.72),(.99,5.50,.72)]
bot=[(1.60,4.70,-.15),(1.90,4.70,-.15),(1.90,4.70,.15),(1.60,4.70,.15)]
for i in range(4):
    j=(i+1)%4;outer=[top[i],top[j],bot[j],bot[i]];inner=[(x+(1.75-x)*.035,y,z-z*.035) for x,y,z in outer]
    mesh(f'hopper_board{i}',outer+inner,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],WOOD,'milling_furniture','block',0)
beam('grain_feed_shoe',(1.75,4.66,0),(1.75,4.42,.20),.17,.12,WOOD,'milling_furniture')
beam('flour_outlet',(1.75,4.04,.84),(1.75,3.84,1.32),.24,.18,WOOD,'milling_furniture')

# Useful receiving/sack space, a bench and grain bins; keep the centre path open.
for i in range(3):
    x=1.3+i*1.13;z=-4.3
    box(f'grain_bin_floor{i}',(x,3.86,z),(1.04,.12,1.30),WOOD,'milling_furniture')
    for s in [-1,1]:box(f'grain_bin_side{i}_{s}',(x+s*.49,4.35,z),(.06,.95,1.30),WOOD,'milling_furniture')
    for s in [-1,1]:box(f'grain_bin_end{i}_{s}',(x,4.35,z+s*.62),(1.02,.95,.06),WOOD,'milling_furniture')
box('packing_bench_top',(-.55,.86,-4.25),(2.35,.12,.85),WOOD,'storage')
for x in [-1.48,.38]:
    for z in [-4.53,-3.97]:beam(f'bench_leg{x}_{z}',(x,0,z),(x,.80,z),.12,.12,WOOD,'storage')
for i in range(5):
    x=1.25+(i%3)*.75;z=3.9+(i//3)*.58
    # Turned sack silhouette with a puckered tie, stored on a low timber pallet.
    profile=[(.18,.04),(.25,.06),(.34,.22),(.33,.58),(.25,.76),(.075,.85),(.095,.90),(.02,.94)]
    vs=[(x+r*math.cos(j*math.tau/20)*(1+.025*math.sin(j*5+i)),y,z+r*math.sin(j*math.tau/20)) for r,y in profile for j in range(20)]
    fs=[]
    for row in range(len(profile)-1):
        for j in range(20):k=row*20+j;n=row*20+(j+1)%20;fs.append((k,n,n+20,k+20))
    fs.extend([tuple(range(19,-1,-1)),tuple(range(140,160))])
    mesh(f'grain_sack{i}',vs,fs,FLOUR,'storage','block')

# Preserve master part hierarchy; game export joins only static semantic groups.
bpy.context.view_layer.update()
ASSEMBLY=bpy.data.objects.new('Axel_Watermill',None);bpy.context.collection.objects.link(ASSEMBLY)
ASSEMBLY['uuid']='axel_watermill_20261016';ASSEMBLY['asset_id']='axel_watermill'
ASSEMBLY['rmmo_model_components']={'version':1}
ASSEMBLY['rmmo_building']={'version':1,'regions':[
    {'id':'mill_ground','floor':0,'min':[-5.23,0.,-5.23],'max':[5.23,3.42,5.23]},
    {'id':'mill_stone_floor','floor':1,'min':[-5.23,3.8,-5.23],'max':[5.23,6.48,5.23]}]}
def part_metadata(o):
    group=o['semantic_group'];floor=int(o['author_floor']);role=o['author_role']
    if role=='rotor' or group.startswith('machinery'):role='mechanism'
    if group in ['storage','milling_furniture']:role='furniture'
    o['rmmo_part']={'floor':floor,'floor_y':3.8 if floor==1 else 0.,'role':role,'part':group}
    if any(m and m.name=='Mill thin clear glass' for m in o.data.materials):
        o['rmmo_tinted_glass']={'version':1,'materials':{'Mill thin clear glass':{'transmittance':[.97,.985,.98],'roughness':.09}}}
for g,r in ROOTS.items():
    r.parent=ASSEMBLY
    r['project_design']='Supplementary design; not official anime dimensions'
    r['source_reference']='Winchester undershot / National Trust mill mechanics'
for o in MESHES:part_metadata(o)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(DEST/'axel_watermill_master.blend'))

groups={}
for o in MESHES:groups.setdefault((o['semantic_group'],o['rmmo_collision']),[]).append(o)
for (g,collision),objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object
    o.name='watermill_'+g+('_'+collision if len([k for k in groups if k[0]==g])>1 else '')
    o['uuid']='watermill_'+g+'_'+collision
    # Set mesh origin at group pivot; transforms remain exact for hinges/rotors.
    cursor=bpy.context.scene.cursor.location.copy();bpy.context.scene.cursor.location=ROOTS[g].location
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.context.scene.cursor.location=cursor
    o['author_floor']=ROOTS[g]['author_floor'];o['author_role']=ROOTS[g]['author_role'];o['rmmo_collision']=collision
    part_metadata(o)
    if g.startswith('door_'):
        o['rmmo_hinge']={'id':g,'angle':ROOTS[g]['door_angle'],'open':0.,'pivot':[0.,0.,0.]}
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    tri=o.modifiers.new('Deterministic export triangulation','TRIANGULATE')
    tri.quad_method='BEAUTY';tri.ngon_method='BEAUTY'
    bpy.ops.object.modifier_apply(modifier=tri.name)
    # Thick roof edges and very small bevel corners need a real 2-D cap mapping.
    uv=o.data.uv_layers.active
    for face in o.data.polygons:
        a,b,c=[uv.data[i].uv.copy() for i in face.loop_indices]
        if abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))<1e-6 or min((b-a).length,(c-b).length,(a-c).length)<1e-5:
            vv=[o.data.vertices[o.data.loops[i].vertex_index].co for i in face.loop_indices]
            n=G((vv[1]-vv[0]).cross(vv[2]-vv[0]).normalized());axis=max(range(3),key=lambda q:abs(n[q]));axes=((2,1) if axis==0 else (0,2) if axis==1 else (0,1))
            tile=list(o.data.materials[face.material_index].get('uv_tile_m',[1,1]))
            coords=[G(o.data.vertices[o.data.loops[i].vertex_index].co) for i in face.loop_indices]
            anchor=coords[0]
            for li,p in zip(face.loop_indices,coords):uv.data[li].uv=((p[axes[0]]-anchor[axes[0]])/tile[0],(p[axes[1]]-anchor[axes[1]])/tile[1])
    o.data.calc_loop_triangles()
    # Compact Blender-generated unused material slots after group joining.
    bpy.ops.object.material_slot_remove_unused()

EXPORTS=[]
def export(name,selection=None,root_pivot=None):
    bpy.ops.object.select_all(action='DESELECT')
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and (selection is None or o.get('semantic_group') in selection)]
    # Standalone components use their connection/rotation pivot at local origin.
    moved=[]
    if root_pivot is not None:
        offset=C(root_pivot)
        for o in objects:moved.append((o,o.matrix_world.copy()));mw=o.matrix_world.copy();mw.translation-=offset;o.matrix_world=mw
    for o in objects:o.select_set(True)
    ASSEMBLY.select_set(True)
    building_metadata=ASSEMBLY['rmmo_building'].to_dict() if 'rmmo_building' in ASSEMBLY else None
    if selection is not None and 'rmmo_building' in ASSEMBLY:del ASSEMBLY['rmmo_building']
    path=DEST/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_apply=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False)
    if building_metadata is not None:ASSEMBLY['rmmo_building']=building_metadata
    for o,mw in moved:o.matrix_world=mw
    j={'file':str(path),'sha256':sha(path),'bytes':path.stat().st_size,'groups':selection or list(ROOTS),'origin':root_pivot or [0,0,0]}
    EXPORTS.append(j)
    return path
export('axel_watermill')
export('axel_watermill_waterwheel',['waterwheel'],(6.85,1.1,0))
export('axel_watermill_drive_axle',['drive_axle'],(6.85,1.1,0))
export('axel_watermill_wheel_support',['wheel_support'])
export('axel_watermill_river_foundation',[m['group'] for m in FOUNDATION_MODULES])

parts=[]
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    o.data.calc_loop_triangles();points=[o.matrix_world@Vector(v) for v in o.bound_box]
    pts=[G(p) for p in points]
    parts.append({'name':o.name,'uuid':o['uuid'],'group':o['semantic_group'],'floor':o['author_floor'],'role':o['author_role'],'collision':o['rmmo_collision'],'triangles':len(o.data.loop_triangles),'materials':[m.name for m in o.data.materials],'origin':G(o.matrix_world.translation),'bounds_min':[min(v[i] for v in pts) for i in range(3)],'bounds_max':[max(v[i] for v in pts) for i in range(3)]})
manifest={'id':'axel_watermill','version':VERSION,'stage':'candidate_geometry_materials_cpu_authored','master':{'file':str(DEST/'axel_watermill_master.blend'),'sha256':sha(DEST/'axel_watermill_master.blend')},'builder':{'file':str(Path(__file__).resolve()),'sha256':sha(__file__)},'exports':EXPORTS,'parts':parts,'material_sources':MATERIAL_SOURCES,'openings':OPENINGS,'stairs':{'clear_width':1.65,'rise':.19,'tread':.35,'count':20,'floor_height':3.8,'hole':list(stair_hole)},'geometry_triangles':sum(p['triangles'] for p in parts),'map_modified':False,'native_import':'PENDING_ROOT','visual_review':'PENDING_ROOT','formal_library':'PENDING_ROOT','mechanism':{'input_axis':[1,0,0],'input_pivot':[6.85,1.1,0],'rotation_design':'Flow +Z to -Z drives positive X rotation','parts':[{'group':'waterwheel','axis':[1,0,0],'ratio':1},{'group':'drive_axle','axis':[1,0,0],'ratio':1},{'group':'pitwheel','axis':[1,0,0],'ratio':1,'teeth':48},{'group':'wallower','axis':[0,1,0],'ratio':-4,'teeth':12},{'group':'great_spur','axis':[0,1,0],'ratio':-4,'teeth':60},{'group':'stone_nut','axis':[0,1,0],'ratio':12,'teeth':20},{'group':'runner_stone','axis':[0,1,0],'ratio':12}],'hydraulics':'Not simulated; contact requires scene-level water placement','runtime_motion':'Pending supported generic rotor contract; source nodes are pivoted, no unconsumed animation claims'}}
manifest['river_foundation']={'modules':FOUNDATION_MODULES,'lowest_base_y':-1.95,'highest_base_y':-1.70,'surveyed_world_floor_y':4.,'surveyed_world_water_y':3.,'surveyed_world_bed_range':[2.2,2.5241],'surveyed_body_terrain_range':[2.459865,3.942139],'surveyed_outer_bearing_terrain_y':2.200733,'world_base_range':[2.05,2.30],'actual_support_is_union_of_polygons':True,'continuous_water_corridor_xz':[5.75,-3.1,7.95,3.1],'wheel_sweep_x_range':[6.065,7.635],'minimum_foundation_to_sweep_x_clearance':.365,'terrain_modified':False,'placement_status':'Base levels and closed perimeter follow source-layout terrain survey. Exact final contact and river corridor remain runtime placement validation; no full-AABB bearing claim.'}
manifest['placement_anchor']={'origin_world':[305.422302246094,4.,199.890441894531],'yaw_degrees':-22.256907055609,'source':'Parent/source layout terrain sampling, 2026-10-16','outer_bearing_world_xz':[313.103912,203.034149],'local_downstream':[0,0,1]}
manifest['mechanism']['rotation_design']='Actual downstream is local +Z; water-contact lower paddles drive negative X rotation.'
manifest['mechanism']['input_drive_sign']=-1
manifest['v10_material_repairs']={'previous_version':'v9','glass':{'consumer':'scripts/world3d/tinted_glass.gd','transmittance':[.97,.985,.98],'roughness':.09,'fallback_alpha':.035},'plaster':{'definition':'walls/exterior_limewash','uv_tile_m':[.45,.45],'normal_strength':.18},'roof':{'underside':'oak timber','actual_boarding_count':54,'boarding_thickness_m':.03,'porch_underside':'oak timber'},'gpu_status':'PENDING_SAME_CAMERA_REVIEW'}
manifest['v11_access_repair']={'evidence':'review_artifacts/axel_landmarks_20261016/pipeline/http_56637590.json','failed_v10_local_feet':[-2.58353,.00284,3.93224],'standard_capsule_diameter':.6,'post_old_center_xz':[-2.82,3.5],'post_new_center_xz':[-2.82,2.6],'post_half_width':.14,'closed_front_door_unchanged':True,'double_open_left_leaf_tip_z':4.23,'nominal_leaf_to_post_clearance':1.49,'girder_unchanged':True,'knee_braces_bottom_y':2.55,'foundation_group':'river_foundation_inner_pier_front','route_local_feet':[[-1.5,0,6.6],[-1.5,0,5.4],[-1.5,0,4.0],[-2.1,0,3.95],[-3.94,0,3.95],[-3.94,0,3.35],[-3.94,.19,2.825],[-3.94,3.8,-3.825],[-3.94,3.8,-4.15],[-3.94,3.8,-4.7]],'runtime_controller_changed':False,'collisions_disabled':False,'status':'CPU candidate; actual HTTP capsule re-test pending'}
(DEST/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(REVIEW/'candidate_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('AXEL_WATERMILL_BUILT',json.dumps({'exports':EXPORTS,'triangles':manifest['geometry_triangles']}))
