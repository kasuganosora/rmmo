"""Reference finish on v4 master. Run Blender background; no production writes.

Fishscale and weave maps are procedural PBR sources, not altered reference images.
Glass tessellation and unseen fittings are project supplemental design.
"""
import bpy, json, math, sys, hashlib, struct
import numpy as np
from pathlib import Path
from mathutils import Vector

ROOT=Path('D:/code/rmmo')
BASE=ROOT/'review_artifacts/axel_guild_materials_20261011'
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'axel_guild_materials_v4.blend'))
SC=bpy.context.scene
initial=set(bpy.data.objects)

def save_map(name,arr,color=False):
    h,w=arr.shape[:2]
    if arr.ndim==2:arr=np.repeat(arr[:,:,None],3,axis=2)
    rgba=np.concatenate([arr,np.ones((h,w,1),dtype=np.float32)],axis=2)
    im=bpy.data.images.new(name,width=w,height=h,alpha=False)
    im.colorspace_settings.name='sRGB' if color else 'Non-Color'
    im.pixels.foreach_set(np.flipud(rgba).astype(np.float32).ravel())
    im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save();im.pack()
    return im

def link_map(mat,im,socket):
    nt=mat.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    for l in list(p.inputs[socket].links):nt.links.remove(l)
    t=nt.nodes.new('ShaderNodeTexImage');t.image=im;t.extension='REPEAT'
    if socket=='Normal':
        n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.45
        nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs['Normal'],p.inputs[socket])
    else:nt.links.new(t.outputs['Color'],p.inputs[socket])

# Six staggered courses across .72m and four .25m-wide round-ended tiles.
# Evaluate a periodic family of overlapping tiles. Upper rows cover lower rows.
n=1024;yy,xx=np.mgrid[0:n,0:n].astype(np.float32);x=xx/n*4;y=yy/n*6
height=np.zeros((n,n),np.float32);variation=np.zeros_like(height);edge=np.zeros_like(height)
for row in range(7,-3,-1):
    shift=(row%2)*.5;col=np.floor(x-shift+.5);dx=x-shift-col
    tip=row+.55+np.sqrt(np.maximum(0,.25-dx*dx))*1.50
    mask=(y>=row-.6)&(y<=tip)
    rim=np.minimum(.5-np.abs(dx),(tip-y)*.6)
    chamfer=np.clip(rim/.024,0,1)
    h=(.35+.20*np.clip(y-row,0,1.3))*chamfer
    var=np.sin((col%4)*19.2+(row%6)*7.8)*.045
    height[mask]=h[mask];variation[mask]=np.broadcast_to(var,height.shape)[mask];edge[mask]=chamfer[mask]
# Periodic multiscale mineral grain: no random discontinuity at tile borders.
noise=(np.sin(xx/n*2*math.pi*173)*np.sin(yy/n*2*math.pi*139)*.014+
       np.sin(xx/n*2*math.pi*23+np.sin(yy/n*2*math.pi*17))*.021)
base=np.stack([.57+variation+noise,.255+variation*.55+noise*.6,.112+variation*.3+noise*.35],axis=2)
base*= (.58+.42*edge)[:,:,None]
albedo=save_map('guild_fishscale_albedo',np.clip(base,0,1),True)
rough=save_map('guild_fishscale_roughness',np.clip(.77+noise+variation*.3,0,1))
dx=(np.roll(height,-1,1)-np.roll(height,1,1))*2.3
dy=(np.roll(height,-1,0)-np.roll(height,1,0))*2.3
normal=np.stack([-dx,dy,np.ones_like(dx)],axis=2);normal/=np.linalg.norm(normal,axis=2)[:,:,None]
normal=save_map('guild_fishscale_normal',normal*.5+.5)
roof=bpy.data.materials['Guild PBR | terracotta']
for im,socket in [(albedo,'Base Color'),(rough,'Roughness'),(normal,'Normal')]:link_map(roof,im,socket)
roof['reference']='U19 fishscale roof; project-authored PBR'

def mat(name,color,metal=0,rough=.3):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

