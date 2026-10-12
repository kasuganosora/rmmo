"""U23 tower material pass: portable PBR maps, unchanged approved geometry."""
import argparse,hashlib,json,math,struct,sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from axel_alarm_tower_shaft import install_shooting_slits

P=argparse.ArgumentParser();P.add_argument('--render-only',action='store_true');P.add_argument('--shots',default='tower,crown,horn,site')
A=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=Path('D:/code/rmmo/review_artifacts/alarm_tower_materials_v3_20261011');OUT.mkdir(exist_ok=True)
(OUT/'textures').mkdir(exist_ok=True)
SOURCE=Path('D:/code/rmmo/review_artifacts/axel_guild_materials_20261011/axel_guild_materials_v4.blend')
TARGET=OUT/'guild_and_alarm_tower_materials.blend'
LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials')
bpy.ops.wm.open_mainfile(filepath=str(TARGET if A.render_only else SOURCE))
SC=bpy.context.scene
# Hidden context collections have identity matrix_world until evaluated.
for c in bpy.data.collections:c.hide_viewport=False
bpy.context.view_layer.update()
objects=[o for o in bpy.data.objects if o.get('semantic_group')=='70_Alarm_Tower_Context']
meshes=[o for o in objects if o.type=='MESH']
M={};SPECS={}

def fingerprint(exclude_shaft=False):
    h=hashlib.sha256()
    for o in sorted(bpy.data.objects,key=lambda o:o.name):
        if exclude_shaft and o.name=='Alarm tower context shaft':continue
        h.update(repr((o.name,o.parent.name if o.parent else '',[[round(v,5) for v in r] for r in o.matrix_world])).encode())
        if o.type=='MESH':
            h.update(repr([tuple(v.co) for v in o.data.vertices]).encode());h.update(repr([tuple(p.vertices) for p in o.data.polygons]).encode())
    return h.hexdigest()

def mat(key,color,rough,metal=0):
    m=bpy.data.materials.new('Alarm PBR | '+key);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    M[key]=m;SPECS[key]={'color':color,'roughness':rough,'metallic':metal}
    return m,p

def texture(m,path,socket,color=False,strength=.3):
    im=bpy.data.images.load(str(path),check_existing=True);im.colorspace_settings.name='sRGB' if color else 'Non-Color';im.pack()
    n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=im;n.extension='REPEAT'
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    if socket=='Normal':
        normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=strength
        m.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
    else:m.node_tree.links.new(n.outputs['Color'],p.inputs[socket])

def save_map(name,rgb,color=False):
    if rgb.ndim==2:rgb=np.repeat(rgb[:,:,None],3,axis=2)
    h,w,_=rgb.shape;im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    im.colorspace_settings.name='sRGB' if color else 'Non-Color'
    rgba=np.ones((h,w,4),dtype=np.float32);rgba[:,:,:3]=np.clip(rgb,0,1)
    im.pixels.foreach_set(rgba.ravel());im.file_format='PNG';im.filepath_raw=str(OUT/'textures'/(name+'.png'));im.save()
    return Path(im.filepath_raw)

def make_materials():
    m,p=mat('warm small masonry',(1,.98,.91),.84)
    folder=LIB/'walls/stone_tiles_facade'
    for file,socket,color in [('normal.png','Normal',False),('roughness.png','Roughness',False)]:texture(m,folder/file,socket,color,.35)
    scan=bpy.data.images.load(str(folder/'texture.jpg'));w,h=scan.size
    pixels=np.empty(w*h*4,dtype=np.float32);scan.pixels.foreach_get(pixels)
    limestone=pixels.reshape(h,w,4)[:,:,:3]*.72+np.array([.66,.59,.46])[None,None,:]*.28
    texture(m,save_map('masonry_limestone_color',limestone,True),'Base Color',True)
    SPECS['warm small masonry']['source']=str(folder/'material.json')
    # Tile scale is reduced to match U23's fine masonry courses.
    SPECS['warm small masonry']['tile_m']=1.65
    SPECS['warm small masonry']['color_adjustment']='72% scan + 28% pale limestone tint, baked as separate portable map; source unchanged'
    m,p=mat('red brick roof',(1,1,1),.86,0)
    brick=LIB/'walls/natural_red_brick'
    texture(m,brick/'texture.png','Base Color',True)
    texture(m,brick/'roughness.png','Roughness')
    normal=bpy.data.images.load(str(brick/'normal.png'));normal.colorspace_settings.name='Non-Color'
    w,h=normal.size;px=np.empty(w*h*4,dtype=np.float32);normal.pixels.foreach_get(px)
    rgb=px.reshape(h,w,4)[:,:,:3].copy();rgb[:,:,1]=1-rgb[:,:,1]
    texture(m,save_map('red_brick_normal_opengl',rgb),'Normal',False,.4)
    SPECS['red brick roof'].update({'source':str(brick/'material.json'),'normal_conversion':'DirectX to OpenGL, invert G once; original unchanged','tile_m':1.5})
    rng=np.random.default_rng(231011);n=1024;y,x=np.mgrid[0:n,0:n]/n
    broad=(np.sin(2*math.pi*(x*3+y*2))+.5*np.sin(2*math.pi*(x*7-y*4)))/1.5
    fine=rng.normal(0,1,(n,n))
    for key,color,rough,metal,amp in [
        ('aged golden brass',(.72,.50,.155),.38,.93,.045),
        ('brass horn interior',(.62,.405,.11),.42,.92,.045),
        ('brass edges',(.78,.55,.19),.32,.94,.025),
        ('dark brass fixings',(.25,.20,.105),.50,.85,.045),
        ]:
        m,p=mat(key,color,rough,metal)
        variation=broad*amp+fine*.007
        height=fine*.00003
        rgb=np.array(color)[None,None,:]*(1+variation[:,:,None])
        colorpath=save_map(key.replace(' ','_')+'_color',rgb,True)
        roughpath=save_map(key.replace(' ','_')+'_roughness',rough+broad*.035+fine*.009)
        gy,gx=np.gradient(height,1/n,1/n);norm=np.stack([-gx,-gy,np.ones_like(gx)],axis=2);norm/=np.linalg.norm(norm,axis=2,keepdims=True)
        normalpath=save_map(key.replace(' ','_')+'_normal',norm*.5+.5)
        for path,socket,iscolor in [(colorpath,'Base Color',True),(roughpath,'Roughness',False),(normalpath,'Normal',False)]:texture(m,path,socket,iscolor,.25)
        SPECS[key]['maps']='textures/'+key.replace(' ','_')+'_{color,roughness,normal}.png'
        SPECS[key]['source']='Project-authored technical PBR variation; U23 palette, no geometry displacement'

