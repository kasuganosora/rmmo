"""Apply the owned Quixel boxwood atlas to a separate Blender review candidate."""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'rmmo_runtime/art_sources/town_planters'
OUT=BASE/'boxwood_review'
OUT.mkdir(parents=True,exist_ok=True)
TEX=BASE/'sources/boxwood_rjepadp2'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'town_planters.blend'))
random.seed(10526)

mat=bpy.data.materials.new('Quixel Boxwood rjepadp2 - scanned branches')
mat.use_nodes=True;mat.surface_render_method='DITHERED';mat.use_backface_culling=False
nt=mat.node_tree;nt.nodes.clear()
output=nt.nodes.new('ShaderNodeOutputMaterial')
p=nt.nodes.new('ShaderNodeBsdfPrincipled');p.inputs['Roughness'].default_value=.6
trans=nt.nodes.new('ShaderNodeBsdfTranslucent')
mix=nt.nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=.16
nt.links.new(p.outputs['BSDF'],mix.inputs[1]);nt.links.new(trans.outputs[0],mix.inputs[2])
transparent=nt.nodes.new('ShaderNodeBsdfTransparent')
alpha_mix=nt.nodes.new('ShaderNodeMixShader')
nt.links.new(transparent.outputs[0],alpha_mix.inputs[1]);nt.links.new(mix.outputs[0],alpha_mix.inputs[2]);nt.links.new(alpha_mix.outputs[0],output.inputs['Surface'])
images={}
for channel in ['BaseColor','Opacity','Normal','Roughness','Translucency']:
    image=bpy.data.images.load(str(TEX/('Boxwood_rjepadp2_4K_'+channel+'.jpg')),check_existing=True)
    if channel not in ['BaseColor','Translucency']:image.colorspace_settings.name='Non-Color'
    node=nt.nodes.new('ShaderNodeTexImage');node.image=image;node.label=channel
    images[channel]=node
tone=nt.nodes.new('ShaderNodeHueSaturation');tone.inputs['Value'].default_value=1.85;tone.inputs['Saturation'].default_value=1.12
nt.links.new(images['BaseColor'].outputs['Color'],tone.inputs['Color']);nt.links.new(tone.outputs['Color'],p.inputs['Base Color'])
nt.links.new(images['Roughness'].outputs['Color'],p.inputs['Roughness'])
nt.links.new(images['Translucency'].outputs['Color'],trans.inputs['Color'])
normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.65
nt.links.new(images['Normal'].outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs[0],p.inputs['Normal'])
cut=nt.nodes.new('ShaderNodeMath');cut.operation='GREATER_THAN';cut.inputs[1].default_value=.45
nt.links.new(images['Opacity'].outputs['Color'],cut.inputs[0]);nt.links.new(cut.outputs[0],alpha_mix.inputs[0])

