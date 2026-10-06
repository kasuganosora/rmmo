"""Original realistic wall banners / red swallowtail gonfalons, offline review.
Blender -b --python this.py. Portable UV PBR, separate rigid and cloth parts.
"""
import bpy, math, json, hashlib, argparse, sys
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]/'rmmo_runtime'
parser=argparse.ArgumentParser();parser.add_argument('--roof-height',type=float,default=7.5);parser.add_argument('--ground-clearance',type=float,default=.3)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
assert 4<=args.roof_height<=15 and .1<=args.ground_clearance<=.8
OUT=ROOT/'art_sources/wall_guild_banners';OUT.mkdir(parents=True,exist_ok=True)
(OUT/'models').mkdir(exist_ok=True);(OUT/'textures').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC'
def mat(name,c,rough=.8,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*c,1)
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(*c,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    return m
iron=mat('Blackened forged iron',(.035,.029,.021),.56,.72)
wood=mat('Dark stained oak crossbar',(.13,.065,.026),.76)
nt=wood.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
for file,socket in [('texture.png','Base Color'),('normal.png','Normal'),('roughness.png','Roughness')]:
    path=ROOT/'packs/default/assets/materials/wood/solid_timber'/file
    if not path.exists():continue
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(path),check_existing=True);tex.image.pack()
    if socket!='Base Color':tex.image.colorspace_settings.name='Non-Color'
    if socket=='Normal':
        n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.35;nt.links.new(tex.outputs[0],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs[socket])
    elif socket=='Roughness':
        sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(tex.outputs[0],sep.inputs[0]);nt.links.new(sep.outputs['Red'],bs.inputs[socket])
    else:nt.links.new(tex.outputs[0],bs.inputs[socket])
brass=mat('Aged brass finials',(.38,.21,.057),.5,.72)
stone=mat('Review warm lime plaster',(.53,.49,.40),.96)
specs=[dict(id='wall_pointed_blue',label='蓝色尖尾墙挂布幡',width=.72,height=1.3,top=2.5,cut=.35,color=[.025,.11,.24],pattern='chalice',preview=-3.0),dict(id='guild_swallowtail_tall',label='公会红色燕尾垂旗-屋檐长款',width=1.15,height=args.roof_height-args.ground_clearance,top=args.roof_height,cut=.72,color=[.34,.014,.022],pattern='compass',preview=0),dict(id='guild_swallowtail_wide',label='公会红色燕尾垂旗-屋檐宽款',width=1.6,height=args.roof_height-args.ground_clearance,top=args.roof_height,cut=.85,color=[.29,.011,.018],pattern='shield',preview=3.2)]
def image(name,pixels,color=True):
    h,w=pixels.shape[:2];im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    im.colorspace_settings.name='sRGB' if color else 'Non-Color';im.pixels.foreach_set(pixels.astype(np.float32).ravel());im.filepath_raw=str(OUT/'textures'/(name+'.png'));im.file_format='PNG';im.save();im.pack();return im