def role(o):
    n=o.name.lower()
    if 'shaft' in n or 'hollow masonry drum' in n:return 'warm small masonry'
    if any(s in n for s in ['stone lip','window reveal','arched corbels','scalloped arcade','top cornice']):return 'warm small masonry'
    if 'conical roof shell' in n or 'pitched cheeks' in n:return 'red brick roof'
    if any(s in n for s in ['rolled lip','split collar','finial']):return 'brass edges'
    if 'bolt' in n or 'anchor plate' in n:return 'dark brass fixings'
    return 'aged golden brass'

def unwrap(o,key):
    me=o.data;uv=me.uv_layers.active or me.uv_layers.new(name='AlarmUV')
    world=[o.matrix_world@v.co for v in me.vertices]
    cylindrical=key=='warm small masonry' and not any(s in o.name.lower() for s in ('window reveal','stone lip'))
    cone='conical roof shell' in o.name.lower()
    horn=bool(o.get('open_bore'))
    for p in me.polygons:
        vals=[]
        # Horizontal ledges and radial corbel sides need nondegenerate stone UVs.
        normal=(o.matrix_world.to_3x3().inverted().transposed()@p.normal).normalized()
        centre=o.matrix_world@p.center
        radial=Vector((centre.x-23,centre.y-42,0)).normalized()
        stone_horizontal=cylindrical and abs(normal.z)>.7
        stone_radial_side=cylindrical and not stone_horizontal and abs(normal.dot(radial))<.35
        curved=cylindrical and not stone_horizontal and not stone_radial_side
        for li in p.loop_indices:
            i=me.loops[li].vertex_index;v=world[i];local=me.vertices[i].co
            if horn:
                count=len(me.vertices)//2;ring=(i%count)//48;j=i%48
                u=j/48;vv=ring/(count/48-1)*4
            elif stone_horizontal:
                u=(v.x-23)/1.65;vv=(v.y-42)/1.65
            elif stone_radial_side:
                u=math.hypot(v.x-23,v.y-42)/1.65;vv=v.z/1.65
            elif curved or cone:
                dx,dy=v.x-23,v.y-42;u=math.atan2(dy,dx)/(2*math.pi)
                vv=(v.z-27.62)*1.26/1.5 if cone else v.z/1.65
            else:
                axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
                u=local[axes[0]];vv=local[axes[1]]
                if key=='warm small masonry':u/=1.65;vv/=1.65
            vals.append([li,u,vv])
        if curved or cone or horn:
            if max(v[1] for v in vals)-min(v[1] for v in vals)>.5:
                for v in vals:
                    if v[1]<0 if not horn else v[1]<.5:v[1]+=1
            repeats=15 if cone else 1 if horn else 10 if 'shaft' in o.name.lower() else 13
        else:repeats=1
        for li,u,v in vals:uv.data[li].uv=(u*repeats,v)
        if horn and all(i>=len(me.vertices)//2 for i in p.vertices):p.material_index=1

def export(path,selected):
    bpy.ops.object.select_all(action='DESELECT')
    for o in selected:o.hide_set(False);o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)

