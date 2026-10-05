"""Colored timber posts, fixed golden silk, proximity-linked bunting. Review only."""
import bpy,math,json,random,argparse,sys
from pathlib import Path
from mathutils import Vector,Matrix
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--config',default=str(ROOT/'tools/town_festival_posts_parameters.json'))
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
cfg=json.loads(Path(args.config).read_text(encoding='utf-8-sig'))
OUT=ROOT.parent/'rmmo_runtime/art_sources/town_festival_posts';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
random.seed(10530);H=float(cfg['height_m']);R=float(cfg['radius_m'])
if not (2.4<=H<=4.5 and .12<=R<=.3):raise ValueError('Invalid post dimensions')

def material(name,color,rough=.7):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=0
    return m
gold=material('FIXED golden yellow silk',(0.88,.51,.045),.33)
p=gold.node_tree.nodes.get('Principled BSDF');p.inputs['Sheen Weight'].default_value=.5;p.inputs['Sheen Roughness'].default_value=.35;p.inputs['Anisotropic'].default_value=.4
rope_mat=material('Natural flax cord',(.39,.27,.115))
flag_mats=[material(n,c,.87) for n,c in [('Saffron flag',(.8,.47,.045)),('Crimson flag',(.48,.025,.037)),('Ivory flag',(.8,.75,.53)),('Meadow flag',(.09,.36,.11)),('Blue flag',(.04,.14,.48))]]
ivory=material('Warm linen stitched trim',(.78,.70,.45),.82)
for m in flag_mats+[ivory,gold]:
    nt=m.node_tree;p=nt.nodes.get('Principled BSDF')
    noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=210;noise.inputs['Detail'].default_value=2
    bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.13;bump.inputs['Distance'].default_value=.0007
    nt.links.new(noise.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs[0],p.inputs['Normal'])
    p.inputs['Sheen Weight'].default_value=.35 if m!=gold else .5

def wind_animation(obj,coords,side,phase):
    obj.shape_key_add(name='Basis')
    for axis,trig in [('Sine',math.sin),('Cosine',math.cos)]:
        key=obj.shape_key_add(name='Wind '+axis);key.slider_min=-1;key.slider_max=1
        for point,(u,v) in zip(key.data,coords):
            theta=u*3.1-v*4.4+phase
            point.co+=side*(.15*v**1.5*trig(theta))+Vector((0,0,.025*v*v*trig(theta+.7)))
        driver=key.driver_add('value').driver
        driver.expression=('cos' if axis=='Sine' else 'sin')+'((frame-1)*6.28318530718/48)'
    obj['wind_note']='48-frame looping cloth flutter; top edge pinned to cord; review animation'