# Isolated branch rectangles measured on the atlas (top-left image coordinates).
# Keep the alpha padding inside each rectangle and avoid adjacent branch silhouettes.
rects=[(.084,.074,.176,.329),(.444,.054,.538,.350),(.574,.085,.673,.342),(.720,.099,.795,.320),(.856,.099,.952,.360),(.077,.380,.166,.575),(.232,.467,.340,.698),(.392,.395,.511,.698),(.540,.381,.679,.723),(.750,.763,.833,.930)]
wood=bpy.data.materials.get('Stem')
stats={}
for col in list(bpy.data.collections):
    if not col.name.startswith(('01_','03_','05_','06_','07_')):continue
    old=next(o for o in col.objects if o.name.startswith('Planting'))
    offset=old.location.copy()
    bpy.data.objects.remove(old,do_unlink=True)
    w=col['length_m'];d=col['depth_m'];corner='arm_width_m' in col
    high=col.name.startswith(('01_','07_'))
    base=(.72 if high else .54)-.07
    if corner:
        arm=col['arm_width_m'];joint=Vector((-w/2+arm/2,-d/2+arm/2))
        segments=[(joint,Vector((w/2-.32,joint.y))),(joint,Vector((joint.x,d/2-.32)))]
    else:segments=[(Vector((-w/2+.32,0)),Vector((w/2-.32,0)))]
    centres=[]
    for k,(a,b) in enumerate(segments):
        count=max(2,math.ceil((b-a).length/.34)+1)
        centres.extend([a.lerp(b,i/(count-1)) for i in range(1 if k else 0,count)])
    verts=[];faces=[];uvs=[]
    stemv=[];stemf=[]
    def stem(a,b,r=.006):
        a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u)
        start=len(stemv)
        for c,rad in [(a,r),(b,r*.45)]:
            stemv.extend([c+rad*(u*math.cos(i*math.tau/5)+v*math.sin(i*math.tau/5)) for i in range(5)])
        for i in range(5):stemf.append((start+i,start+(i+1)%5,start+5+(i+1)%5,start+5+i))
    for centre in centres:
        crown=.90*random.uniform(.9,1.1) if high else .30*random.uniform(.9,1.1)
        for j in range(135 if high else 90):
            az=random.random()*math.tau
            # Randomized whorls fill volume instead of repeated flat crosses.
            radial=math.sqrt(random.random())*.23
            foot=Vector((centre.x+math.cos(az)*radial,centre.y+math.sin(az)*radial,base+.015+random.random()*(crown*.53)))
            a=az+random.uniform(-.7,.7)
            tilt=random.uniform(.25,1.05) if high else random.uniform(.75,1.35)
            axis=Vector((math.cos(a)*math.sin(tilt),math.sin(a)*math.sin(tilt),math.cos(tilt)))
            u=Vector((-math.sin(a),math.cos(a),0));n=u.cross(axis).normalized()
            # Roll each branch plane around its growth axis.
            roll=random.uniform(-1.1,1.1);u=u*math.cos(roll)+n*math.sin(roll);n=u.cross(axis).normalized()
            length=random.uniform(.38,.58) if high else random.uniform(.30,.43)
            x0,y0,x1,y1=random.choice(rects);width=length*(x1-x0)/(y1-y0)
            start=len(verts)
            for row in range(5):
                t=row/4
                for column in range(3):
                    s=column/2
                    co=foot+axis*(t*length)+u*((s-.5)*width)+n*(math.sin(t*math.pi)*length*.07+abs(s-.5)*width*.14)
                    verts.append(co);uvs.append((x0+(x1-x0)*s,1-y1+(y1-y0)*t))
            for row in range(4):
                for column in range(2):
                    q=start+row*3+column;faces.append((q,q+1,q+4,q+3))
            stem((centre.x,centre.y,base-.03),foot,.0018 if high else .0012)
    def obj(name,v,f,m):
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],f);mesh.update()
        o=bpy.data.objects.new(name,mesh);col.objects.link(o);o.location=offset;mesh.materials.append(m);return o
    leaves=obj('Boxwood scanned branch clusters',verts,faces,mat)
    layer=leaves.data.uv_layers.new(name='BoxwoodAtlas')
    for loop in leaves.data.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
    for poly in leaves.data.polygons:poly.use_smooth=True
    obj('Rooted woody stems',stemv,stemf,wood)
    stats[col.name]={'branch_cards':len(faces)//8,'foliage_triangles':len(faces)*2,'stem_triangles':len(stemf)*2}

scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=40
scene.cycles.use_denoising=True;scene.cycles.transparent_max_bounces=64
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
cam=scene.camera;cam.location=(4,-16,9);cam.rotation_euler=(Vector((-.15,-7,.6))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.8
for col in bpy.data.collections:
    if col.name[:2].isdigit():col.hide_render=not col.name.startswith(('06_','07_'))
scene.render.filepath=str(OUT/'boxwood_L_comparison.png')
# Pack native scan maps; the new .blend is independently reviewable.
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_planters_boxwood.blend'))
(OUT/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
bpy.ops.render.render(write_still=True)
# Close view shows actual atlas leaf and branch detail rather than just silhouette.
cam.location=(4.6,-11.5,3.7);cam.rotation_euler=(Vector((2.0,-7.7,1.1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.4
scene.render.resolution_x=1200;scene.render.resolution_y=1000
scene.render.filepath=str(OUT/'boxwood_leaf_detail.png')
bpy.ops.render.render(write_still=True)
print('BOXWOOD_REVIEW_COMPLETE',json.dumps(stats))