if not A.render_only:
    other_before=fingerprint(exclude_shaft=True)
    slit_review=install_shooting_slits(bpy.data.objects['Alarm tower context shaft'])
    assert other_before==fingerprint(exclude_shaft=True)
    slit_review['other_objects_unchanged']=True
    (OUT/'shooting_slit_review.json').write_text(json.dumps(slit_review,indent=2),encoding='utf8')
    before=fingerprint();make_materials();seen=set();assigned=[]
    for o in meshes:
        key=role(o);o['material_pass']='alarm_tower_v3';o['material_role']=key
        if o.data.as_pointer() not in seen:
            seen.add(o.data.as_pointer());o.data.materials.clear();o.data.materials.append(M[key])
            if o.get('open_bore'):o.data.materials.append(M['brass horn interior'])
            for p in o.data.polygons:p.material_index=0
            unwrap(o,key)
        assigned.append({'object':o.name,'role':key})
    assert before==fingerprint()
    for im in bpy.data.images:
        if im.source=='FILE' and im.has_data:im.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),compress=True)
    for c in bpy.data.collections:c.hide_viewport=False
    top=[o for o in objects if o.parent and o.parent.get('semantic_group')=='70_Alarm_Tower_Context' and not o.parent.get('asset_id')]
    saved={o:(o.location.copy(),o.rotation_euler.copy(),o.scale.copy()) for o in top}
    for o in top:o.location-=Vector((23,42,0))
    bpy.context.view_layer.update()
    export(OUT/'guild_alarm_tower.glb',objects)
    # Standalone editable collection, preserving separate horn and roof roots.
    bpy.data.libraries.write(str(OUT/'guild_alarm_tower.blend'),set(objects),fake_user=True,compress=True)
    for o,(loc,rotation,scale) in saved.items():o.location=loc;o.rotation_euler=rotation;o.scale=scale
    bpy.context.view_layer.update()
    roots=[o for o in objects if o.get('asset_id') and o.type=='EMPTY']
    for asset in ['guild_alarm_crown','guild_alarm_conical_roof','guild_alarm_ring_supports','guild_alarm_horn']:
        r=next(o for o in roots if o.get('asset_id')==asset)
        parent=r.parent;pose=(r.location.copy(),r.rotation_euler.copy(),r.scale.copy());r.parent=None;r.matrix_basis.identity();bpy.context.view_layer.update()
        export(OUT/(asset+'.glb'),[r]+list(r.children_recursive))
        r.parent=parent;r.location,r.rotation_euler,r.scale=pose;bpy.context.view_layer.update()
    assert before==fingerprint()
    report={'source':str(SOURCE),'geometry_unchanged':False,'geometry_change':'Shaft hollowed and 16 splayed shooting slits added; other objects unchanged; material/export stages preserve geometry.',
            'geometry_fingerprint':before,'assigned_meshes':len(meshes),
            'unique_meshes':len(seen),'assignments':assigned,'materials':SPECS,
            'glb_sha256':hashlib.sha256((OUT/'guild_alarm_tower.glb').read_bytes()).hexdigest(),
            'user_map_modified':False,'published_to_editor':False,
            'design_notes':['User confirmed red brick roof, stone brick shaft/crown, and golden-yellow brass horns; overrides the earlier copper-roof interpretation.',
                            'User correction: all lower architectural surfaces including cornices, arcades, corbels and reveals use stone brick, with no smooth plaster-like trim.',
                            'Shaft now has 16 real splayed shooting slits; interior void only, no entrance, stair or traversal completion claimed.']}
    (OUT/'material_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print('ALARM_MATERIALS_EXPORTED',len(meshes),flush=True)

# Same geometry and neutral daylight; character/context visibility is preview-only.
SC.render.engine='CYCLES';SC.cycles.samples=32;SC.cycles.use_denoising=True
SC.render.resolution_x=1400;SC.render.resolution_y=1100;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG';SC.view_settings.view_transform='AgX'
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA':o.hide_render=True
SC.world.use_nodes=True
bg=next(n for n in SC.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.65,.72,.84,1);bg.inputs[1].default_value=.65
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='SUN':o.data.energy=2.0;o.rotation_euler=(.5,-.45,-.5)
shots={'tower':((54,7,26),(23,42,16.5),47),'crown':((37,24,32),(23,42,27.3),16.5),
       'stone_detail':((32,29,24.5),(23,42,23.8),8),
       'slit_detail':((30,33,12),(23,42,10),7),
       'shaft':((42,17,19),(23,42,12),27),
       'horn':((33,36,28),(27.8,42,25.9),5),'site':((67,-63,51),(17,22,12),70)}
for name in A.shots.split(','):
    if name not in shots:continue
    for c in bpy.data.collections:c.hide_render=not c.name.startswith(('70_','90_')) if name!='site' else c.name.startswith(('60_','71_','80_'))
    eye,aim,size=shots[name];cam=SC.camera;cam.location=eye;cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=size
    SC.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
    print('ALARM_RENDERED',name,flush=True)