# Styles are independent assets. Pattern is cloth pigment, not floating metal geometry.
style_path=Path(args.config).resolve().parent/cfg['flag_styles_file']
style_catalog=json.loads(style_path.read_text(encoding='utf-8-sig'))['styles']
style_materials={};style_manifest={}
texture_dir=OUT/'flag_styles';texture_dir.mkdir(exist_ok=True)
for style_id,style in style_catalog.items():
    m=flag_mats[0].copy();m.name='REPLACEABLE CLOTH '+style_id
    if style.get('texture_path'):
        texture_path=(style_path.parent/style['texture_path']).resolve()
        im=bpy.data.images.load(str(texture_path))
    else:
        w,h=512,1024;yy,xx=np.mgrid[0:h,0:w];u=(xx+.5)/w;v=(yy+.5)/h
        mask=np.zeros((h,w),dtype=np.float32)
        def stroke(a,b,width=.015):
            # Coordinates: u left to right, v attachment to tip.
            ax,ay=a;bx,by=b;dx=bx-ax;dy=by-ay
            t=np.clip(((u-ax)*dx+(v-ay)*dy)/(dx*dx+dy*dy),0,1)
            distance=np.sqrt((u-ax-t*dx)**2+(v-ay-t*dy)**2)
            np.maximum(mask,np.clip((width-distance)*w+0.5,0,1),out=mask)
        pattern=style['pattern']
        if pattern in ['border','panel']:
            for a,b in [((.055,.035),(.055,.95)),((.945,.035),(.945,.95)),((.055,.95),(.945,.95)),((.055,.035),(.945,.035))]:stroke(a,b,.014)
        if pattern=='panel':stroke((.055,.75),(.945,.75),.018)
        if pattern=='fork':
            for a,b in [((.5,.54),(.5,.91)),((.29,.70),(.32,.80)),((.32,.80),(.5,.91)),((.71,.70),(.68,.80)),((.68,.80),(.5,.91))]:stroke(a,b,.018)
        rgb=np.array(style['base_color'])[None,None,:]*(1-mask[:,:,None])+np.array(style['ink_color'])[None,None,:]*mask[:,:,None]
        pixels=np.ones((h,w,4),dtype=np.float32);pixels[:,:,:3]=rgb
        im=bpy.data.images.new(style_id,width=w,height=h,alpha=True);im.pixels.foreach_set(pixels.ravel())
        im.filepath_raw=str(texture_dir/(style_id+'.png'));im.file_format='PNG';im.save()
    im.pack()
    nt=m.node_tree;tex=nt.nodes.new('ShaderNodeTexImage');tex.name='REPLACE FLAG ARTWORK';tex.image=im
    p=nt.nodes.get('Principled BSDF');p.inputs['Specular IOR Level'].default_value=.18;p.inputs['Sheen Weight'].default_value=.16
    coord=nt.nodes.new('ShaderNodeTexCoord');split=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(coord.outputs['UV'],split.inputs[0])
    waves=[]
    for axis,count in [('X',170),('Y',340)]:
        mul=nt.nodes.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=math.tau*count;nt.links.new(split.outputs[axis],mul.inputs[0])
        wave=nt.nodes.new('ShaderNodeMath');wave.operation='SINE';nt.links.new(mul.outputs[0],wave.inputs[0]);waves.append(wave)
    weave=nt.nodes.new('ShaderNodeMath');weave.operation='MULTIPLY';nt.links.new(waves[0].outputs[0],weave.inputs[0]);nt.links.new(waves[1].outputs[0],weave.inputs[1])
    grain=nt.nodes.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=65;grain.inputs['Roughness'].default_value=.8;nt.links.new(coord.outputs['UV'],grain.inputs['Vector'])
    variation=nt.nodes.new('ShaderNodeMapRange');variation.inputs['To Min'].default_value=.68;variation.inputs['To Max'].default_value=1.05;nt.links.new(grain.outputs['Fac'],variation.inputs['Value'])
    pigment=nt.nodes.new('ShaderNodeMixRGB');pigment.blend_type='MULTIPLY';pigment.inputs[0].default_value=1;nt.links.new(tex.outputs['Color'],pigment.inputs[1]);nt.links.new(variation.outputs[0],pigment.inputs[2]);nt.links.new(pigment.outputs[0],p.inputs['Base Color'])
    rough=nt.nodes.new('ShaderNodeMapRange');rough.inputs['To Min'].default_value=.84;rough.inputs['To Max'].default_value=.98;nt.links.new(grain.outputs['Fac'],rough.inputs['Value']);nt.links.new(rough.outputs[0],p.inputs['Roughness'])
    yarn=nt.nodes.new('ShaderNodeBump');yarn.name='Interlaced warp and weft';yarn.inputs['Strength'].default_value=.48;yarn.inputs['Distance'].default_value=.0012;nt.links.new(weave.outputs[0],yarn.inputs['Height'])
    crumple=nt.nodes.new('ShaderNodeTexNoise');crumple.inputs['Scale'].default_value=17;crumple.inputs['Detail'].default_value=3;nt.links.new(coord.outputs['UV'],crumple.inputs['Vector'])
    bump=nt.nodes.new('ShaderNodeBump');bump.name='Small cloth puckering';bump.inputs['Strength'].default_value=.32;bump.inputs['Distance'].default_value=.008;nt.links.new(crumple.outputs['Fac'],bump.inputs['Height']);nt.links.new(yarn.outputs[0],bump.inputs['Normal']);nt.links.new(bump.outputs[0],p.inputs['Normal'])
    style_materials[style_id]=m;style_manifest[style_id]={'material':m.name,'image':im.name,'pattern':style.get('pattern','custom')}
flag_slots=[]
path=ROOT.parent/'rmmo_runtime/packs/default/assets/materials/wood/solid_timber'
images={}
for key,file in [('color','texture.png'),('normal','normal.png'),('rough','roughness.png')]:
    im=bpy.data.images.load(str(path/file));im.pack()
    if key!='color':im.colorspace_settings.name='Non-Color'
    images[key]=im

def mesh(name,v,f,mat,uvs=None):
    data=bpy.data.meshes.new(name);data.from_pydata(v,[],f);data.update();o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);data.materials.append(mat)
    if uvs:
        layer=data.uv_layers.new(name='SurfaceUV')
        for loop in data.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
    return o