def mesh(name,verts,faces,material,group,collision=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.materials.append(material);data.update()
    o=bpy.data.objects.new(name,data);bpy.data.collections[group].objects.link(o)
    o.parent=bpy.data.objects.get(group)
    o['semantic_group']=group;o['collision_review']=collision;o['material_pass']='reference_finish_v5'
    o['rmmo_collision']='none' if not collision else 'block'
    o['reference_status']='Project supplemental detailing based on U16/U18/U19'
    return o

lead=mat('Guild window dark lead',(.045,.05,.045),.78,.42)
glass=[mat('Guild stained glass '+str(i),c,0,.17) for i,c in enumerate([
    (.008,.026,.24),(.29,.002,.008),(.33,.16,.008),(.008,.17,.045),(.055,.008,.17)])]
for m in glass:
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Coat Weight'].default_value=.12;p.inputs['IOR'].default_value=1.52
    p.inputs['Alpha'].default_value=.90;p.inputs['Transmission Weight'].default_value=.25
    m.diffuse_color=(*m.diffuse_color[:3],.90);m.surface_render_method='BLENDED'
    m.use_backface_culling=False
    m['reference']='User stained glass palette 2026-10-12; cobalt/ruby dominant, amber/emerald accents'
    m['backlight_note']='Thin tinted glass; no baked emission or promised coloured caustics'
palette=[0,1,0,1,0,2,1,3,0,1,4,0]

def ring(name,cx,cy,cz,r,width,group):
    verts=[];faces=[]
    for k in range(96):
        a=k*math.tau/96
        for rr in [r-width/2,r+width/2]:verts.append((cx+rr*math.cos(a),cy,cz+rr*math.sin(a)))
    for k in range(96):faces.append((2*k,2*k+1,(2*k+3)%192,(2*k+2)%192))
    return mesh(name,verts,faces,lead,group)

# Rose opening: all panels sit behind the existing stone spokes, not over them.
rose_radii=[0,.18,.32,.46,.60,.74,.88,1.01,1.135]
for layer,(r0,r1) in enumerate(zip(rose_radii[:-1],rose_radii[1:])):
    for sector in range(32):
        a0=sector*math.tau/32+.004;a1=(sector+1)*math.tau/32-.004
        verts=[(16+r*math.cos(a),-.475,9.4+r*math.sin(a)) for r,a in [(r0,a0),(r1,a0),(r1,a1),(r0,a1)]]
        mesh('Rose coloured pane',verts,[(0,1,2,3)],glass[palette[(sector+layer*3)%len(palette)]],'12_Facade_Detail')
for r in rose_radii[1:]:ring('Rose lead concentric',16,-.485,9.4,r,.014,'12_Facade_Detail')
for k in range(32):
    a=k*math.tau/32;perp=Vector((-math.sin(a),math.cos(a)))*.006
    verts=[(16+r*math.cos(a)+s*perp.x,-.485,9.4+r*math.sin(a)+s*perp.y) for r,s in [(0,-1),(1.135,-1),(1.135,1),(0,1)]]
    mesh('Rose radial lead joint',verts,[(0,1,2,3)],lead,'12_Facade_Detail')
for o in bpy.data.objects:
    if o.type=='MESH' and o.name.startswith(('Rose window tracery','Fanlight radial','Fanlight transom')):
        o.data.materials.clear();o.data.materials.append(lead)
for cx in [22.8,24.65,26.5,28.35]:
    # Only the upper fanlight is glazed; the registration service opening stays open.
    for k in range(12):
        a0=k*math.pi/12+.012;a1=(k+1)*math.pi/12-.012
        verts=[(cx,10.91,2.685)]+[(cx+.675*math.cos(a),10.91,2.65+.675*math.sin(a)) for a in [a0,a1]]
        o=mesh('Registration jewel fanlight pane',verts,[(0,1,2)],glass[palette[k]],'40_Reception_L0')
        o['window_id']='reception_'+str(cx)
    for k in range(13):
        a=k*math.pi/12;dx=-math.sin(a)*.008;dz=math.cos(a)*.008
        verts=[(cx+dx,10.90,2.65+dz),(cx+.675*math.cos(a)+dx,10.90,2.65+.675*math.sin(a)+dz),
               (cx+.675*math.cos(a)-dx,10.90,2.65+.675*math.sin(a)-dz),(cx-dx,10.90,2.65-dz)]
        o=mesh('Registration lead divider',verts,[(0,1,2,3)],lead,'40_Reception_L0');o['window_id']='reception_'+str(cx)

# Wood strips are flush decorative inlays; existing floor remains the walk surface.
oak=bpy.data.materials['Guild PBR | structural oak'];g='00_Foundation'
def inlay(name,x0,x1,y0,y1):
    o=mesh(name,[(x0,y0,.002),(x1,y0,.002),(x1,y1,.002),(x0,y1,.002)],[(0,1,2,3)],oak,g)
    uv=o.data.uv_layers.new(name='MetresUV')
    for li in o.data.polygons[0].loop_indices:
        v=o.data.vertices[o.data.loops[li].vertex_index].co
        uv.data[li].uv=(v.x/.8,v.y/2.4) if y1-y0>x1-x0 else (v.y/.8,v.x/2.4)
    o['floor_inlay']=True
xs=[.55+2.8*i for i in range(12) if .55+2.8*i<31.5];ys=[.55+2.8*i for i in range(5)];w=.16
for x in xs:inlay('L0 oak grid longitudinal',x,x+w,.5,13.5)
for y in ys:
    last=.5
    for x in xs:
        if x>last:inlay('L0 oak grid transverse',last,x,y,y+w)
        last=x+w
    if last<31.5:inlay('L0 oak grid transverse',last,31.5,y,y+w)

# Shared weave normal and roughness on the existing separate banner colours.
k=256;v,u=np.mgrid[0:k,0:k].astype(np.float32)
weave=.5+.18*np.sin(u*math.tau/8)*np.sin(v*math.tau/8)
nx=(np.roll(weave,-1,1)-np.roll(weave,1,1))*.25;ny=(np.roll(weave,-1,0)-np.roll(weave,1,0))*.25
wn=np.stack([-nx,ny,np.ones_like(nx)],axis=2);wn/=np.linalg.norm(wn,axis=2)[:,:,None]
weave_im=save_map('guild_banner_weave_normal',wn*.5+.5)
for key in ['banner blue','banner gold','banner red']:
    link_map(bpy.data.materials['Guild PBR | '+key],weave_im,'Normal')

# Replace the angular placeholder crest with curved embroidered wings and loops.
# This is a project interpretation of the partly occluded U19 emblem, not a logo scan.
from mathutils.geometry import tessellate_polygon
gold=bpy.data.materials['Guild PBR | banner gold']
def crest_polygon(name,points):
    verts=[Vector((16+x,-2.449,6.28+z)) for x,z in points]
    tris=tessellate_polygon([verts])
    lookup={tuple(v):i for i,v in enumerate(verts)}
    o=mesh(name,verts,[tuple(v if isinstance(v,int) else lookup[tuple(v)] for v in t) for t in tris],gold,'12_Facade_Detail')
    o['finish_component']='guild_emblem'
    return o
wing=[(-.06,.33),(-.16,.60),(-.31,.76),(-.45,.78),(-.54,.97),(-.63,.89),(-.78,.71),(-.91,.47),(-1.00,.16),(-1.01,-.16),(-.88,.00),(-.72,.14),(-.50,.23),(-.28,.21),(-.14,.10)]
def smooth_loop(points):
    p=[Vector(v) for v in points];out=[]
    for i in range(len(p)):
        a,b,c,d=p[(i-1)%len(p)],p[i],p[(i+1)%len(p)],p[(i+2)%len(p)]
        for k in range(5):
            t=k/5;v=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            out.append(tuple(v))
    return out
for o in list(bpy.data.objects):
    if o.name.startswith('Guild bird'):bpy.data.objects.remove(o,do_unlink=True)
crest_polygon('Guild embroidered left wing',smooth_loop(wing))
crest_polygon('Guild embroidered right wing',[(-x,z) for x,z in reversed(smooth_loop(wing))])
crest_polygon('Guild embroidered central spear',[(-.12,.36),(-.075,.91),(0,1.10),(.075,.91),(.12,.36),(.08,-.49),(.20,-.62),(0,-.94),(-.20,-.62),(-.08,-.49)])
for cx in [-.22,.22]:
    verts=[];faces=[]
    for k in range(64):
        a=k*math.tau/64
        for offset in [-.025,.025]:verts.append((16+cx+(.30+offset)*math.cos(a),-2.447,5.99+(.43+offset)*math.sin(a)))
    for k in range(64):faces.append((2*k,2*k+1,(2*k+3)%128,(2*k+2)%128))
    o=mesh('Guild embroidered loop',verts,faces,gold,'12_Facade_Detail');o['finish_component']='guild_emblem'

# A thin hanging textile, not the old 4cm solid whitebox plate.
import bmesh
blue=bpy.data.materials['Guild PBR | banner blue'];red=bpy.data.materials['Guild PBR | banner red']
for material,color in [(blue,(.008,.065,.09)),(red,(.20,.012,.008)),(gold,(.48,.34,.075))]:
    p=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=0
    p.inputs['Roughness'].default_value=.96;p.inputs['Specular IOR Level'].default_value=.18
    material.use_backface_culling=False
for o in list(bpy.data.objects):
    if o.name.startswith(('Guild shield banner','Banner narrow border','Banner hanging loop')):
        bpy.data.objects.remove(o,do_unlink=True)
verts=[];faces=[];nx=48;nz=44
for iz in range(nz+1):
    t=iz/nz
    for ix in range(nx+1):
        x=14.45+3.1*ix/nx;bottom=4.75+.77*abs(x-16)/1.55
        verts.append((x,-2.38,7.75*(1-t)+bottom*t))
for iz in range(nz):
    for ix in range(nx):
        i=iz*(nx+1)+ix;faces.append((i,i+1,i+nx+2,i+nx+1))
cloth=mesh('Guild hanging wool banner',verts,faces,blue,'12_Facade_Detail');cloth.data.materials.append(red)
for f in cloth.data.polygons:
    c=f.center;v=[cloth.data.vertices[i].co for i in f.vertices]
    x=sum(p.x for p in v)/len(v);z=sum(p.z for p in v)/len(v);bottom=4.75+.77*abs(x-16)/1.55
    if x<14.53 or x>17.47 or z>7.68 or z<bottom+.08:f.material_index=1
cloth['finish_component']='guild_banner_cloth'
def cloth_depth(x,z):
    t=max(0,min(1,(7.75-z)/3))
    return -2.38-t*(.065*math.sin((x-14.45)*math.tau/1.05)+.03*math.sin((x-14.45)*math.tau/.43))-.08*t*t
for o in list(bpy.data.objects):
    if o.get('finish_component')!='guild_emblem':continue
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=3,use_grid_fill=True)
    bm.to_mesh(o.data);bm.free();o['finish_component']='guild_banner_cloth';o['embroidered_overlay']=True
