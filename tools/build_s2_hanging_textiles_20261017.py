"""S2 reference textiles; independent Blender sources, no library/map writes.

Coordinates are Godot metres (+Y up, front +Z). Hidden hems, knots and fasteners
are project additions. No existing lamp, post, banner or map is overwritten.
"""
import argparse, hashlib, json, math, shutil, sys, struct
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Vector

P=argparse.ArgumentParser();P.add_argument('--version',default='v1');A=P.parse_args(sys.argv[sys.argv.index('--')+1:])
BASE=Path('D:/code/rmmo_runtime/art_sources/s2_hanging_textiles_20261017')
OUT=BASE/A.version
OUT.mkdir(parents=True,exist_ok=True)
WEAVE=Path('D:/code/rmmo_runtime/art_sources/wall_guild_banners/textures/woven_normal.png')
OBJECTS=[];ROWS=[];ROOT=None
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def c(v):return (v[0],-v[2],v[1])
def g(v):return (v[0],v[2],-v[1])
def textile_map(name,values):
    # Analytic material channels, not edited reference photography. 0.26 m tile.
    height,width=values.shape[:2];pixels=np.ones((height,width,4),np.float32);pixels[:,:,:3]=values[:,:,None] if values.ndim==2 else values
    im=bpy.data.images.new(name,width=width,height=height,alpha=False);im.colorspace_settings.name='Non-Color';im.pixels.foreach_set(pixels.ravel());im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save();im.pack();return im
yy,xx=np.mgrid[0:1024,0:1024]/1024
warp=np.sin(xx*math.tau*192);weft=np.sin(yy*math.tau*192)
slub=.035*np.sin(xx*math.tau*37)+.023*np.cos(yy*math.tau*31)
mottle=.025*np.sin(xx*math.tau*3+np.sin(yy*math.tau*4))+.018*np.cos(xx*math.tau*7-yy*math.tau*5)
linear=np.clip(.86+slub+mottle+.018*warp*weft,.70,.98)
ALBEDO=textile_map('S2_linen_thread_albedo',np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055));ALBEDO.colorspace_settings.name='sRGB'
ROUGH=textile_map('S2_linen_thread_roughness',np.clip(.94+slub*.5+.025*warp*weft,.84,1))
def material(name,color,rough=.9,metal=0,weave=False):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1);m.use_backface_culling=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if weave:
        for socket,im in [('Base Color',ALBEDO),('Roughness',ROUGH)]:
            t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=im
            if socket=='Base Color':
                mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*color,1);m.node_tree.links.new(t.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(mix.outputs['Color'],p.inputs[socket])
            else:m.node_tree.links.new(t.outputs['Color'],p.inputs[socket])
        t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(WEAVE),check_existing=True);t.image.colorspace_settings.name='Non-Color';t.image.pack()
        n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.38;m.node_tree.links.new(t.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],p.inputs['Normal'])
    return m
YELLOW=material('S2 ochre yellow dyed linen',(.54,.355,.055),.91,weave=True)
YELLOW2=material('S2 sun faded yellow linen',(.62,.44,.09),.93,weave=True)
WHITE=material('S2 washed unbleached linen',(.73,.705,.635),.96,weave=True)
WHITE2=material('S2 pale clean linen',(.82,.81,.755),.95,weave=True)
FIELD=material('S2 aged yellow ochre banner field',(.31,.225,.078),.92,weave=True)
OLIVE=material('S2 muted olive sewn border',(.19,.235,.075),.94,weave=True)
INK=material('S2 yellow pigment motif',(.64,.43,.065),.94,weave=True)
ROPE=material('S2 natural flax cord',(.225,.161,.08),.98)
IRON=material('S2 dark iron wall hooks',(.025,.023,.020),.63,.65)
WOOD=material('S2 wooden clothes pegs',(.23,.135,.065),.85)

def reset(name):
    global ROOT,OBJECTS
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);OBJECTS=[]
    ROOT=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ROOT);ROOT['asset_id']=name;ROOT['rmmo_project_supplement']=True
    bpy.context.scene.unit_settings.system='METRIC'