def clothmat(spec):
    w,h=768,1536 if spec['pattern']=='chalice' else 4096;v,u=np.mgrid[0:h,0:w];u=(u+.5)/w;v=1-(v+.5)/h
    edge=1-spec['cut']/spec['height']*((2*abs(u-.5)) if spec['pattern']=='chalice' else (1-2*abs(u-.5)))
    mask=np.zeros((h,w));border=(u<.035)|(u>.965)|(abs(v-edge+.025)<.012)|(v<.018)
    mask[border]=1
    def line(a,b,width=.009):
        ax,ay=a;bx,by=b
        factor=1 if spec['pattern']=='chalice' else 1.5*spec['width']/spec['height']
        if spec['pattern']!='chalice':ay=.25+(ay-.34)*factor;by=.25+(by-.34)*factor
        dx=bx-ax;dy=(by-ay)/factor;t=np.clip(((u-ax)*dx+((v-ay)/factor)*dy)/(dx*dx+dy*dy),0,1)
        d=np.sqrt((u-ax-t*dx)**2+((v-ay)/factor-t*dy)**2);np.maximum(mask,np.clip((width-d)*w+0.5,0,1),out=mask)
    if spec['pattern']=='chalice':
        for a,b in [((.27,.19),(.73,.19)),((.27,.19),(.36,.39)),((.73,.19),(.64,.39)),((.36,.39),(.5,.45)),((.64,.39),(.5,.45)),((.5,.45),(.5,.65)),((.35,.65),(.65,.65)),((.30,.22),(.7,.59)),((.70,.22),(.3,.59))]:line(a,b)
    elif spec['pattern']=='compass':
        cx,cy=.5,.34
        for k in range(8):
            t=k*math.pi/4;rad=.24 if k%2==0 else .15
            line((cx,cy),(cx+math.sin(t)*rad,cy+math.cos(t)*rad*.66),.011)
        ring=np.sqrt(((u-cx)/.135)**2+((v-.25)/(.09*1.5*spec['width']/spec['height']))**2);np.maximum(mask,np.clip((.07-abs(ring-1))*w*.1,0,1),out=mask)
        for a,b in [((.5,.57),(.5,.77)),((.36,.63),(.5,.72)),((.64,.63),(.5,.72))]:line(a,b)
    else:
        for a,b in [((.29,.17),(.71,.17)),((.29,.17),(.32,.40)),((.71,.17),(.68,.40)),((.32,.40),(.5,.55)),((.68,.40),(.5,.55)),((.5,.21),(.5,.47)),((.39,.34),(.61,.34))]:line(a,b,.012)
    rng=np.random.default_rng(620);noise=rng.normal(0,1,(h,w))
    weave=np.sin(u*math.tau*180)*np.sin(v*math.tau*min(1200,170*spec['height']))
    variation=.93+.025*weave+.018*noise+.035*np.sin(u*32+np.sin(v*18))
    ink=np.array([.73,.49,.16]);base=np.array(spec['color']);rgb=(base[None,None,:]*(1-mask[:,:,None])+ink*mask[:,:,None])*variation[:,:,None]
    # Two sewn hem lines, small interrupted stitches rather than metallic strips.
    stitches=(((abs(u-.022)<.0016)|(abs(u-.978)<.0016)) & ((v*150)%1<.55)) | ((abs(v-edge+.024)<.0018) & ((u*100)%1<.55))
    rgb[stitches]=np.array([.48,.29,.10])
    rgba=np.ones((h,w,4));rgba[:,:,:3]=np.clip(rgb,0,1);albedo=image(spec['id']+'_artwork',rgba)
    # Physical small yarn relief, no procedural nodes left for the GLB to lose.
    height=.6*weave+.12*noise+.4*stitches.astype(float);gy,gx=np.gradient(height)
    normal=np.stack([-gx*.28,-gy*.28,np.ones_like(gx)],axis=2);normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    rgba[:,:,:3]=normal*.5+.5;nmap=image('woven_normal' if spec==specs[0] else spec['id']+'_normal',rgba,False)
    rough=np.clip(.9+.035*weave+.025*noise-mask*.05,.72,1);rgba[:,:,:3]=rough[:,:,None];rmap=image(spec['id']+'_roughness',rgba,False)
    m=mat('Replaceable textile - '+spec['id'],spec['color']);m.use_backface_culling=False;nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Specular IOR Level'].default_value=.2
    for im,socket in [(albedo,'Base Color'),(nmap,'Normal'),(rmap,'Roughness')]:
        t=nt.nodes.new('ShaderNodeTexImage');t.image=im;t.name='REPLACE ARTWORK' if socket=='Base Color' else socket
        if socket=='Normal':
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.6;nt.links.new(t.outputs[0],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs[socket])
        elif socket=='Roughness':
            sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(t.outputs[0],sep.inputs[0]);nt.links.new(sep.outputs['Red'],bs.inputs[socket])
        else:nt.links.new(t.outputs[0],bs.inputs[socket])
    return m
for spec in specs:spec['mat']=clothmat(spec)
def rod(name,start,end,radius,material):
    d=Vector(end)-Vector(start);bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=radius,depth=d.length,location=(Vector(start)+Vector(end))/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    be=o.modifiers.new('Soft worked edges','BEVEL');be.width=.004;be.segments=2
    return o