for o in bpy.data.objects:
    if o.get('finish_component')!='guild_banner_cloth':continue
    for v in o.data.vertices:
        v.co.y=cloth_depth(v.co.x,v.co.z)-(.0015 if o.get('embroidered_overlay') else 0)
    uv=o.data.uv_layers.new(name='FabricMetresUV')
    for loop in o.data.loops:
        co=o.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(co.x/.32,co.z/.32)
    for p in o.data.polygons:p.use_smooth=True

# Bake the authored vector embroidery into the fabric colour atlas. A second
# triangulation floating above curved cloth intersected it between vertices;
# one deforming surface now carries cloth, border and motif without z-fighting.
resolution=2048
gy,gx=np.mgrid[0:resolution,0:resolution].astype(np.float32)
px=14.45+3.1*(gx+.5)/resolution;pz=7.75-3*(gy+.5)/resolution
motif=np.zeros((resolution,resolution),dtype=bool)
for o in list(bpy.data.objects):
    if not o.get('embroidered_overlay'):continue
    # Original loops are analytic rings; subdivided triangle edges are not a
    # reliable polygon outline, so use the same authoring contours as above.
    bpy.data.objects.remove(o,do_unlink=True)
def polygon_mask(points):
    inside=np.zeros_like(motif)
    for (x1,z1),(x2,z2) in zip(points,points[1:]+points[:1]):
        if abs(z2-z1)<1e-8:continue
        inside^=((z1>pz)!=(z2>pz))&(px<(x2-x1)*(pz-z1)/(z2-z1)+x1)
    return inside
