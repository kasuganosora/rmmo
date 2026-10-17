"""S12 residential shot assets. CPU Blender authoring; no catalogue/map writes.

Units/coordinates below are Godot metres, +Y up, gable front +Z, river side +X.
Visible proportions follow the user's S12 frames; concealed plan is supplemental.
Gate is a slender freestanding courtyard entrance, per the latest user correction.
Only the reviewed gable relief is reused unchanged.
"""
import argparse, hashlib, json, math, shutil, sys
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Vector

P=argparse.ArgumentParser();P.add_argument('--version',default='v1');P.add_argument('--only',default='all')
A=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
BASE=Path('D:/code/rmmo_runtime/art_sources/s12_residential_details_20261017')
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
    o.name=name;o.parent=ROOT;o['uuid']='s12_'+hashlib.sha256(name.encode()).hexdigest()[:24]
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
    uv=o.data.uv_layers.active if authored else o.data.uv_layers.new(name='S12UV')
    uv.name='S12UV'
    for face in o.data.polygons:
        if authored:
            coords=[uv.data[li].uv.copy() for li in face.loop_indices]
            area=sum(a.x*b.y-a.y*b.x for a,b in zip(coords,coords[1:]+coords[:1]))
            if abs(area)>1e-12:continue
        n=g(face.normal);m=o.data.materials[face.material_index];roof=m==ROOF
        for li in face.loop_indices:
            p=g(o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co)
            if roof and abs(n.y)<.999:
                uphill=Vector((0,1,0))-n*n.y;uphill.normalize();across=uphill.cross(n).normalized();a,b=p.dot(across),p.dot(uphill)/.72
            else:
                a,b=(p.x,p.z) if abs(n.y)>.7 else ((p.z,p.y) if abs(n.x)>abs(n.z) else (p.x,p.y))
                if m in [STONE,TRIM,GATE_STONE]:a/=2;b/=2
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