def mesh(name,vs,fs,m,uv=None,smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata([c(v) for v in vs],[],fs);data.update()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.parent=ROOT;o['rmmo_collision']='none';o['uuid']='s2_'+hashlib.sha256((ROOT.name+name).encode()).hexdigest()[:24];data.materials.append(m)
    for p in data.polygons:p.use_smooth=smooth
    if uv:
        layer=data.uv_layers.new(name='Metric_weave')
        for loop in data.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    OBJECTS.append(o);return o
def tube(name,points,r,m,segments=8):
    pts=[Vector(p) for p in points];vs=[];uv=[]
    for i,p in enumerate(pts):
        t=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized();ref=Vector((0,0,1)) if abs(t.z)<.9 else Vector((0,1,0));u=t.cross(ref).normalized();v=t.cross(u).normalized()
        for j in range(segments):
            a=j*math.tau/segments;vs.append(tuple(p+r*(u*math.cos(a)+v*math.sin(a))));uv.append((j/segments,i/max(1,len(pts)-1)))
    fs=[(i*segments+j,i*segments+(j+1)%segments,(i+1)*segments+(j+1)%segments,(i+1)*segments+j) for i in range(len(pts)-1) for j in range(segments)]
    fs += [tuple(range(segments-1,-1,-1)),tuple((len(pts)-1)*segments+j for j in range(segments))]
    return mesh(name,vs,fs,m,uv,smooth=True)
def box(name,center,size,m):
    x,y,z=center;w,h,d=[s*.5 for s in size];vs=[(x+a*w,y+b*h,z+cc*d) for a,b,cc in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    o=mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],m)
    mod=o.modifiers.new('Soft worked edges','BEVEL');mod.width=.002;mod.segments=2;return o
def ring(name,center,r,wire,m,axis='z'):
    x,y,z=center
    return tube(name,[(x+r*math.cos(a),y+r*math.sin(a),z) if axis=='z' else (x,y+r*math.sin(a),z+r*math.cos(a)) for a in [j*math.tau/24 for j in range(25)]],wire,m)
def cord_y(x,span,sag):return -sag*(1-(2*x/span)**2)
def tie(name,x,y,z=0):
    # Three visible turns and a loose end; knots stay with the tensioned rope.
    tube(name+'_turns',[(x+(t-.5)*.055,y+.017*math.sin(t*math.tau*3),z+.017*math.cos(t*math.tau*3)) for t in [i/36 for i in range(37)]],.004,ROPE,6)
    tube(name+'_tail',[(x+.024,y,z+.012),(x+.037,y-.055,z+.025),(x+.025,y-.115,z+.036)],.004,ROPE,6)
def cloth(name,x,w,h,span,sag,m,phase=0,nu=20,nv=32,fold=.03,border=False):
    def point(u,v):
        xx=x+(u-.5)*w;top=cord_y(xx,span,sag)-.025
        yy=top-v*h+.009*v*v*math.sin(u*math.pi*3+phase)
        zz=fold*(1-math.exp(-v*10))*math.sin(u*math.pi*5+phase)+.035*v*v*math.sin(v*5+phase)
        return xx,yy,zz
    vs=[point(i/nu,j/nv) for j in range(nv+1) for i in range(nu+1)]
    uv=[(i/nu*w/.26,-j/nv*h/.26) for j in range(nv+1) for i in range(nu+1)]
    fs=[(j*(nu+1)+i,j*(nu+1)+i+1,(j+1)*(nu+1)+i+1,(j+1)*(nu+1)+i) for j in range(nv) for i in range(nu)]
    o=mesh(name,vs,fs,m,uv,True)
    sol=o.modifiers.new('Hemmed linen 1.4 mm','SOLIDIFY');sol.thickness=.0014;sol.offset=0
    o['rmmo_wind']={'profile':'cloth','mesh':'*','amplitude':.25 if h>1 else .16,'stiffness':.42 if h>1 else .64,'anchor':'top','shelter':True}
    o['cloth_top_vertices']=[list(v) for v in vs[:nu+1]]
    # Narrow doubled hem shares the same wind mesh and anchor, not floating bars.
    hems=[]
    for side in [0,1,2]:
        vv=[];uu=[];count=nv if side<2 else nu
        for j in range(count+1):
            for k in [0,1]:
                u=(.012*k/w if side==0 else 1-.012*k/w) if side<2 else j/count
                v=j/count if side<2 else 1-.012*k/h
                q=point(u,v);vv.append((q[0],q[1],q[2]+.0014));uu.append((u*w/.26,-v*h/.26))
        he=mesh(name+'_double_hem_'+str(side),vv,[(2*j,2*j+1,2*j+3,2*j+2) for j in range(count)],m,uu,True);he.modifiers.new('Folded hem thickness','SOLIDIFY').thickness=.0014;hems.append(he)
    for ob in [o]+hems:
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [o]+hems:ob.select_set(True)
    bpy.context.view_layer.objects.active=o;bpy.ops.object.join()
    for ob in hems:OBJECTS.remove(ob)
    return o,point