for points in [smooth_loop(wing),[(-x,z) for x,z in smooth_loop(wing)],
    [(-.12,.36),(-.075,.91),(0,1.10),(.075,.91),(.12,.36),(.08,-.49),(.20,-.62),(0,-.94),(-.20,-.62),(-.08,-.49)]]:
    motif|=polygon_mask([(16+x,6.28+z) for x,z in points])
for cx in [-.22,.22]:
    outer=((px-16-cx)/.325)**2+((pz-5.99)/.455)**2
    inner=((px-16-cx)/.275)**2+((pz-5.99)/.405)**2
    motif|=(outer<=1)&(inner>=1)
color=np.empty((resolution,resolution,3),np.float32);color[:]=(.008,.065,.09)
border=(px<14.515)|(px>17.485)|(pz>7.685)|(pz<4.75+.77*np.abs(px-16)/1.55+.065)
color[border]=(.20,.012,.008);color[motif]=(.48,.34,.075)
atlas=save_map('guild_banner_embroidered_colour',color,True)
fabric=blue.copy();fabric.name='Guild woven heraldic cloth atlas'
link_map(fabric,atlas,'Base Color')
tex=next(n for n in fabric.node_tree.nodes if n.type=='TEX_IMAGE' and n.image==atlas)
uv_node=fabric.node_tree.nodes.new('ShaderNodeUVMap');uv_node.uv_map='BannerArtworkUV'
fabric.node_tree.links.new(uv_node.outputs['UV'],tex.inputs['Vector'])
cloth.data.materials.clear();cloth.data.materials.append(fabric)
for p in cloth.data.polygons:p.material_index=0
uv=cloth.data.uv_layers.new(name='BannerArtworkUV')
for loop in cloth.data.loops:
    p=cloth.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((p.x-14.45)/3.1,(p.z-4.75)/3)