# Shared, already-authored project materials; files remain unchanged.
STONE=library_mat('walls/stone_tiles_facade','S12 warm coursed stone')
WOOD=library_mat('wood/solid_timber','S12 weathered oak')
ROOF=library_mat('roofs/terracotta_plain','S12 red clay overlapping tiles')
GM=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
TRIM=mat('S12 dressed stone',rough=1,maps={s:GM/f for s,f in [('Base Color','guild_cut_limestone_mineral_color.png'),('Normal','guild_cut_limestone_micro_normal.png'),('Roughness','guild_cut_limestone_roughness.png')]},normal=.18)
GATE_STONE=library_mat('terrain/beach_cliff','S12 fine worked grey limestone')
next(n for n in GATE_STONE.node_tree.nodes if n.type=='NORMAL_MAP').inputs['Strength'].default_value=.12
IRON=mat('S12 blackened iron',(.018,.014,.011),.62,.65)
BRASS=mat('S12 aged brass fasteners',(.30,.19,.055),.42,.8)
GLASS=mat('S12 residential clear glass',(.68,.75,.70),.14)
bs=next(n for n in GLASS.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Alpha'].default_value=.22;bs.inputs['Transmission Weight'].default_value=.8;GLASS.surface_render_method='BLENDED';GLASS.use_backface_culling=False
WEAVE=Path('D:/code/rmmo_runtime/art_sources/wall_guild_banners/textures/woven_normal.png')
RED=mat('S12 oxblood woven linen',(.10,.008,.009),.93,maps={'Normal':WEAVE},normal=.32)
GOLD=mat('S12 ochre yellow woven border',(.32,.16,.028),.87,maps={'Normal':WEAVE},normal=.32)

def banner(name,phase):
    reset(name);W,H=.82,1.60
    # Root is the centre of the wall plate at crossbar elevation; wall z=0.
    for x in [-W/2-.045,W/2+.045]:
        box('Wall_plate_'+str(x),(x,-.07,.018),(.075,.32,.036),IRON,collision='none',part='bracket',bevel=.006)
        rod('Cantilever_'+str(x),(x,0,.035),(x,0,.45),.014,IRON,collision='none',part='bracket')
        rod('Triangular_brace_'+str(x),(x,-.205,.038),(x,-.006,.397),.011,IRON,collision='none',part='bracket')
        for y in [.045,-.185]:rod('Anchor_bolt_'+str((x,y)),(x,y,.031),(x,y,.052),.012,BRASS,collision='none',part='bracket',segments=12)
    rod('Oak_crossbar',(-.52,0,.45),(.52,0,.45),.025,WOOD,collision='none',part='bracket',segments=24)
    for x in [-.51,.51]:rod('Rod_end_'+str(x),(x-.02,0,.45),(x+.02,0,.45),.034,BRASS,collision='none',part='bracket')
    N=44;vs=[];uv=[];index={};fs=[]
    outer=[(-W/2,0),(W/2,0),(0,-H)]
    offset=.045*math.sqrt(1+(W/2/H)**2);half=W/2*(1-.055/H)-offset
    inner=[(-half,-.055),(half,-.055),(0,-H+offset/(W/2/H))]
    def point(xx,yy):
        t=-yy/H
        zz=.45+.022*(1-math.exp(-t*12))*math.sin(xx*23+phase)+.027*t*t*math.sin(t*8+phase)
        uv.append((xx/.35,(yy-.025)/.35));vs.append((xx,yy-.025,zz));return len(vs)-1
    # Explicit continuous inset edges keep the gold hem straight, without centroid stair-steps.
    for j in range(N+1):
        t=j/N
        for i in range(N-j+1):
            u=i/N;xx=inner[0][0]*(1-u-t)+inner[1][0]*u+inner[2][0]*t;yy=inner[0][1]*(1-u-t)+inner[1][1]*u+inner[2][1]*t
            index[i,j]=point(xx,yy)
    for j in range(N):
        for i in range(N-j):
            tri=[index[i,j],index[i+1,j],index[i,j+1]];fs.append(tuple(tri))
            if i<N-j-1:fs.append((index[i+1,j],index[i+1,j+1],index[i,j+1]))
    red_faces=len(fs)
    for edge in range(3):
        ids=[];nxt=(edge+1)%3
        for j in range(N+1):
            t=j/N;ids.append([point(poly[edge][0]*(1-t)+poly[nxt][0]*t,poly[edge][1]*(1-t)+poly[nxt][1]*t) for poly in [outer,inner]])
        for j in range(N):fs.append((ids[j][0],ids[j+1][0],ids[j+1][1],ids[j][1]))
    cloth=mesh('Triangular_woven_cloth',vs,fs,RED,uv=uv,smooth=True,collision='none',part='cloth')
    cloth.data.materials.append(GOLD)
    for p in cloth.data.polygons:p.material_index=int(p.index>=red_faces)
    bm=bmesh.new();bm.from_mesh(cloth.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bm.to_mesh(cloth.data);bm.free()
    sol=cloth.modifiers.new('Linen thickness 1.6 mm','SOLIDIFY');sol.thickness=.0016;sol.offset=0
    cloth['rmmo_wind']={'profile':'cloth','mesh':'*','amplitude':.055,'stiffness':.62,'anchor':'top','shelter':True}
    # Continuous stitched loops over the bar, fixed independently from the free hem.
    for idx,x in enumerate([-.31,0,.31]):
        path=[(-.09,.48),(0,.48)]+[(.030*math.sin(a),.45+.030*math.cos(a)) for a in np.linspace(0,math.pi,13)][1:]+[(-.09,.42)]
        verts=[(x+s*.026,y,z) for y,z in path for s in [-1,1]];faces=[(j*2,j*2+1,j*2+3,j*2+2) for j in range(len(path)-1)]
        loop=mesh('Sewn_hanging_loop_'+str(idx),verts,faces,GOLD,smooth=True,collision='none',part='bracket');loop.modifiers.new('Sewn linen ribbon','SOLIDIFY').thickness=.0016
    export(name,'Reference red field and yellow triangular hem. Unseen sewn loops, bolts and triangular braces are project supplementary design. Gold is woven pigment, nonmetal. Wind at cloth only; support fixed.',{'wall_origin':[0,0,0],'pole_center':[0,0,.45],'lowest_tip':[0,-1.625,.45],'mount_floor_height_recommended':3.10})

def jar_material():
    # Numerical clay micro-surface maps, authored for this asset; not measured scans.
    N=768;y,x=np.mgrid[0:N,0:N]/N;rng=np.random.default_rng(712)
    cloud=.45*np.sin(2*math.pi*(x*3+y))+.25*np.sin(2*math.pi*(x-y*2))+.18*np.sin(2*math.pi*(x*9+y*5))
    grain=rng.normal(0,1,(N,N));h=.000045*grain+.00012*np.sin(2*math.pi*y*54+.12*np.sin(x*math.tau*4))
    dy,dx=np.gradient(h,.88/N,2.2/N);normal=np.stack([-dx,-dy,np.ones_like(dx)],axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    color=np.array([.47,.31,.17])[None,None,:]*(1+.10*cloud[...,None]+.012*grain[...,None]);rough=np.clip(.82+.035*cloud+.025*grain,.67,.94)
    paths={}
    for role,arr in [('Base Color',color),('Normal',normal*.5+.5),('Roughness',np.repeat(rough[...,None],3,axis=-1))]:
        im=bpy.data.images.new('S12 clay '+role,width=N,height=N);im.colorspace_settings.name='sRGB' if role=='Base Color' else 'Non-Color'
        rgba=np.concatenate([np.clip(arr,0,1),np.ones((N,N,1))],axis=-1).astype(np.float32);im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(OUT/('jar_'+role.replace(' ','_')+'.png'));im.file_format='PNG';im.save();paths[role]=im.filepath_raw
    return mat('S12 unglazed wheel-thrown ochre clay',rough=1,maps=paths,normal=.8)
def jar():
    reset('s12_doorstep_jar');m=jar_material();vs=[];fs=[];uv=[]
    controls=[(.0,.21),(.025,.225),(.08,.265),(.19,.32),(.36,.365),(.51,.36),(.65,.30),(.74,.22),(.79,.17),(.82,.165),(.845,.185),(.87,.19),(.885,.178)]
    profile=[];slopes=np.gradient([r for h,r in controls],[h for h,r in controls])
    for k,((a,ra),(b,rb)) in enumerate(zip(controls,controls[1:])):
        for i in range(4):
            t=i/4;r=(2*t**3-3*t*t+1)*ra+(t**3-2*t*t+t)*(b-a)*slopes[k]+(-2*t**3+3*t*t)*rb+(t**3-t*t)*(b-a)*slopes[k+1];profile.append((a+(b-a)*t,r))
    profile.append(controls[-1]);profile.extend([(h-.012,max(.03,r-.026)) for h,r in reversed(profile[:-1]) if h>.07]);profile.extend([(.065,.16),(.06,0)])
    N=64
    for k,(h,r) in enumerate(profile):
        for i in range(N+1):
            a=i/N*math.tau;rr=r*(1+.006*math.sin(a*3+h*4))+.0015*math.sin(h*93)*(r/.365)
            vs.append((rr*math.cos(a),h,rr*math.sin(a)));uv.append((i/N,k/(len(profile)-1)))
    for j in range(len(profile)-1):
        for i in range(N):q=j*(N+1)+i;fs.append((q,q+1,q+N+2,q+N+1))
    mesh('Thrown_body_with_real_inner_cavity',vs,fs,m,uv=uv,smooth=True,part='jar',bevel=0)
    # Close underside with a recessed foot disk; mouth stays open.
    rod('Closed_foot',(0,0,0),(0,.019,0),.211,m,segments=64,part='jar')
    for side in [-1,1]:
        pts=[(side*(.220+.150*math.sin(i/20*math.pi)),.71-.24*i/20,0) for i in range(21)]
        verts=[];faces=[];uvs=[];length=0
        for j,p in enumerate(pts):
            if j:length+=math.dist(pts[j-1],p)
            tangent=Vector(pts[min(j+1,20)])-Vector(pts[max(0,j-1)]);tangent.normalize();u=Vector((0,0,1));v=tangent.cross(u).normalized()
            for i in range(13):
                a=i/12*math.tau;verts.append(tuple(Vector(p)+.024*(math.cos(a)*u+math.sin(a)*v)));uvs.append((i/12,length))
        for j in range(20):
            for i in range(12):q=j*13+i;faces.append((q,q+1,q+14,q+13))
        mesh('Continuous_lug_handle_'+str(side),verts,faces,m,uv=uvs,smooth=True,part='jar')
    export('s12_doorstep_jar','Hollow unglazed ochre clay jar with rolled lip, foot and two small lug handles. Rim/wall thickness and hidden interior are project supplementary design; no baked sunset tint.',{'ground_origin':[0,0,0],'mouth_center':[0,.875,0]})

def rect(u,y,w,h):return [(u-w/2,y),(u+w/2,y),(u+w/2,y+h),(u-w/2,y+h)]
def window(wall,name,axis,fixed,u,y,w=.85,h=1.3,floor=1,outward=1,role='body'):
    cut(wall,rect(u,y,w,h),axis,fixed,1.0,name)
    def pos(a,b,off=0):return (a,b,fixed+off) if axis=='z' else (fixed+off,b,a)
    def bx(n,a,b,ww,hh,dd,m,off=0):return box(name+n,pos(a,b,off),(ww,hh,dd) if axis=='z' else (dd,hh,ww),m,floor=floor,role=role,collision='none',part='window_'+name,bevel=.008)
    for xx in [u-w/2-.07,u+w/2+.07]:bx('_stone_jamb_'+str(xx),xx,y+h/2,.14,h+.18,.20,TRIM,outward*.23)
    bx('_stone_sill',u,y-.07,w+.32,.14,.32,TRIM,outward*.26)
    bx('_oak_lintel',u,y+h+.10,w+.34,.20,.30,WOOD,outward*.24)
    for xx in [u-w/2+.035,u+w/2-.035,u]:bx('_frame_v_'+str(xx),xx,y+h/2,.065,h,.09,WOOD,outward*.08)
    for yy in [y+.035,y+h*.33,y+h*.66,y+h-.035]:bx('_frame_h_'+str(yy),u,yy,w,.06,.09,WOOD,outward*.08)
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

def courtyard_gate():
    reset('s12_freestanding_courtyard_gate');m=GATE_STONE
    def lathe(name,cx,profile):
        vs=[];uv=[];fs=[];N=48
        for y,r in profile:
            for i in range(N+1):
                a=math.tau*i/N+math.pi/2;vs.append((cx+r*math.cos(a),y,r*math.sin(a)));uv.append((i/N,y/2))
        for j in range(len(profile)-1):
            for i in range(N):q=j*(N+1)+i;fs.append((q,q+1,q+N+2,q+N+1))
        fs.extend([tuple(range(N-1,-1,-1)),tuple((len(profile)-1)*(N+1)+i for i in range(N))])
        o=mesh(name,vs,fs,m,uv=uv,smooth=True,part='gate_stone')
        for p in list(o.data.polygons)[-2:]:p.use_smooth=False
    for side in [-1,1]:
        x=side*1.28
        box('Gate_plinth_'+str(side),(x,.085,0),(.55,.17,.55),m,part='gate_stone',bevel=.008)
        lathe('Gate_moulded_base_'+str(side),x,[(.17,.235),(.22,.235),(.25,.202),(.30,.190),(.33,.17)])
        for j in range(7):
            y=.33+j*.40;r=.172-j*.002
            lathe('Slender_shaft_'+str((side,j)),x,[(y,r),(y+.398,r-.0018)])
        lathe('Neck_bell_capital_'+str(side),x,[(3.13,.158),(3.16,.178),(3.21,.178),(3.24,.20),(3.30,.235),(3.34,.26)])
        for y,w,h in [(3.37,.53,.06),(3.43,.60,.06)]:box('Stepped_impost_'+str((side,y)),(x,y,0),(w,h,w),m,part='gate_stone',bevel=.006)
    spring=3.46;ri,ro=1.16,1.40
    for i in range(17):
        a=i*math.pi/17+.0007;b=(i+1)*math.pi/17-.0007
        poly=[(r*math.cos(t),spring+r*math.sin(t)) for r,seq in [(ri,np.linspace(a,b,6)),(ro,np.linspace(b,a,6))] for t in seq]
        prism('Shallow_radial_arch_stone_'+str(i),poly,'z',0,.40,m,part='gate_stone',bevel=.003)
        # Narrow raised edge, matching the reference archivolt on both finished faces.
        for face in [-1,1]:
            poly=[(r*math.cos(t),spring+r*math.sin(t)) for r,seq in [(1.345,np.linspace(a,b,6)),(1.405,np.linspace(b,a,6))] for t in seq]
            prism('Arch_edge_'+str((i,face)),poly,'z',face*.207,.025,m,part='gate_stone',bevel=.002)
    export('s12_freestanding_courtyard_gate','User correction 2026-10-17: independent courtyard gateway, not an attached porch. Slender tapered shafts, stepped capitals, shallow radial arch. No rear piers, deep barrel, facade ties, gate leaf or wall-cut requirement. Hidden footings and mortar joints are project supplementary design; no structural-engineering certification.',{'ground_origin':[0,0,0],'front_axis':'+Z','clear_shaft_width':2.216,'inner_arch_span':2.32,'arch_radial_thickness':.24,'barrel_depth':.40,'max_capital_depth':.60,'shaft_diameter_at_base':.344,'spring_height':spring,'top_height':4.865,'courtyard_wall_connections':[[-1.56,.6,0],[1.56,.6,0]],'wall_requires_opening':False,'installation':'Place as an independent courtyard entrance. Side yard walls meet outer plinths; keep central passage clear. Do not mount to the residence facade.'})

def house():
    reset('s12_riverside_residence',True);W,D=8.6,13.2;X,Z=W/2,D/2;E,R=6.45,10.0
    walls={}
    for f,(bottom,top) in enumerate([(0,3.25),(3.25,E)]):
        for axis,fixed,length in [('z',Z,W),('z',-Z,W),('x',X,D),('x',-X,D)]:
            walls[f,axis,fixed]=box('Wall_'+str((f,axis,fixed)),(0,(bottom+top)/2,fixed) if axis=='z' else (fixed,(bottom+top)/2,0),(length,top-bottom,.38) if axis=='z' else (.38,top-bottom,length),STONE,floor=f,part='walls')
    # The courtyard arch is detached. The gable stays solid; entry is on the long river face.
    for z in [-Z,Z]:prism('Stone_gable_'+str(z),[(-X,E),(X,E),(0,R-.12)],'z',z,.38,STONE,floor=1,part='gable')
    slab=box('Ground_floor',(0,-.09,0),(W-.38,.18,D-.38),TRIM,role='floor',collision='walk',part='ground_floor')
    upper=box('Upper_floor',(0,3.16,0),(W-.38,.18,D-.38),WOOD,floor=1,role='floor',collision='walk',part='upper_floor')
    # Boolean vertical voids use horizontal prism via a temporary box.
    for name,center,size in [('stairs',(-2.65,3.16,-2.58),(1.8,1,6.26))]:
        tool=box('CUT_'+name,center,size,None);bpy.context.view_layer.objects.active=upper;mod=upper.modifiers.new('Floor void '+name,'BOOLEAN');mod.operation='DIFFERENCE';mod.object=tool;mod.solver='EXACT';bpy.ops.object.modifier_apply(modifier=mod.name);OBJECTS.remove(tool);bpy.data.objects.remove(tool,do_unlink=True)
    # Private rear stair, all dimensions are project supplemental design.
    for i in range(20):
        height=(i+1)*3.25/20;box('Timber_stair_'+str(i),(-2.65,height-.07,.35-i*.31),(1.65,.14,.34),WOOD,role='stairs',collision='walk',part='stairs',bevel=.008)
    for x in [-3.53,-1.77]:
        beam('Stair_stringer_'+str(x),(x,-.06,.55),(x,3.10,-5.78),.12,.22,WOOD,role='stairs',part='stairs')
        beam('Stair_handrail_'+str(x),(x,1.0,.55),(x,4.1,-5.78),.065,.07,WOOD,role='stairs',part='stairs')
        for i in range(0,20,3):rod('Stair_baluster_'+str((x,i)),(x,(i+1)*.1625,.35-i*.31),(x,(i+1)*.1625+.93,.35-i*.31),.025,WOOD,role='stairs',part='stairs')
    for edge,(a,b) in enumerate([((-3.55,-5.71),(-3.55,.55)),((-1.75,-5.71),(-1.75,.55)),((-3.55,.55),(-1.75,.55))]):
        beam('Gallery_guard_rail_'+str(edge),(a[0],4.24,a[1]),(b[0],4.24,b[1]),.08,.08,WOOD,floor=1,part='gallery_guard')
        count=math.ceil(math.dist(a,b)/.20)
        for j in range(count+1):
            t=j/count;x=a[0]+(b[0]-a[0])*t;z=a[1]+(b[1]-a[1])*t
            rod('Gallery_guard_spindle_'+str((edge,j)),(x,3.25,z),(x,4.24,z),.027,WOOD,floor=1,part='gallery_guard')
    # Front windows flank the independent vertical relief; river side has five regular bays.
    for x in [-2.45,2.30]:window(walls[1,'z',Z],'Gable_window_'+str(x),'z',Z,x,5.15,.78,1.0)
    for z in [4.6,2.25,-.10,-2.45,-4.8]:window(walls[1,'x',X],'River_upper_'+str(z),'x',X,z,4.25,.85,1.45)
    door(walls[0,'x',X],'River_entrance','x',X,4.15,0,1.38,2.45)
    for z in [1.0,-1.75,-4.50]:window(walls[0,'x',X],'River_lower_'+str(z),'x',X,z,1.0,.80,1.35,floor=0)
    for f in range(2):
        for z in [-4.3,0,4.3]:window(walls[f,'x',-X],'Rear_side_'+str((f,z)),'x',-X,z,.95+f*3.25,.82,1.35,floor=f,outward=-1)
        for x in [-1.8,1.8]:window(walls[f,'z',-Z],'Rear_gable_'+str((f,x)),'z',-Z,x,.95+f*3.25,.82,1.35,floor=f,outward=-1)
    # Lintel and entrance threshold align with the side door and banner brackets.
    box('River_entrance_head_beam',(X+.25,2.95,4.15),(.40,.22,3.55),WOOD,collision='none',part='entrance')
    for z in [2.48,5.82]:beam('Entrance_corbel_'+str(z),(X+.18,2.55,z),(X+.46,2.88,z),.14,.14,WOOD,collision='none',part='entrance')
    box('Doorstep_landing',(X+.36,-.08,4.15),(.92,.16,2.05),TRIM,role='floor',collision='walk',part='entrance',bevel=.018)
    box('Doorstep_lower',(X+.88,-.16,4.15),(.36,.16,2.05),TRIM,role='floor',collision='walk',part='entrance',bevel=.018)
    # Main roof: a continuous two-sided shell, with proper through-openings for dormers.
    roofs=[]
    for sign in [-1,1]:
        edge=sign*(X+.38);poly=[(0,R),(edge,E-.01),(edge,E-.17),(0,R-.17)]
        roofs.append(prism('Main_roof_'+str(sign),poly,'z',0,D+.75,ROOF,floor=1,role='roof',part='roof'))
        box('Eave_fascia_'+str(sign),(edge,E-.10,0),(.17,.24,D+.80),WOOD,floor=1,role='roof',collision='none',part='roof',bevel=.01)
    for z in [-Z-.38,Z+.38]:
        for sign in [-1,1]:beam('Gable_verge_'+str((z,sign)),(0,R+.035,z),(sign*(X+.40),E-.04,z),.15,.19,WOOD,floor=1,role='roof',collision='none',part='roof')
    # Ridge caps are geometry, tile relief remains texture-driven between edges.
    rod('Clay_ridge',(0,R+.025,-Z-.4),(0,R+.025,Z+.4),.105,ROOF,segments=20,floor=1,role='roof',collision='none',part='roof')
    for z in [3.35,.05,-3.25]:
        # The dormer's rear sits inside the main roof; only the visible wedge is added.
        xfront=3.28;bottom=7.22;peak=8.72;half=.61;k=(R-(E-.01))/(X+.38)
        rear_eave=(R-8.10)/k;rear_ridge=(R-8.80)/k
        cheek_poly=[(rear_eave,8.10),(xfront,R-k*xfront),(xfront,8.10)]
        for zz in [z-half,z+half]:prism('Dormer_cheek_'+str((z,zz)),cheek_poly,'z',zz,.12,STONE,floor=1,role='roof',part='roof')
        face=prism('Dormer_face_'+str(z),[(z-half,bottom),(z+half,bottom),(z+half,8.1),(z,peak),(z-half,8.1)],'x',xfront,.18,STONE,floor=1,role='roof',part='roof')
        window(face,'Dormer_'+str(z),'x',xfront,z,7.33,.55,.68,floor=1,role='roof')
        # Cut roof below the clear window so it looks into the attic, not into roof tiles.
        cutter=prism('CUT_dormer',[(z-.54,7.2),(z+.54,7.2),(z+.54,8.00),(z,8.65),(z-.54,8.00)],'x',2.42,2.04,None)
        bpy.context.view_layer.objects.active=roofs[1];mod=roofs[1].modifiers.new('Dormer aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);OBJECTS.remove(cutter);bpy.data.objects.remove(cutter,do_unlink=True)
        for sign in [-1,1]:
            # Dormer roof runs along X; extends back to meet the main roof plane.
            top=[(3.45,8.80,z),(3.45,8.10,z+sign*.72),(rear_eave-.025,8.10,z+sign*.72),(rear_ridge-.025,8.80,z)]
            vs=top+[(x,y-.12,zz) for x,y,zz in top]
            mesh('Dormer_roof_'+str((z,sign)),vs,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],ROOF,floor=1,role='roof',part='roof')
            beam('Dormer_barge_'+str((z,sign)),(3.45,peak+.1,z),(3.45,8.10,z+sign*(half+.11)),.10,.12,WOOD,floor=1,role='roof',part='roof',collision='none')
    # Rear offset chimney, with actual open flue and cap; no unobserved religious symbol.
    chim=box('Stone_chimney',(-1.55,9.55,-3.6),(.58,2.8,.62),STONE,floor=1,role='roof',part='roof')
    tool=box('CUT_flue',(-1.55,10.6,-3.6),(.29,1.1,.33),None);bpy.context.view_layer.objects.active=chim;mod=chim.modifiers.new('Flue opening','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=tool;bpy.ops.object.modifier_apply(modifier=mod.name);OBJECTS.remove(tool);bpy.data.objects.remove(tool,do_unlink=True)
    for yy in [10.87,11.03]:
        for x in [-1.83,-1.27]:box('Chimney_cap_x_'+str((x,yy)),(x,yy,-3.6),(.13,.13,.76),TRIM,floor=1,role='roof',part='roof')
        for z in [-3.91,-3.29]:box('Chimney_cap_z_'+str((z,yy)),(-1.55,yy,z),(.57,.13,.14),TRIM,floor=1,role='roof',part='roof')
    ROOT['rmmo_building']={'version':1,'regions':[{'id':'ground','floor':0,'min':[-4.1,0,-6.4],'max':[4.1,3.25,6.4]},{'id':'upper','floor':1,'min':[-4.1,3.25,-6.4],'max':[4.1,6.45,6.4]}]}
    anchors={'front_axis':'+Z','river_side_axis':'+X','wall_bounds_xz':[-X,-Z,X,Z],'courtyard_gate':{'position':[2.75,0,8.6],'yaw_degrees':0,'scale':[1,1,1],'note':'Independent scene instance; 1.51m clear behind deepest gate capital to facade. Yard connects to left; not a facade aperture.'},'relief':{'position':[-.25,5.55,6.73],'yaw_degrees':0,'scale':[1,1,1]},'river_door':[4.3,0,4.15],'banner_a':{'position':[4.505,3.10,5.62],'yaw_degrees':90},'banner_b':{'position':[4.505,3.10,2.68],'yaw_degrees':90},'jar':{'position':[4.95,0,5.62],'yaw_degrees':0},'suggested_world':{'origin':[351.9,8.025,111.0],'yaw_degrees':-90,'note':'Keeps front gable plane world X=345.3. Gate suggested world (343.3,8.025,113.75), yaw -90; separate courtyard entrance. Layout proposal only.'}}
    export('s12_riverside_residence','S12 residence: narrow solid gable, long river elevation with five upper windows, side entrance, three dormers. Detached courtyard gate is a separate asset and instance. Rear, stair and floor are project supplemental design. Reviewed relief reused separately. Not a church or shop; no window displays. Furniture not included.',anchors)

for name,phase in [('s12_red_gold_pennant_a',.3),('s12_red_gold_pennant_b',1.6)]:
    if A.only in ['all','props',name]:banner(name,phase)
if A.only in ['all','props','jar']:jar()
if A.only in ['all','gate']:courtyard_gate()
if A.only in ['all','house']:house()
manifest={'version':A.version,'assets':ASSETS,'inputs':INPUTS,'scope':'Offline S12 shot assets, not deployed to map or catalogue','reference_base':str(BASE/'references'),'existing_reuse':{'relief':'D:/code/rmmo_runtime/packs/default/assets/141d49724ce3c328e913d0e7e3d6091bda06a6fb37353e0065ecd49787392434.glb'}}
(OUT/('manifest_'+A.only+'.json')).write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
shutil.copy2(__file__,OUT/Path(__file__).name)
print('S12_AUTHORING_COMPLETE',[(r['id'],r['triangles']) for r in ASSETS],flush=True)