def export(name,anchors,notes):
    path=OUT/(name+'.glb')
    if path.exists():raise RuntimeError('Immutable version already exists '+str(path))
    for o in OBJECTS:
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
        layer=o.data.uv_layers.active if o.data.uv_layers else o.data.uv_layers.new(name='Metric')
        for p in o.data.polygons:
            coords=[layer.data[li].uv.copy() for li in p.loop_indices]
            area=sum(a.x*b.y-a.y*b.x for a,b in zip(coords,coords[1:]+coords[:1]))
            if abs(area)>1e-12:continue
            # Solidify's edge UVs collapse; give the actual thin edge a valid
            # local planar metric mapping without disturbing authored face UVs.
            a,b=(0,1) if abs(p.normal.z)>.6 else ((0,2) if abs(p.normal.y)>.6 else (1,2))
            for li in p.loop_indices:
                v=o.data.vertices[o.data.loops[li].vertex_index].co;layer.data[li].uv=(v[a]/.26,v[b]/.26)
    # Fixed support parts merge; separate cloth meshes retain individual anchors.
    fixed=[o for o in OBJECTS if 'rmmo_wind' not in o]
    if fixed:
        bpy.ops.object.select_all(action='DESELECT')
        for o in fixed:o.select_set(True)
        bpy.context.view_layer.objects.active=fixed[0];bpy.ops.object.join();fixed[0].name='Fixed_cord_knots_and_mounts'
        for o in fixed[1:]:OBJECTS.remove(o)
    for o in OBJECTS:
        bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('Explicit triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
    master=OUT/(name+'_master.blend');bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_extras=True,export_tangents=True,export_animations=False,export_cameras=False,export_lights=False)
    # Blender's generic MixRGB does not export its tint as a glTF factor.
    # Preserve the standard texture*factor contract explicitly, without changing
    # the embedded image data, UVs or geometry. Authoring shader uses this factor.
    raw=path.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jl]);binchunk=raw[20+jl:]
    for item in doc.get('materials',[]):
        pbr=item.get('pbrMetallicRoughness',{})
        if 'baseColorTexture' in pbr:pbr['baseColorFactor']=list(bpy.data.materials[item['name']].diffuse_color)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binchunk))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+binchunk)
    vs=[g(o.matrix_world@v.co) for o in OBJECTS for v in o.data.vertices]
    row={'id':name,'path':path.as_posix(),'sha256':sha(path),'bytes':path.stat().st_size,'master':master.as_posix(),'master_sha256':sha(master),'bounds':{'min':[min(p[k] for p in vs) for k in range(3)],'max':[max(p[k] for p in vs) for k in range(3)]},'anchors':anchors,'notes':notes,'triangles':sum(len(o.data.polygons) for o in OBJECTS),'expected_wind_meshes':len([o for o in OBJECTS if 'rmmo_wind' in o]),'inputs':{str(WEAVE):sha(WEAVE)}}
    (OUT/(name+'_authoring.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8');ROWS.append(row)

def string():
    name='s2_yellow_rectangular_festoon_8m';reset(name);span=8.;sag=.48
    tube('Sagging flax main cord',[(x,cord_y(x,span,sag),0) for x in [-4+i*.05 for i in range(161)]],.011,ROPE,8)
    for side in [-1,1]:
        ring('End rope eye '+str(side),(side*4,0,0),.045,.007,ROPE);tie('End knot '+str(side),side*3.96,0)
    lengths=[.68,.56,.77,.62,.90,.71,.63,.85,.70,.95,.73,.87]
    for i,h in enumerate(lengths):
        x=-3.5+i*7/11;w=.44+(i%3)*.035
        o,point=cloth('Yellow_short_rectangle_%02d'%i,x,w,h,span,sag,YELLOW if i%3 else YELLOW2,phase=i*.79,nu=14,nv=20)
        for edge in [-1,1]:
            xx=x+edge*(w/2-.035);yy=cord_y(xx,span,sag)
            ring('Sewn hanging eye '+str((i,edge)),(xx,yy-.006,0),.018,.003,ROPE,axis='x')
    export(name,{'left_end':[-4,0,0],'right_end':[4,0,0],'span':8.,'cord_midpoint':[0,-.48,0],'front_axis':'+Z','mount_height_recommended':4.7,'minimum_static_cloth_height_at_recommended_mount':4.7+min(g(o.matrix_world@v.co)[1] for o in OBJECTS for v in o.data.vertices),'notes':'Root is midpoint of end-to-end chord. Align both eyes to post rings. Do not stretch Y with X; use uniform scale or a correctly sized variant.'},'Reference short yellow rectangular linen, unequal drops, shallow sag. Rope eyes, knots and sewn hems are project additions. No posts, no collision, individual wind anchors.')
def laundry():
    name='s2_wall_to_wall_white_laundry_36m';reset(name);span=3.6;sag=.15
    tube('Wall-to-wall flax line',[(x,cord_y(x,span,sag),0) for x in [-1.8+i*.03 for i in range(121)]],.009,ROPE)
    for side in [-1,1]:
        x=side*1.8;ring('Wall eye '+str(side),(x,0,0),.036,.007,IRON);tube('Eye shank '+str(side),[(x+side*.015,0,0),(x+side*.13,0,0)],.008,IRON)
        box('Wall anchor '+str(side),(x+side*.10,0,0),(.024,.14,.08),IRON);tie('Tie '+str(side),x-side*.05,0)
    for i,(x,w,h) in enumerate([(-1.10,.77,1.21),(-.19,.83,1.39),(.82,1.01,1.16)]):
        o,p=cloth('White_linen_%d'%i,x,w,h,span,sag,WHITE2 if i==1 else WHITE,i*1.3,22,34,.048)
        for edge in [-1,1]:
            xx=x+edge*(w/2-.045);yy=cord_y(xx,span,sag)
            for z in [-.013,.013]:box('Wooden peg '+str((i,edge,z)),(xx,yy-.014,z),(.024,.09,.016),WOOD)
            tube('Peg neck '+str((i,edge)),[(xx-.018,yy+.006,0),(xx+.018,yy+.006,0)],.005,IRON)
    export(name,{'left_end':[-1.8,0,0],'right_end':[1.8,0,0],'span':3.6,'cord_midpoint':[0,-.15,0],'front_axis':'+Z','mount_height_recommended':3.8,'minimum_static_cloth_height_at_recommended_mount':3.8+min(g(o.matrix_world@v.co)[1] for o in OBJECTS for v in o.data.vertices),'wall_planes_x':[-1.90,1.90]},'White household linen between opposing walls. No freestanding posts, no shop canopy, no walking collision. Cloth lengths, folded hems and wall eye fixings are project additions.')
def banner():
    name='s2_ochre_long_banner';reset(name);w=.67;h=2.02
    # Paint belongs in the textile's albedo. A separately tessellated overlay
    # intersects the drape and cannot remain a valid thin pigment layer.
    by,bx=np.mgrid[0:2048,0:1024];u=(bx+.5)/1024;v=1-(by+.5)/2048
    color=np.empty((2048,1024,3),np.float32);color[:]=(.31,.225,.078)
    border=(u<.075)|(u>.925)|(v>.955);color[border]=(.19,.235,.075)
    motif=[(.72,.075),(.33,.18),(.71,.18),(.30,.32),(.70,.32),(.30,.47),(.70,.47),(.31,.62),(.31,.82)]
    segments=list(zip(motif,motif[1:]))+[((.4+k*.13,.90),(.4+k*.13,.80-k*.04)) for k in range(3)]
    distance=np.ones_like(u)*10
    for a,b in segments:
        px=u*w-a[0]*w;py=v*h-a[1]*h;dx=(b[0]-a[0])*w;dy=(b[1]-a[1])*h;t=np.clip((px*dx+py*dy)/(dx*dx+dy*dy),0,1)
        distance=np.minimum(distance,np.sqrt((px-t*dx)**2+(py-t*dy)**2))
    ink=np.clip((.0085-distance)/.0007+.5,0,1)
    color=color*(1-ink[:,:,None])+np.array([.64,.43,.065])*ink[:,:,None]
    tx=u*w/.26;ty=v*h/.26;variation=.86+.035*np.sin(tx*math.tau*37)+.023*np.cos(ty*math.tau*31)+.025*np.sin(tx*math.tau*3+np.sin(ty*math.tau*4))
    color*=np.clip(variation,.7,.98)[:,:,None]
    encoded=np.where(color<=.0031308,color*12.92,1.055*color**(1/2.4)-.055)
    art=textile_map('S2_long_banner_ochre_angular_dye',encoded);art.colorspace_settings.name='sRGB'
    dyed=material('S2 printed ochre and olive linen',(1,1,1),.94)
    bs=dyed.node_tree.nodes.get('Principled BSDF');image_node=dyed.node_tree.nodes.new('ShaderNodeTexImage');image_node.image=art
    dyed.node_tree.links.new(image_node.outputs['Color'],bs.inputs['Base Color'])
    # One normalized UV set for all channels: runtime StandardMaterial does not
    # provide independent UV sets for dye and normal. Bake metric yarn response
    # into this atlas (roughly 2.1 x 2.7 mm yarn period), avoiding UV2 reliance.
    tx=u*math.tau*320;ty=v*math.tau*750
    nx=.14*np.cos(tx)*np.sin(ty);ny=.14*np.sin(tx)*np.cos(ty);nz=np.ones_like(nx);norm=np.sqrt(nx*nx+ny*ny+1)
    normal=textile_map('S2_long_banner_metric_weave_normal',np.stack([nx/norm*.5+.5,ny/norm*.5+.5,nz/norm*.5+.5],axis=-1))
    rough=textile_map('S2_long_banner_linen_roughness',np.clip(.94+.025*np.sin(tx)*np.sin(ty)+.02*np.sin(u*37),.86,1))
    for socket,im in [('Normal',normal),('Roughness',rough)]:
        t=dyed.node_tree.nodes.new('ShaderNodeTexImage');t.image=im
        if socket=='Normal':
            n=dyed.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.65;dyed.node_tree.links.new(t.outputs['Color'],n.inputs['Color']);dyed.node_tree.links.new(n.outputs['Normal'],bs.inputs['Normal'])
        else:dyed.node_tree.links.new(t.outputs['Color'],bs.inputs['Roughness'])
    o,point=cloth('Long_ochre_linen',0,w,h,100,0,dyed,.4,32,76,.018)
    dye_uv=o.data.uv_layers.active
    for loop in o.data.loops:
        p=g(o.data.vertices[loop.vertex_index].co);dye_uv.data[loop.index].uv=(p[0]/w+.5,1-(-p[1]-.025)/h)
    # Keep the existing metric UV active for micro-normal/roughness channels.
    o.data.uv_layers.active_index=0
    # Sewn olive border follows the same drape and is joined to the same wind mesh.
    additions=[]
    def ribbon(n,pts,width,m):
        vs=[];uv=[]
        for i,(u,v) in enumerate(pts):
            p0=Vector(pts[max(0,i-1)]);p1=Vector(pts[min(i+1,len(pts)-1)]);d=p1-p0;d=Vector((d.x*w,d.y*h)).normalized();off=Vector((-d.y,d.x))*width*.5
            for side in [-1,1]:
                uu=u+side*off.x/w;vv=v+side*off.y/h;q=point(uu,vv);vs.append((q[0],q[1],q[2]+.0009));uv.append((uu*w/.26,-vv*h/.26))
        a=mesh(n,vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(len(pts)-1)],m,uv,True);a.modifiers.new('Pigment and stitch relief','SOLIDIFY').thickness=.0005;additions.append(a)
    # Angular non-text symbolic motif inspired by the visible zigzags, not official script.
    motif=[(.72,.075),(.33,.18),(.71,.18),(.30,.32),(.70,.32),(.30,.47),(.70,.47),(.31,.62),(.31,.82)]
    fine=[]
    for a,b in zip(motif,motif[1:]):
        for j in range(10):fine.append((a[0]+(b[0]-a[0])*j/10,a[1]+(b[1]-a[1])*j/10))
    fine.append(motif[-1])
    for ob in additions:
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [o]+additions:ob.select_set(True)
    bpy.context.view_layer.objects.active=o;bpy.ops.object.join()
    for ob in additions:OBJECTS.remove(ob)
    for x in [-.27,.27]:
        # Textile loops wrap the existing lamp crossbar, not rigid decorative rods.
        pts=[(x,-.004+.034*math.sin(a),.034*math.cos(a)) for a in [i*math.tau/32 for i in range(33)]]
        tube('Linen suspension '+str(x),pts,.006,FIELD)
    export(name,{'mount_origin':[0,0,0],'width':w,'cloth_drop':h+.025,'front_axis':'+Z','lamp_local_mount':[-.61,2.835,.038],'lamp_reference_source':'f308819058f9a51e8fecb41b24ac839073153f48481979af18c73c273199a2c9','lamp_variant_replaces_existing_cloth':True},'Reference long ochre/yellow panel with muted olive border and angular yellow ornament. Motif is project supplemental design, not legible official writing. Independent textile; reused lamp assembly is supplied separately to avoid layering it over the red flag.')

string();laundry();banner()
shutil.copy2(__file__,OUT/'build_recipe.py')
(OUT/'manifest.json').write_text(json.dumps({'items':ROWS,'reference':'D:/code/rmmo/docs/references/town_required_shots_20261012/03_festival_residential_lane.webp','formal_map_modified':False},ensure_ascii=False,indent=2),encoding='utf-8')
print('S2_TEXTILES_BUILD_COMPLETE',flush=True)