# Runtime cloth shaders consume UV0 for every texture. Use a single artwork UV
# for both colour and woven normal so the crest survives the wind material path.
cloth.data.uv_layers.remove(cloth.data.uv_layers['FabricMetresUV'])
cloth.data.uv_layers.active_index=0
wx=.025*np.cos((px-14.45)*math.tau/.012)
wz=.025*np.cos((pz-4.75)*math.tau/.012)
nw=np.stack([wx,wz,np.ones_like(wx)],axis=2);nw/=np.linalg.norm(nw,axis=2)[:,:,None]
cloth_normal=save_map('guild_banner_atlas_weave_normal',nw*.5+.5)
link_map(fabric,cloth_normal,'Normal')

iron=bpy.data.materials['Guild PBR | forged iron']
def support_beam(name,a,b,width,material=iron):
    a,b=Vector(a),Vector(b);direction=(b-a).normalized()
    right=direction.cross(Vector((0,0,1)))
    if right.length<.01:right=direction.cross(Vector((1,0,0)))
    right.normalize();up=direction.cross(right).normalized()
    vs=[p+width/2*(r*right+s*up) for p in [a,b] for r,s in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    o=mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],material,'12_Facade_Detail')
    o['finish_component']='guild_banner_brackets';return o
for x in [14.3,17.7]:
    support_beam('Banner diagonal iron stay',(x,-.13,6.65),(x,-2.35,7.90),.075)
    support_beam('Banner vertical wall tie',(x,-.13,6.57),(x,-.13,8.01),.075)
    for z in [6.66,7.91]:
        for dz in [-.15,.15]:
            support_beam('Banner wall fixing plate',(x-.115,-.055,z+dz),(x+.115,-.055,z+dz),.095)
            for dx in [-.072,.072]:support_beam('Banner masonry bolt',(x+dx,-.165,z+dz),(x+dx,.06,z+dz),.035)