def cube(name,loc,scale,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material);be=o.modifiers.new('Forged rounded edges','BEVEL');be.width=.012;be.segments=3;return o
def body(spec,nx,ny):
    W,H,C=spec['width'],spec['height'],spec['cut'];top=spec['top'];r=.04
    verts=[];uvs=[];faces=[]
    # One continuous cloth surface: front, rounded fold over rod, short rear flap.
    rows=[('front',1-j/ny) for j in range(ny+1)]+[('arc',j/10) for j in range(1,11)]+[('back',j/5) for j in range(1,6)]
    for mode,t in rows:
        for i in range(nx+1):
            u=i/nx;length=H-C*(2*abs(u-.5) if spec['pattern']=='chalice' else 1-2*abs(u-.5))
            if mode=='front':s=t*length;y=-r;z=top-s;v=1-s/H;weight=min(1,s/.3);fold=.028*math.sin(u*math.tau*2.7+.4)+.012*math.sin(u*math.tau*5+s*2);y+=weight*fold+.025*(s/H)**2*math.sin(s*6+u*4);z+=.01*weight*math.sin(u*12)
            elif mode=='arc':s=0;y=-r*math.cos(t*math.pi);z=top+r*math.sin(t*math.pi);v=1-t*.02
            else:s=t*.16;y=r+.009*t*math.sin(u*17);z=top-s;v=.98-s/H
            verts.append(((u-.5)*W,y,z));uvs.append((u,v))
    for j in range(len(rows)-1):
        for i in range(nx):
            q=j*(nx+1)+i;faces.append((q,q+1,q+nx+2,q+nx+1))
    mesh=bpy.data.meshes.new(spec['id']+'_cloth');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new(spec['id']+'_cloth',mesh);sc.collection.objects.link(o);mesh.materials.append(spec['mat'])
    uv=mesh.uv_layers.new(name='ReplaceableArtworkUV')
    for loop in mesh.loops:uv.data[loop.index].uv=uvs[loop.vertex_index]
    for poly in mesh.polygons:poly.use_smooth=True
    o.shape_key_add(name='Basis');key=o.shape_key_add(name='Breeze preview')
    for point in key.data:
        drop=max(0,top-point.co.z);weight=min(1,drop/H)**1.6
        point.co.y+=.12*weight*math.sin(point.co.x*5+drop*4);point.co.x+=.018*weight*math.sin(drop*4)
    sol=o.modifiers.new('Woven fabric thickness 1.6mm','SOLIDIFY');sol.thickness=.0016;sol.offset=0
    o['rmmo_wind']={'profile':'cloth','mesh':'*','amplitude':.12,'stiffness':.48,'anchor':'top','shelter':True};o['rmmo_collision']='none';o['artwork_slot']='ReplaceableArtworkUV; BaseColor; whole fabric including gold pigment'
    return o
assets=[]
for spec in specs:
    W=spec['width'];parts=[]
    parts.append(rod('Oak crossbar',(-W/2-.14,0,2.5),(W/2+.14,0,2.5),.032,wood))
    for x in [-W/2-.1,W/2+.1]:
        parts.append(cube('Iron wall plate',(x,.42,2.4),(.10,.035,.33),iron))
        parts.append(rod('Wall arm',(x,.4,2.5),(x,0,2.5),.018,iron))
        parts.append(rod('Diagonal brace',(x,.4,2.28),(x,.03,2.5),.013,iron))
        for z in [2.3,2.51]:parts.append(rod('Wall bolt',(x,.393,z),(x,.405,z),.012,brass))
    for x in [-W/2-.17,W/2+.17]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.046,location=(x,0,2.5));o=bpy.context.object;o.name='Rod end stop';o.data.materials.append(brass);parts.append(o)
    for o in parts:o.location.z+=spec['top']-2.5
    cloth=body(spec,48,160 if spec['height']>3 else 80);parts.append(cloth)
    for o in parts:o.location.x+=spec['preview']
    assets.append(dict(spec=spec,parts=parts,cloth=cloth))