def tube(name,points,r,mat,sides=6):
    vs=[];fs=[]
    for i,point in enumerate(points):
        tangent=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])).normalized()
        u=tangent.cross(Vector((0,0,1)))
        if u.length<.01:u=tangent.cross(Vector((0,1,0)))
        u.normalize();v=tangent.cross(u)
        vs.extend([Vector(point)+r*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides)) for j in range(sides)])
    for i in range(len(points)-1):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    return mesh(name,vs,fs,mat)

def radius(a,z):return R*(1-.065*z/H)*(1+.023*math.sin(5*a)+.012*math.sin(11*a+z))
post_groups=[]
for entry in cfg['posts']:
    start=set(bpy.context.scene.objects);x,y=entry['position'];color=entry['color']
    if len(color)!=3 or any(not 0<=v<=1 for v in color):raise ValueError('Post RGB must be 0..1')
    mat=material('CUSTOM post color - '+entry['id'],color,.74);nt=mat.node_tree;p=nt.nodes.get('Principled BSDF')
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=images['color']
    bw=nt.nodes.new('ShaderNodeRGBToBW');nt.links.new(tex.outputs['Color'],bw.inputs[0])
    ramp=nt.nodes.new('ShaderNodeMapRange');ramp.inputs['From Min'].default_value=0;ramp.inputs['From Max'].default_value=.45;ramp.inputs['To Min'].default_value=.45;ramp.inputs['To Max'].default_value=1.1
    nt.links.new(bw.outputs[0],ramp.inputs['Value'])
    tint=nt.nodes.new('ShaderNodeMixRGB');tint.name='USER POST COLOR';tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1;tint.inputs[1].default_value=(*color,1)
    nt.links.new(ramp.outputs[0],tint.inputs[2]);nt.links.new(tint.outputs[0],p.inputs['Base Color'])
    tn=nt.nodes.new('ShaderNodeTexImage');tn.image=images['normal'];normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.42;nt.links.new(tn.outputs[0],normal.inputs['Color']);nt.links.new(normal.outputs[0],p.inputs['Normal'])
    tr=nt.nodes.new('ShaderNodeTexImage');tr.image=images['rough'];nt.links.new(tr.outputs[0],p.inputs['Roughness'])
    vs=[];fs=[];uv=[];N=48;rows=12
    for row in range(rows+1):
        for j in range(N+1):
            a=j*math.tau/N;z=H*row/rows
            if row==rows:z+=.009*math.sin(a*7)+.005*math.cos(a*11)
            r=radius(a,z);vs.append((x+r*math.cos(a),y+r*math.sin(a),z));uv.append((j/N*math.tau*R/.8,z/2.4))
    for row in range(rows):
        for j in range(N):q=row*(N+1)+j;fs.append((q,q+1,q+N+2,q+N+1))
    fs.extend([tuple(range(N-1,-1,-1)),tuple(rows*(N+1)+j for j in range(N))])
    ob=mesh('Wood post '+entry['id'],vs,fs,mat,uv)
    for poly in ob.data.polygons:poly.use_smooth=len(poly.vertices)==4
    # Hand-wrapped spacing differs on each post; reverse wrap only covers part.
    phase=random.uniform(-1.8,1.8)
    for strand,turns in enumerate([3.65+random.uniform(-.3,.3),-1.15]):
        vs=[];fs=[];uv=[];segments=180
        if strand==0:
            # Full lower turn: its hidden beginning overlaps the outgoing strip.
            angle0=phase+.22*math.sin(phase)
            for j in range(64):
                s=j/64;angle=angle0-math.tau*(1-s)
                for edge in [-1,1]:
                    zz=.12+edge*.021+.012*math.sin(math.tau*s)
                    rr=radius(angle,zz)+.0015+.0035*min(1,s*8)
                    vs.append((x+rr*math.cos(angle),y+rr*math.sin(angle),zz));uv.append((s-1,(edge+1)/2))
        for i in range(segments+1):
            t=i/segments;angle=phase+turns*math.tau*t+.22*math.sin(t*11+phase)
            progress=t+.055*math.sin(t*math.tau)+.025*math.sin(t*math.tau*3)
            z=(.12+(H-.28)*progress) if strand==0 else (H*.52+(H*.43)*progress)
            for side in [-1,1]:
                zz=z+side*.021*(1+.12*math.sin(t*19))
                rr=radius(angle,zz)+.005+strand*.008+.003*math.sin(t*29+side)**2
                vs.append((x+rr*math.cos(angle),y+rr*math.sin(angle),zz));uv.append((t*6,(side+1)/2))
        for i in range(len(vs)//2-1):fs.append((i*2,i*2+1,i*2+3,i*2+2))
        ribbon=mesh('Golden silk crossing '+entry['id'],vs,fs,gold,uv)
        for poly in ribbon.data.polygons:poly.use_smooth=True
        mod=ribbon.modifiers.new('Silk edge thickness','SOLIDIFY');mod.thickness=.0015
    # One upper wrap gives the rope a visible anchored tie point.
    vs=[];fs=[]
    for i in range(65):
        a=i*math.tau/64
        for dz in [-.017,.017]:
            z=H-.17+dz+.045*math.sin(a+phase);r=radius(a,z)+.014;vs.append((x+r*math.cos(a),y+r*math.sin(a),z))
    for i in range(64):fs.append((2*i,2*i+1,2*i+3,2*i+2))
    mesh('Gold silk upper tie '+entry['id'],vs,fs,gold)
    # Small gathered knot and two uneven soft ends, on the viewer-facing side.
    angle=-math.pi/2+.2*math.sin(phase);z0=H-.17+.045*math.sin(angle+phase)
    radial=Vector((math.cos(angle),math.sin(angle),0));tangent=Vector((-math.sin(angle),math.cos(angle),0))
    anchor=Vector((x,y,z0))+radial*(radius(angle,z0)+.019)
    for tail,length in enumerate([.25,.38]):
        vs=[];fs=[]
        for i in range(25):
            t=i/24
            center=anchor+Vector((0,0,-length*t))+tangent*((tail*2-1)*(.012+.08*t))+radial*(.012+.045*math.sin(t*3.4))
            for edge in [-1,1]:vs.append(center+tangent*(edge*.018*math.cos(t*1.8))+radial*(edge*.018*math.sin(t*1.8)))
        for i in range(24):fs.append((2*i,2*i+1,2*i+3,2*i+2))
        ob=mesh('Loose silk tail '+entry['id'],vs,fs,gold)
        for p in ob.data.polygons:p.use_smooth=True
        ob.modifiers.new('Thin silk','SOLIDIFY').thickness=.0015
    vs=[];fs=[]
    for i in range(25):
        a=i*math.tau/24
        for edge in [-1,1]:vs.append(anchor+tangent*(.027*math.cos(a))+radial*(.018+.018*math.sin(a))+Vector((0,0,edge*.022)))
    for i in range(24):fs.append((2*i,2*i+1,2*i+3,2*i+2))
    mesh('Gathered silk knot '+entry['id'],vs,fs,gold)
    col=bpy.data.collections.new('POST_'+entry['id']);bpy.context.scene.collection.children.link(col)
    for o in set(bpy.context.scene.objects)-start:
        for c in list(o.users_collection):c.objects.unlink(o)
        col.objects.link(o)
    col['body_color']=color;post_groups.append(col)

# Nearest-first disjoint pairs avoid a web of crossing strings in the review recipe.
pairs=[]
for i,a in enumerate(cfg['posts']):
    for j,b in enumerate(cfg['posts'][:i]):
        distance=(Vector(a['position'])-Vector(b['position'])).length
        if 1.2<=distance<=float(cfg['connect_distance_m']):pairs.append((distance,j,i))
used=set();links=[]
for distance,i,j in sorted(pairs):
    if i in used or j in used:continue
    used.update([i,j]);a=Vector((*cfg['posts'][i]['position'],H-.17));b=Vector((*cfg['posts'][j]['position'],H-.17));direction=(b-a).normalized();a+=direction*(R+.018);b-=direction*(R+.018)
    def line(t):return a.lerp(b,t)-Vector((0,0,4*cfg['rope_sag_m']*t*(1-t)))
    tube('Suspended flax bunting cord',[line(k/48) for k in range(49)],.012,rope_mat)
    number=max(3,int((b-a).length/.53));available=(b-a).length;flag_width=available/number*cfg.get('flag_fill_ratio',.93)
    side=Vector((-direction.y,direction.x,0))
    for k in range(number):
        centre=(k+.5)/number;length=cfg.get('flag_length_m',1.05)+.10*math.sin(k*1.7+.3)
        def cloth(u,v,offset=0):
            t=centre+(u-.5)*flag_width/available
            # A broad pennant with a pointed tip and relaxed cloth folds.
            drop=length*v+.15*max(0,(v-.78)/.22)*(1-abs(2*u-1))
            wrinkles=.009*math.sin(u*24+v*9+k)*math.sin(v*17+u*5)*min(1,v*8)
            return line(t)+Vector((0,0,-drop))+side*(.03*math.sin(u*math.pi*4+k)*v+.08*math.sin(v*math.pi)*math.sin(k+1)+wrinkles+offset)
        vs=[];fs=[];uv=[];nx=16;ny=24
        for v in range(ny+1):
            for u in range(nx+1):vs.append(cloth(u/nx,v/ny));uv.append((u/nx,v/ny))
        for v in range(ny):
            for u in range(nx):q=v*(nx+1)+u;fs.append((q,q+nx+1,q+nx+2,q+1))
        sequence=cfg['flag_style_sequence'];style_id=sequence[k%len(sequence)]
        o=mesh('Hanging pennant '+str(k+1),vs,fs,style_materials[style_id],uv)
        wind_animation(o,uv,side,k*1.3)
        for p in o.data.polygons:p.use_smooth=True
        so=o.modifiers.new('Cloth thickness','SOLIDIFY');so.thickness=.0014
        slot_id=f"{cfg['posts'][i]['id']}_{cfg['posts'][j]['id']}_{k+1:02d}"
        mount=bpy.data.objects.new('FLAG_SLOT_'+slot_id,None);bpy.context.collection.objects.link(mount)
        mount.location=line(centre);mount.empty_display_size=.06
        o.data.transform(Matrix.Translation(-mount.location),shape_keys=True);o.parent=mount
        o['style_id']=style_id;o['replaceable_part']='cloth';o['uv_contract']='u 0..1 left/right; v 0 top attachment, 1 bottom tip'
        pinned=o.vertex_groups.new(name='PIN_TOP');pinned.add(list(range(nx+1)),1,'REPLACE')
        mount['slot_id']=slot_id;mount['style_id']=style_id;mount['attachment']='top_center'
        flag_slots.append({'slot_id':slot_id,'style_id':style_id,'mount_world':list(mount.location),'width_m':flag_width,'length_m':length+.15,'mesh':o.name,'material_slot':0,'pin_group':'PIN_TOP'})
    links.append({'posts':[cfg['posts'][i]['id'],cfg['posts'][j]['id']],'distance_m':distance,'flags':number})

scene=bpy.context.scene;scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.58,.65,.75,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.008));ground=bpy.context.object;ground.name='REVIEW floor';ground.data.materials.append(material('Studio limestone',(.31,.30,.25)))
for pos,power,size in [((-3,-5,8),1900,5),((4,3,7),1600,4)]:
    bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.size=size;o.rotation_euler=(Vector((0,0,1.5))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(7,-14,8));cam=bpy.context.object;cam.rotation_euler=(Vector((-1,.3,1.5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=8.1;scene.camera=cam
scene.unit_settings.system='METRIC';scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.filepath=str(OUT/'festival_posts_review.png');scene.view_settings.view_transform='AgX'
scene.frame_start=1;scene.frame_end=48;scene.render.fps=24;scene.frame_set(8)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'festival_posts.blend'))
(OUT/'flag_asset_manifest.json').write_text(json.dumps({'schema_version':1,'status':'offline_review_only','uv_contract':'u left/right; v=0 top, v=1 tip; external artwork must follow these UVs','styles':style_manifest,'slots':flag_slots},indent=2),encoding='utf8')
(OUT/'pairing_report.json').write_text(json.dumps({'links':links,'unpaired':[p['id'] for index,p in enumerate(cfg['posts']) if index not in used],'fixed_ribbon_material':gold.name},indent=2),encoding='utf8')
bpy.ops.render.render(write_still=True)
overview_matrix=cam.matrix_world.copy();overview_scale=cam.data.ortho_scale
cam.location=(1,-5,3.4);cam.rotation_euler=(Vector((0,1.8,2.15))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=3.35
scene.render.filepath=str(OUT/'festival_cloth_detail.png');bpy.ops.render.render(write_still=True)
cam.location=(4,-4,1.7);cam.rotation_euler=(Vector((1.7,1.8,.40))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=1.0
scene.render.filepath=str(OUT/'festival_ribbon_detail.png');bpy.ops.render.render(write_still=True)
cam.matrix_world=overview_matrix;cam.data.ortho_scale=overview_scale
scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=800;scene.render.resolution_y=600
scene.render.image_settings.file_format='FFMPEG';scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264'
scene.render.filepath=str(OUT/'festival_posts_wind.mp4')
bpy.ops.render.render(animation=True)
print('FESTIVAL_POSTS_COMPLETE',json.dumps(links))
