"""S1 bridge-left dedicated residence; offline immutable Blender authoring.
Shared primitive behavior copied from reviewed S12 authoring, no S12 outputs modified.
All coordinates are Godot metres, +Y up, front +Z, origin body-ground center.
"""
import argparse, hashlib, json, math, shutil, sys
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Vector

P=argparse.ArgumentParser();P.add_argument('--version',default='v1');P.add_argument('--only',default='all')
A=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
BASE=Path('D:/code/rmmo_runtime/art_sources/s1_bridge_left_residence_20261017')
OUT=BASE/A.version;OUT.mkdir(parents=True,exist_ok=True)
LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials')
OBJECTS=[];ROOT=None;IMAGES={};INPUTS={};OPENINGS=[];MATS={};ASSETS=[]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def c(v):return (v[0],-v[2],v[1])
def g(v):return Vector((v[0],v[2],-v[1]))
def image(path,color=True):
    path=Path(path);key=(str(path),color)
    if key not in IMAGES:
        INPUTS[str(path)]={'sha256':sha(path),'bytes':path.stat().st_size}
        im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='sRGB' if color else 'Non-Color';im.pack();IMAGES[key]=im
    return IMAGES[key]
def mat(name,color=(1,1,1),rough=.8,metal=0,maps=None,normal=1):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1);m.use_backface_culling=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    for socket,path in (maps or {}).items():
        t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=image(path,socket=='Base Color')
        if socket=='Normal':
            n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=normal;m.node_tree.links.new(t.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],p.inputs['Normal'])
        else:m.node_tree.links.new(t.outputs['Color'],p.inputs[socket])
    MATS[name]=m;return m
def library_mat(key,name):
    folder=LIB/key;d=json.loads((folder/'material.json').read_text(encoding='utf-8'))['material']
    INPUTS[str(folder/'material.json')]={'sha256':sha(folder/'material.json')}
    maps={s:folder/d[k] for s,k in [('Base Color','texture_path'),('Normal','normal_path'),('Roughness','roughness_path')] if d.get(k)}
    return mat(name,rough=d.get('roughness',1),metal=d.get('metallic',0),maps=maps,normal=d.get('normal_strength',1))
def reset(name,building=False):
    global OBJECTS,ROOT,OPENINGS
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);OBJECTS=[];OPENINGS=[]
    ROOT=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ROOT)
    ROOT['asset_id']=name;ROOT['rmmo_project_supplement']=True
    if building:ROOT['rmmo_model_components']={'version':1}
    bpy.context.scene.unit_settings.system='METRIC'
def reg(o,name,m,floor=0,role='body',collision='block',part='shell',bevel=0):
    o.name=name;o.parent=ROOT;o['uuid']='s1_'+hashlib.sha256(name.encode()).hexdigest()[:24]
    o['rmmo_collision']=collision;o['rmmo_part']={'floor':floor,'floor_y':floor*3.25,'role':role,'part':part}
    o['semantic_group']=('50_' if role in ['roof','ceiling'] else '')+part
    if m:o.data.materials.append(m)
    if bevel:
        bpy.context.view_layer.objects.active=o
        mod=o.modifiers.new('Small worked edge','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
    OBJECTS.append(o);return o
def mesh(name,vs,fs,m,uv=None,smooth=False,**kw):
    data=bpy.data.meshes.new(name);data.from_pydata([c(p) for p in vs],[],fs);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);reg(o,name,m,**kw)
    for p in data.polygons:p.use_smooth=smooth
    if uv:
        layer=data.uv_layers.new(name='AuthoredUV')
        for loop in data.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    return o
def box(name,center,size,m,**kw):
    x,y,z=center;w,h,d=[v/2 for v in size]
    vs=[(x+a*w,y+b*h,z+cc*d) for a,b,cc in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],m,**kw)
def rod(name,a,b,r,m,segments=16,**kw):
    a,b=Vector(c(a)),Vector(c(b));v=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=v.length,location=(a+b)/2)
    o=bpy.context.object;o.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    reg(o,name,m,**kw)
    for face in o.data.polygons:face.use_smooth=len(face.vertices)==4
    return o