for x in [14.65,15.30,16,16.70,17.35]:
    # A fabric loop wraps around the suspension rail; its lower end meets the top hem.
    vs=[];fs=[]
    for k in range(16):
        a=k*math.tau/16
        for side in [-1,1]:vs.append((x+side*.035,-2.38+.048*math.cos(a),7.82+.115*math.sin(a)))
    for k in range(16):fs.append((2*k,2*k+1,(2*k+3)%32,(2*k+2)%32))
    o=mesh('Banner sewn fabric suspension loop',vs,fs,red,'12_Facade_Detail');o['finish_component']='guild_banner_loops'

# Repair roof junctions and add the previously missing entrance standards.
sys.path.insert(0,str(ROOT/'tools'))
from axel_guild_finish_structure import build as build_structure
structure_report=build_structure(globals())
from axel_guild_entry_alignment import align as align_entry
entry_report=align_entry()

# Keep the five glazed openings replaceable, but do not export one node per pane.
joins={}
for o in list(bpy.data.objects):
    if o in initial or o.type!='MESH':continue
    key='floor_inlay' if o.get('floor_inlay') else o.get('finish_component',o.get('window_id','rose_window'))
    joins.setdefault(key,[]).append(o)
for key,objects in joins.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.hide_set(False);o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join();obj=bpy.context.view_layer.objects.active
    obj.name='Guild finish '+key
    obj['independent_prop']=key!='floor_inlay'
    obj['replaceable_window']=key=='rose_window' or key.startswith('reception_')
    obj['finish_component']=key
    if key=='guild_banner_cloth':
        obj['rmmo_wind']={'profile':'cloth','mesh':'*','amplitude':.10,'stiffness':.60,'anchor':'top','shelter':True}
        obj['rmmo_collision']='none';obj['structural_wall']=False
        obj['fabric_thickness_m']=.002;obj['artwork_slot']='Woven colour atlas on shared UV0; no separate floating embroidery geometry'

# Remove only editor scale figures from this new master, never the archived v4.
removed=[o for o in bpy.data.objects if o.get('semantic_group','').startswith('60_')]
for o in removed:bpy.data.objects.remove(o,do_unlink=True)
for c in bpy.data.collections:c.hide_viewport=False
bpy.ops.object.select_all(action='DESELECT')
selected=[]
for o in bpy.data.objects:
    if not o.get('semantic_group','').startswith(('60_','70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT'):
        o.hide_set(False);o.select_set(True);selected.append(o)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_finish.blend'),compress=True)
path=OUT/'axel_guild_finish_raw.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
# Preserve the established tint workaround (Blender MixRGB export omits factor).
b=path.read_bytes();size,kind=struct.unpack_from('<II',b,12);j=json.loads(b[20:20+size]);binary=b[20+size:]
specs=json.loads((BASE/'material_review.json').read_text(encoding='utf8'))['materials']
for m in j['materials']:
    key=m.get('name','').removeprefix('Guild PBR | ');p=m.get('pbrMetallicRoughness',{})
    if key in specs and 'color' in specs[key] and 'baseColorTexture' in p:p['baseColorFactor']=list(specs[key]['color'])+[1]
payload=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4)
path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),kind)+payload+binary)
report=dict(source=str(BASE/'axel_guild_materials_v4.blend'),candidate=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
    removed_scale_nodes=len(removed),new_objects=sum(o not in initial for o in selected),
    roof_structure=structure_report,entry_alignment=entry_report,
    intentional_changes=['fishscale roof PBR','jewel rose and registration fanlight glazing','flush oak floor grid','draped cloth crest and triangular brackets','roof junctions and entrance crescent standards'],
    scope='Offline reference finish; runtime light/door/cutaway integration remains separate',review='pending')
(OUT/'finish_build.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('GUILD_FINISH_BUILT',json.dumps(report),flush=True)