cube('Review wall',(0,.49,(args.roof_height+.25)/2),(13,.12,args.roof_height+.25),stone);cube('Review floor',(0,-2,-.02),(30,30,.04),stone)
roofmat=mat('Review terracotta eave',(.25,.067,.025),.85)
cube('Review eave at roofline',(0,.42,args.roof_height+.25),(13.3,.65,.18),roofmat)
for z in [2.7,5.2]:cube('Review storey band',(0,.40,z),(13,.09,.12),stone)
cube('Review 2.2m entrance for scale',(-4.8,.365,1.1),(1.15,.06,2.2),wood)
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.65,.75,.9,1);bg.inputs[1].default_value=.45
bpy.ops.object.light_add(type='AREA',location=(-3,-6,10));light=bpy.context.object;light.data.energy=2400;light.data.size=6;light.rotation_euler=(Vector((0,0,4))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(5,-12,4.6));cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO'
sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True;sc.render.resolution_x=1500;sc.render.resolution_y=1100;sc.view_settings.view_transform='AgX'
def view(loc,target,scale):cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
def render(name):sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
def tris(o):
    eo=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=eo.to_mesh();me.calc_loop_triangles();n=len(me.loop_triangles);eo.to_mesh_clear();return n
view((6,-20,10),(0,0,args.roof_height*.51),10.6)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'wall_guild_banners_master.blend'),compress=True)
for a in assets:a['master_triangles']=sum(tris(o) for o in a['parts'])
render('master_overview');view((1.1,-3,args.roof_height-1.5),(0,0,args.roof_height-specs[1]['height']*.25),1.5);render('master_close')
for a in assets:
    old=a['cloth'];a['parts'].remove(old);bpy.data.objects.remove(old,do_unlink=True)
    cloth=body(a['spec'],32,112 if a['spec']['height']>3 else 48);cloth.location.x=a['spec']['preview'];a['cloth']=cloth;a['parts'].append(cloth)
render('optimized_close');view((6,-20,10),(0,0,args.roof_height*.51),10.6);render('optimized_overview')
for a in assets:a['cloth'].data.shape_keys.key_blocks['Breeze preview'].value=1
render('breeze_preview')
for a in assets:a['cloth'].data.shape_keys.key_blocks['Breeze preview'].value=0
view((4,-2,args.roof_height+.6),(3.2,0,args.roof_height-.1),1.8);render('mount_and_fold_detail')
view((6,-20,10),(0,0,args.roof_height*.51),10.6);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'wall_guild_banners_optimized.blend'),compress=True)
manifest=[]
for a in assets:
    spec=a['spec'];bpy.ops.object.select_all(action='DESELECT')
    for o in a['parts']:o.location.x-=spec['preview'];o.select_set(True)
    evaluated_triangles=sum(tris(o) for o in a['parts'])
    bpy.ops.object.select_all(action='DESELECT')
    rigid=[o for o in a['parts'] if o!=a['cloth']]
    for o in rigid:
        o.select_set(True);bpy.context.view_layer.objects.active=o
        for modifier in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
        o.select_set(False)
    for o in rigid:o.select_set(True)
    bpy.context.view_layer.objects.active=rigid[0];bpy.ops.object.join();structure=bpy.context.object;structure.name=spec['id']+'_rigid_support'
    a['parts']=[structure,a['cloth']];a['cloth'].select_set(True)
    path=OUT/'models'/(spec['id']+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_morph=False,export_apply=True)
    manifest.append(dict(id=spec['id'],label=spec['label'],width=spec['width'],height=spec['height'],mount_height=spec['top'],tip_clearance=spec['top']-spec['height'],cut_depth=spec['cut'],master_triangles=a['master_triangles'],game_triangles=evaluated_triangles,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),cloth_thickness=.0016,wall_standoff=.42,artwork='textures/'+spec['id']+'_artwork.png',wind='metadata only; Blender breeze shape key intentionally not exported'))
    for o in a['parts']:o.location.x+=spec['preview']
(OUT/'manifest.json').write_text(json.dumps(dict(status='offline review; not published',assets=manifest),ensure_ascii=False,indent=2),encoding='utf8')
print('WALL_GUILD_BANNERS_COMPLETE',flush=True)