def beam(name,a,b,w,h,m,**kw):
    a,b=Vector(a),Vector(b);v=(b-a).normalized();cross=Vector((0,0,1)) if abs(v.z)<.9 else Vector((1,0,0))
    u=v.cross(cross).normalized()*w/2;t=v.cross(u).normalized()*h/2
    vs=[tuple(p+su*u+st*t) for p in [a,b] for su,st in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    return mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],m,**kw)
def prism(name,poly,axis,fixed,depth,m,**kw):
    n=len(poly)
    def point(u,v,d):return (u,v,d) if axis=='z' else (d,v,u)
    vs=[point(u,v,fixed+d) for d in [-depth/2,depth/2] for u,v in poly]
    return mesh(name,vs,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],m,**kw)
def cut(o,poly,axis,fixed,depth,name):
    tool=prism('CUT_'+name,poly,axis,fixed,depth,None,collision='none')
    bpy.context.view_layer.objects.active=o;mod=o.modifiers.new(name,'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=tool;bpy.ops.object.modifier_apply(modifier=mod.name)
    OBJECTS.remove(tool);bpy.data.objects.remove(tool,do_unlink=True)
    OPENINGS.append({'id':name,'axis':axis,'fixed':fixed,'polygon':poly,'wall':o.name})
def join(obs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    for old in obs[1:]:OBJECTS.remove(old)
    return o
def auto_uv(o):
    o.data.update()
    points=[g(o.matrix_world@v.co) for v in o.data.vertices]
    spans=[max(v[k] for v in points)-min(v[k] for v in points) for k in range(3)]
    grain=Vector((0,0,0));grain[spans.index(max(spans))]=1
    authored=bool(o.data.uv_layers)
    uv=o.data.uv_layers.active if authored else o.data.uv_layers.new(name='S1UV')
    uv.name='S1UV'
    for face in o.data.polygons:
        if authored:
            coords=[uv.data[li].uv.copy() for li in face.loop_indices]
            area=sum(a.x*b.y-a.y*b.x for a,b in zip(coords,coords[1:]+coords[:1]))
            if abs(area)>1e-12:continue
        n=g(face.normal);m=o.data.materials[face.material_index];roof=m==ROOF
        for li in face.loop_indices:
            p=g(o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co)
            if roof and abs(n.y)<.999:
                uphill=Vector((0,1,0))-n*n.y;uphill.normalize();across=uphill.cross(n).normalized();a,b=p.dot(across)/3,p.dot(uphill)/2.16
            else:
                a,b=(p.x,p.z) if abs(n.y)>.7 else ((p.z,p.y) if abs(n.x)>abs(n.z) else (p.x,p.y))
                if m==STONE:a/=2;b/=2
                if m==TRIM:a/=1;b/=1
                if m==WOOD:
                    along=grain-n*grain.dot(n)
                    if along.length>.01:
                        along.normalize();across=along.cross(n).normalized();a=p.dot(across)/.8;b=p.dot(along)/2.4
                    else:a/=.8;b/=.8
            uv.data[li].uv=(a,b)
def export(name,notes,anchors=None):
    path=OUT/(name+'.glb')
    if path.exists():raise RuntimeError('Immutable version already exists: '+str(path))
    for o in OBJECTS:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
        auto_uv(o)
    # Static groups may merge within one semantic part; hinges, glass and cloth stay separate.
    groups={}
    for o in OBJECTS:
        if o.get('rmmo_hinge') or o.get('rmmo_wind') or o.get('rmmo_tinted_glass'):continue
        p=o['rmmo_part'];key=(p['floor'],p['role'],p['part'],o['rmmo_collision']);groups.setdefault(key,[]).append(o)
    for key,obs in groups.items():
        if len(obs)>1:join(obs,name+'_'+('_'.join(map(str,key))))
    for o in OBJECTS:
        bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('Explicit triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
    master=OUT/(name+'_master.blend');bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_extras=True,export_animations=False,export_tangents=True,export_normals=True,export_cameras=False,export_lights=False)
    vs=[g(o.matrix_world@v.co) for o in OBJECTS for v in o.data.vertices]
    bounds={'min':[min(p[k] for p in vs) for k in range(3)],'max':[max(p[k] for p in vs) for k in range(3)]}
    row={'id':name,'path':str(path),'sha256':sha(path),'bytes':path.stat().st_size,'master':str(master),'master_sha256':sha(master),'bounds':bounds,'triangles':sum(len(o.data.polygons) for o in OBJECTS),'mesh_nodes':len(OBJECTS),'anchors':anchors or {},'notes':notes,'openings':OPENINGS,'status':'candidate_requires_runtime_review'}
    (OUT/(name+'_authoring.json')).write_text(json.dumps(row,indent=2,ensure_ascii=False),encoding='utf-8');ASSETS.append(row)


def rect(u,y,w,h):return [(u-w/2,y),(u+w/2,y),(u+w/2,y+h),(u-w/2,y+h)]
def window(wall,name,axis,fixed,u,y,w=.85,h=1.3,floor=1,outward=1,role='body'):
    cut(wall,rect(u,y,w,h),axis,fixed,1.0,name)
    def pos(a,b,off=0):return (a,b,fixed+off) if axis=='z' else (fixed+off,b,a)
    def bx(n,a,b,ww,hh,dd,m,off=0):return box(name+n,pos(a,b,off),(ww,hh,dd) if axis=='z' else (dd,hh,ww),m,floor=floor,role=role,collision='none',part='window_'+name,bevel=.008)
    for xx in [u-w/2-.07,u+w/2+.07]:bx('_stone_jamb_'+str(xx),xx,y+h/2,.14,h+.18,.20,TRIM,outward*.23)
    bx('_stone_sill',u,y-.07,w+.32,.14,.32,TRIM,outward*.26)
    bx('_lintel',u,y+h+.10,w+.34,.20,.30,TRIM if name.startswith('Single_tall') else WOOD,outward*.24)
    for xx in [u-w/2+.035,u+w/2-.035,u]:bx('_frame_v_'+str(xx),xx,y+h/2,.065,h,.09,WOOD,outward*.08)
    for yy in [y+.035,y+h*.5,y+h-.035]:bx('_frame_h_'+str(yy),u,yy,w,.06,.09,WOOD,outward*.08)
    poly=rect(u,y+.035,w-.075,h-.07);points=[pos(a,b,0) for a,b in poly]
    pane=mesh(name+'_clear_panes',points,[(0,1,2,3)],GLASS,floor=floor,role=role,collision='none',part='window_'+name)
    pane['rmmo_tinted_glass']={'version':1,'materials':{GLASS.name:{'transmittance':[.94,.97,.94],'roughness':.14}}}
def door(wall,name,axis,fixed,u,y,w=1.35,h=2.4,outward=1):
    cut(wall,rect(u,y,w,h),axis,fixed,1.0,name)
    def pos(a,b,off=0):return (a,b,fixed+off) if axis=='z' else (fixed+off,b,a)
    def bx(n,a,b,ww,hh,dd,m,off=0):return box(name+n,pos(a,b,off),(ww,hh,dd) if axis=='z' else (dd,hh,ww),m,role='door',part=name,bevel=.008)
    for x in [u-w/2-.09,u+w/2+.09]:bx('_fixed_jamb_'+str(x),x,y+h/2,.18,h+.15,.28,WOOD,outward*.25)['rmmo_part']['role']='body'
    bx('_fixed_lintel',u,y+h+.12,w+.4,.24,.32,WOOD,outward*.25)['rmmo_part']['role']='body'
    start=len(OBJECTS)
    for i in range(7):bx('_oak_plank_'+str(i),u-w/2+(i+.5)*w/7,y+h/2,w/7-.006,h-.035,.10,WOOD,outward*.06)
    for yy in [y+.4,y+h-.42]:
        bx('_strap_'+str(yy),u-.10,yy,w*.78,.08,.03,IRON,outward*.124)
        for dx in [-.4,-.1,.2]:bx('_rivet_'+str((yy,dx)),u+dx,yy,.025,.025,.02,BRASS,outward*.145)
        bx('_moving_hinge_'+str(yy),u-w/2+.02,yy,.075,.22,.075,IRON,outward*.13)
    bx('_latch_plate',u+w*.29,y+1.05,.12,.19,.026,IRON,outward*.13)
    bx('_handle',u+w*.29,y+1.05,.035,.14,.05,BRASS,outward*.20)
    leaf=join(OBJECTS[start:],name+'_moving_leaf');pivot=Vector(c(pos(u-w/2,y,outward*.06)))
    for v in leaf.data.vertices:v.co-=pivot
    leaf.location=pivot;leaf['rmmo_hinge']={'id':name,'pivot':[0,0,0],'angle':-100 if axis=='x' else 100,'open':0.0}
    for yy in [y+.4,y+h-.42]:bx('_fixed_hinge_'+str(yy),u-w/2-.035,yy,.07,.26,.08,IRON,outward*.13)['rmmo_part']['role']='body'

# Existing realistic authored/owned channels; no shared textures are changed.
STONE=library_mat('walls/stone_tiles_facade','S1 warm grey weathered stone masonry')
WOOD=library_mat('wood/solid_timber','S1 structural oak')
GM=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
ROOF=mat('S1 orange red round-tail clay tiles',rough=1,maps={s:GM/f for s,f in [('Base Color','guild_fishscale_large_repeat_color.png'),('Normal','guild_fishscale_large_repeat_normal.png'),('Roughness','guild_fishscale_large_repeat_roughness.png')]})
CLAY=mat('S1 solid clay ridge and cut edges',rough=1,maps={s:GM/f for s,f in [('Base Color','guild_baked_clay_plain_color.png'),('Normal','guild_baked_clay_plain_normal.png'),('Roughness','guild_baked_clay_plain_roughness.png')]},normal=.4)
TRIM=mat('S1 dressed pale limestone',rough=1,maps={s:GM/f for s,f in [('Base Color','guild_cut_limestone_mineral_color.png'),('Normal','guild_cut_limestone_micro_normal.png'),('Roughness','guild_cut_limestone_roughness.png')]},normal=.18)
IRON=mat('S1 blackened iron hardware',(.018,.014,.011),.62,.65)
BRASS=mat('S1 aged brass handle',(.30,.19,.055),.42,.8)
GLASS=mat('S1 clear residential glass',(.68,.75,.70),.14)
bs=next(n for n in GLASS.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Alpha'].default_value=.22;bs.inputs['Transmission Weight'].default_value=.8;GLASS.surface_render_method='BLENDED';GLASS.use_backface_culling=False

def box_cut(target,center,size,name):
    tool=box('CUT_'+name,center,size,None);bpy.context.view_layer.objects.active=target
    mod=target.modifiers.new(name,'BOOLEAN');mod.operation='DIFFERENCE';mod.object=tool;mod.solver='EXACT';bpy.ops.object.modifier_apply(modifier=mod.name)
    OBJECTS.remove(tool);bpy.data.objects.remove(tool,do_unlink=True)

def height(x):
    # A steep upper roof with a progressively gentler foot, not a projecting annex.
    x=abs(x);return 11.90-1.60*x+.098*x*x

def flight(name,x,z,start,end,floor,direction):
    rise=(end-start)/20;run=.29
    for i in range(20):
        y=start+(i+1)*rise;zz=z+direction*i*run
        box(name+'_tread_'+str(i),(x,y-.065,zz),(1.5,.13,run+.015),WOOD,floor=floor,role='stairs',collision='walk',part=name,bevel=.006)
    a=z-direction*.16;b=z+direction*(19*run+.16)
    for xx in [x-.79,x+.79]:
        beam(name+'_stringer_'+str(xx),(xx,start-.08,a),(xx,end-.12,b),.12,.22,WOOD,floor=floor,role='stairs',part=name)
        beam(name+'_handrail_'+str(xx),(xx,start+1.02,a),(xx,end+.98,b),.065,.07,WOOD,floor=floor,role='stairs',part=name)
        for i in range(0,20,3):rod(name+'_spindle_'+str((xx,i)),(xx,start+(i+1)*rise,z+direction*i*run),(xx,start+(i+1)*rise+.94,z+direction*i*run),.024,WOOD,floor=floor,role='stairs',part=name)

def landing_guard(name,x,z0,z1,y,floor,open_end):
    # The approach end stays open; rails only along the stair void sides and far end.
    for xx in [x-.87,x+.87]:
        beam(name+'_rail_'+str(xx),(xx,y+1,z0),(xx,y+1,z1),.065,.07,WOOD,floor=floor,part=name)
        for zz in np.linspace(z0,z1,30):rod(name+'_baluster_'+str((xx,zz)),(xx,y,zz),(xx,y+1,zz),.024,WOOD,floor=floor,part=name)
    z=z1 if open_end=='z0' else z0
    beam(name+'_end',(x-.87,y+1,z),(x+.87,y+1,z),.065,.07,WOOD,floor=floor,part=name)
    for xx in np.linspace(x-.87,x+.87,10):rod(name+'_end_spindle_'+str(xx),(xx,y,z),(xx,y+1,z),.024,WOOD,floor=floor,part=name)

def house():
    reset('s1_bridge_left_residence',True);W,D=8.5,14.;X,Z=W/2-.20,D/2-.20;GX=W/2;E=height(GX)-.12
    walls={}
    # Sloping S1 bank: independent lower perimeter foundation, not a raised floor.
    for axis,fixed,length in [('z',Z,W),('z',-Z,W),('x',X,D),('x',-X,D)]:
        box('Stone_foundation_'+str((axis,fixed)),(0,-.55,fixed) if axis=='z' else (fixed,-.55,0),(length,1.10,.44) if axis=='z' else (.44,1.10,length),STONE,floor=0,role='body',part='foundation')
    for f,(bottom,top) in enumerate([(0,3.25),(3.25,E)]):
        for axis,fixed,length in [('z',Z,W),('z',-Z,W),('x',X,D),('x',-X,D)]:
            walls[f,axis,fixed]=box('Wall_'+str((f,axis,fixed)),(0,(bottom+top)/2,fixed) if axis=='z' else (fixed,(bottom+top)/2,0),(length,top-bottom,.40) if axis=='z' else (.40,top-bottom,length),STONE,floor=f,part='walls')
    # Curved gable closes exactly beneath the roof shell; no triangular wall pokes through it.
    for z in [-Z,Z]:
        poly=[(-GX,E),(GX,E)]+[(float(x),height(x)-.12) for x in np.linspace(GX,-GX,49)]
        gable=prism('Curved_stone_gable_'+str(z),poly,'z',z,.40,STONE,floor=2,part='gable')
        window(gable,'Single_tall_gable_window_'+str(z),'z',z,0,7.25,.88,2.1,floor=2,outward=1 if z>0 else -1)
    # Visible front has one tall gable window and the domestic doorway only.
    door(walls[0,'z',Z],'Front_entrance','z',Z,.60,.16,1.52,2.58)
    for xx in [-.30,1.50]:box('Entrance_stone_jamb_'+str(xx),(xx,1.48,Z+.18),(.28,2.66,.40),TRIM,part='entrance',bevel=.012)
    box('Heavy_pale_stone_lintel',(.60,2.95,Z+.21),(2.30,.42,.50),TRIM,part='entrance',bevel=.012)
    box('Flush_stone_threshold',(.60,.08,Z+.20),(2.12,.16,.88),TRIM,role='floor',collision='walk',part='entrance',bevel=.010)
    # Concealed faces use the same residential frame treatment, not rows of shop glazing.
    for axis,fixed,sign in [('x',X,1),('x',-X,-1)]:
        for f,positions in [(0,[-4.8,-.5,3.7]),(1,[-3.8,2.4])]:
            for z in positions:window(walls[f,axis,fixed],'Side_'+str((sign,f,z)),axis,fixed,z,1.05+f*3.25,.76,1.38,floor=f,outward=sign)
    for f in range(2):
        for x in [-2.1,2.1]:window(walls[f,'z',-Z],'Rear_'+str((f,x)),'z',-Z,x,1.05+f*3.25,.76,1.38,floor=f,outward=-1)
    box('Ground_floor',(0,.08,0),(W-.4,.16,D-.4),TRIM,role='floor',collision='walk',part='floor')
    upper=box('Upper_floor',(0,3.18,0),(W-.4,.14,D-.4),WOOD,floor=1,role='floor',collision='walk',part='floor')
    loft=box('Loft_floor',(0,6.43,0),(W-.4,.14,D-.4),WOOD,floor=2,role='floor',collision='walk',part='floor')
    box_cut(upper,(-2.80,3.18,-.10),(1.74,.8,6.30),'First_stair_void')
    box_cut(loft,(.90,6.43,-.10),(1.74,.8,6.30),'Loft_stair_void')
    flight('First_stair',-2.80,2.65,.16,3.25,0,-1)
    flight('Loft_stair',.90,-2.85,3.25,6.50,1,1)
    landing_guard('First_stair_guard',-2.80,-3.25,3.05,3.25,1,'z0')
    landing_guard('Loft_stair_guard',.90,-3.25,3.05,6.50,2,'z1')
    # Supplementary wall partitions leave real generous doorways to both rear rooms.
    for f in [0,1]:
        wall=box('Rear_room_partition_'+str(f),(0,.16+f*3.25+1.48,-4.6),(W-.4,2.96,.14),WOOD,floor=f,part='partition')
        cut(wall,rect(.7,.16+f*3.25,1.6,2.5),'z',-4.6,.6,'Rear_room_opening_'+str(f))
    # Continuous roof strips with arc-length UVs, so course spacing remains 0.12 m.
    N=36;extent=W/2+.38;roof_z=D/2+.25
    for sign in [-1,1]:
        xs=np.linspace(0,extent,N+1);dist=[0.]
        for a,b in zip(xs,xs[1:]):dist.append(dist[-1]+math.hypot(b-a,height(b)-height(a)))
        vs=[];uv=[];faces=[]
        for x,s in zip(xs,dist):
            for z in [-roof_z,roof_z]:vs.append((sign*x,height(x),z));uv.append((z/3,-s/2.16))
        for i in range(N):q=i*2;faces.append((q,q+1,q+3,q+2))
        top=mesh('Swept_fishscale_roof_'+str(sign),vs,faces,ROOF,uv=uv,smooth=True,floor=2,role='roof',part='roof')
        # Roof deck 12 cm below tile face, finished on its underside in timber.
        vs2=[(x,y-.12,z) for x,y,z in vs]+[(x,y-.18,z) for x,y,z in vs];K=len(vs)
        shell=faces+[tuple(K+i for i in reversed(face)) for face in faces]
        for i in range(N):
            a=i*2;b=a+2;shell.extend([(a,b,b+K,a+K),(a+1,a+1+K,b+1+K,b+1)])
        shell.extend([(0,K,K+1,1),(K-2,K-1,2*K-1,2*K-2)])
        deck=mesh('Oak_roof_deck_'+str(sign),vs2,shell,WOOD,floor=2,role='roof',part='roof')
        for z in [-roof_z,roof_z]:
            for i,(a,b) in enumerate(zip(xs,xs[1:])):
                beam('Slender_curved_verge_'+str((sign,z,i)),(sign*a,height(a)-.045,z),(sign*b,height(b)-.045,z),.105,.15,WOOD,floor=2,role='roof',collision='none',part='verge')
        box('Eave_fascia_'+str(sign),(sign*extent,height(extent)-.065,0),(.12,.16,D+.50),WOOD,floor=2,role='roof',collision='none',part='roof')
        # Rafters below the deck, supported by the plate and collar beams.
        for z in np.linspace(-6.8,6.8,12):
            for i,(a,b) in enumerate(zip(xs[::6],xs[6::6])):beam('Bent_rafter_'+str((sign,z,i)),(sign*a,height(a)-.23,z),(sign*b,height(b)-.23,z),.12,.15,WOOD,floor=2,role='roof',part='roof')
        box('Oak_wall_plate_'+str(sign),(sign*(X-.12),E-.10,0),(.22,.22,D-.2),WOOD,floor=2,role='roof',part='roof')
    for z in [-5.6,0,5.6]:beam('High_collar_tie_'+str(z),(-1.7,9.35,z),(1.7,9.35,z),.19,.20,WOOD,floor=2,role='roof',part='roof')
    # Half-round ridge tiles, genuine geometry instead of a pointed thin sheet.
    for j,z in enumerate(np.arange(-roof_z,roof_z,.34)):
        poly=[(.13*math.cos(a),11.90+.13*math.sin(a)) for a in np.linspace(0,math.pi,13)]+[(.10*math.cos(a),11.90+.10*math.sin(a)) for a in np.linspace(math.pi,0,13)]
        prism('Clay_half_round_ridge_'+str(j),poly,'z',min(z+.17,roof_z-.16),.34,CLAY,floor=2,role='roof',collision='none',part='ridge')
    # Regions are actual occupiable floor areas, not the external AABB. Leave
    # both stair voids out so cutaway cannot report a nonexistent floor there.
    regions=[{'id':'ground','floor':0,'min':[-3.85,.16,-6.6],'max':[3.85,3.25,6.6]}]
    for f,x0,x1,hole0,hole1,top in [(1,-3.85,3.85,-3.67,-1.93,6.5),(2,-2.,2.,.03,1.77,9.3)]:
        for label,a,b in [('front',[x0,f*3.25,3.05],[x1,top,6.6]),('rear',[x0,f*3.25,-6.6],[x1,top,-3.25]),('left',[x0,f*3.25,-3.25],[hole0,top,3.05]),('right',[hole1,f*3.25,-3.25],[x1,top,3.05])]:
            if b[0]-a[0]>.30:regions.append({'id':str(f)+'_'+label,'floor':f,'min':a,'max':b})
    ROOT['rmmo_building']={'version':1,'regions':regions}
    anchors={'ground_origin':[0,0,0],'front_axis':'+Z','wall_bounds_xz':[-W/2,-D/2,W/2,D/2],'entrance':[.60,.16,Z],'entrance_outer_wall':[.60,.16,D/2],'entrance_outside':[.60,.16,D/2+.65],'entrance_clear_width':1.52,'entrance_clear_height':2.58,'wall_height':E,'ridge_height':12.03,'roof_curve':'y=11.90-1.60*abs(x)+0.098*x*x','reference':'01_bridge_to_festival_street.webp; extreme left residence','supplemental':['concealed side/rear windows','two domestic storeys plus storage loft','internal partitions/stairs','timber roof structure','hinges and latch'],'interior_room_uses':{'ground':'entry/living and rear kitchen','upper':'sleeping and rear private room','loft':'storage'},'floor_heights':[.16,3.25,6.50]}
    anchors['foundation_bottom_y']=-1.10;anchors['ground_floor_finished_y']=.16;anchors['foundation_reason']='2026-10-17 complete four-corner terrain sampling, lowest corner 5.153m at proposed root 6.15m; closed perimeter footing to 5.05m. Original floor/entrance unchanged.'
    export('s1_bridge_left_residence','Dedicated S1 high narrow gable, one tall gable window, thick pale stone door lintel and gently swept clay roof eaves. Front +Z. Width/depth 8.5x14 m and ridge 12.03 m are third-person adapted project dimensions, not measured animation dimensions. Hidden elevations, plan, below-ground bank foundation and roof carpentry are project supplementary design. Courtyard walls/trees/flags are separate layout assets.',anchors)

house()
(OUT/'manifest.json').write_text(json.dumps({'version':A.version,'assets':ASSETS,'inputs':INPUTS,'scope':'Offline dedicated S1 residence; no map writes','reference':'D:/code/rmmo/docs/references/town_bridge_street_20261005/01_bridge_to_festival_street.webp'},ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copy2(__file__,OUT/Path(__file__).name)
print('S1_AUTHORING_COMPLETE',[(r['id'],r['triangles']) for r in ASSETS],flush=True)
