"""New masonry only; original foliage is assembled later without re-export."""
import bpy,bmesh,math,random,json,hashlib,sys,argparse
import numpy as np
from pathlib import Path
P=argparse.ArgumentParser();P.add_argument('--version',default='v1');A=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=Path('D:/code/rmmo_runtime/art_sources/s10_warm_brick_planter_20261017')/A.version;OUT.mkdir(parents=True,exist_ok=True)
LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials');INPUTS={};random.seed(101717)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def material(name,key,strength):
    folder=LIB/key;config=json.loads((folder/'material.json').read_text(encoding='utf-8'));d=config['material'];m=bpy.data.materials.new(name);m.use_nodes=True;m.use_backface_culling=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Roughness'].default_value=1;p.inputs['Metallic'].default_value=0
    record={'config':(folder/'material.json').as_posix(),'config_sha256':sha(folder/'material.json'),'source':config.get('source'),'inputs':{}}
    for field,socket,color in [('texture_path','Base Color',True),('roughness_path','Roughness',False),('normal_path','Normal',False)]:
        file=folder/d[field];im=bpy.data.images.load(str(file),check_existing=False);im.colorspace_settings.name='sRGB' if color else 'Non-Color';record['inputs'][field]={'path':file.as_posix(),'sha256':sha(file)}
        if socket=='Normal' and d.get('normal_format')=='directx':
            converted=im.copy();pixels=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(pixels);pixels[1::4]=1-pixels[1::4];converted.pixels.foreach_set(pixels)
            converted.filepath_raw=str(OUT/(name+'_normal_opengl.png'));converted.file_format='PNG';converted.save();converted.pack();im=converted
            record['normal_conversion']='DirectX to OpenGL green inversion once; source library unchanged'
        im.pack();node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;node.extension='REPEAT'
        if socket=='Normal':
            normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=strength;m.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],p.inputs[socket])
        else:m.node_tree.links.new(node.outputs['Color'],p.inputs[socket])
    INPUTS[name]=record;return m
bpy.ops.wm.read_factory_settings(use_empty=True)
BRICK=material('S10 fired clay brick','walls/natural_red_brick',.72)
SOIL=material('S10 planting earth','terrain/natural_dirt',.55)
MORTAR=bpy.data.materials.new('S10 recessed lime mortar');MORTAR.use_nodes=True;bs=next(n for n in MORTAR.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.27,.26,.235,1);bs.inputs['Roughness'].default_value=.96;bs.inputs['Metallic'].default_value=0
OBJECTS=[]
def box(name,center,size,mat,brick=False,bevel=.002):
    # Inputs Godot +Y up, Blender +Z up. Existing source-node translation retained later.
    x,y,z=center;w,h,dep=size;bpy.ops.mesh.primitive_cube_add(size=1,location=(x,-z,y));o=bpy.context.object;o.name=name;o.scale=(w,dep,h);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Small worn clay edge','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
    uv=o.data.uv_layers.active or o.data.uv_layers.new(name='Metric clay UV');col=random.randrange(4);row=random.randrange(12)
    for face in o.data.polygons:
        n=face.normal;axis=max(range(3),key=lambda k:abs(n[k]));axes=[k for k in range(3) if k!=axis]
        values=[o.data.vertices[o.data.loops[li].vertex_index].co for li in face.loop_indices]
        lo=[min(v[k] for v in values) for k in axes];hi=[max(v[k] for v in values) for k in axes]
        for li in face.loop_indices:
            v=o.data.vertices[o.data.loops[li].vertex_index].co
            a=(v[axes[0]]-lo[0])/max(hi[0]-lo[0],1e-6);b=(v[axes[1]]-lo[1])/max(hi[1]-lo[1],1e-6)
            if brick:
                # Sample an actual individual clay face from the 4x12 source texture.
                # Physical joints are geometry; do not print a second mortar grid over it.
                uv.data[li].uv=((col+(.5 if row%2==0 else 0)+.045+a*.91)/4,(row+.10+b*.80)/12)
            else:uv.data[li].uv=(float((o.matrix_world@v)[axes[0]])/1.5,float((o.matrix_world@v)[axes[1]])/1.5)
    OBJECTS.append(o);return o

W=3.345;D=1.095;TOP=.6581677198410034;BODY=.56;WALL=.19
# Recessed continuous mortar backs keep joints closed and support the planting bed.
for z in [-D/2+.105,D/2-.105]:box('Mortar long bed',(0,BODY/2,z),(W-.054,BODY,WALL-.025),MORTAR,bevel=.001)
for x in [-W/2+.105,W/2-.105]:box('Mortar return',(x,BODY/2,0),(WALL-.025,BODY,D-.40),MORTAR,bevel=.001)
brick_count=0
def course(length,row,fixed,axis):
    global brick_count
    # Alternate half-brick starts; 8mm horizontal/vertical joints.
    start=-length/2;end=length/2;cuts=[start];offset=.12 if row%2 else .24
    cut=start+offset
    while cut<end-.025:cuts.append(cut);cut+=.24
    cuts.append(end)
    for left,right in zip(cuts,cuts[1:]):
        span=right-left-.008;center=(left+right)/2;y=row*.08+.04
        if axis=='x':c=(center,y,fixed);size=(span,.072,WALL)
        else:c=(fixed,y,center);size=(WALL,.072,span)
        box('Hand-sized clay brick',(c),size,BRICK,True,.003);brick_count+=1
for row in range(7):
    # Corner joints alternate which wall owns the corner; no overlapping bricks.
    if row%2==0:
        for z in [-D/2+WALL/2+.018,D/2-WALL/2-.018]:course(W-.036,row,z,'x')
        for x in [-W/2+WALL/2+.018,W/2-WALL/2-.018]:course(D-.036-2*WALL,row,x,'z')
    else:
        for z in [-D/2+WALL/2+.018,D/2-WALL/2-.018]:course(W-.036-2*WALL,row,z,'x')
        for x in [-W/2+WALL/2+.018,W/2-WALL/2-.018]:course(D-.036,row,x,'z')
# Same outer coping envelope as the source; small individual cap units, no massive slabs.
cap_h=TOP-BODY
for z in [-D/2+.1225,D/2-.1225]:
    n=math.ceil(W/.24)
    for k in range(n):box('Clay coping',( -W/2+(k+.5)*W/n,BODY+cap_h/2,z),(W/n-.006,cap_h,.245),BRICK,True,.004)
for x in [-W/2+.1225,W/2-.1225]:
    length=D-.49;n=math.ceil(length/.24)
    for k in range(n):box('Coping return',(x,BODY+cap_h/2,-length/2+(k+.5)*length/n),(.245,cap_h,length/n-.006),BRICK,True,.004)
# Soil below unchanged lowest rooted branch vertices (0.418m).
box('Planting soil',(0,.403,0),(W-.39,.026,D-.39),SOIL,bevel=.001)
bpy.ops.object.select_all(action='DESELECT')
for o in OBJECTS:o.select_set(True)
bpy.context.view_layer.objects.active=OBJECTS[0];bpy.ops.object.join();o=bpy.context.object;o.name='Structure';bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
mod=o.modifiers.new('Explicit triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
master=OUT/'brick_structure_master.blend';target=OUT/'brick_structure.glb';assert not target.exists();bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_extras=True,export_animations=False,export_tangents=True,export_cameras=False,export_lights=False)
spec={'masonry_outer_dimensions_m':[W,TOP,D],'body_course_height_m':.08,'typical_brick_width_m':.24,'mortar_joint_m':.008,'brick_count':brick_count,'soil_top_y':.416,'normal_maps':'OpenGL converted once from owned library DirectX originals','source_inputs':INPUTS,'structure_source_sha256':sha(target),'structure_master':master.as_posix(),'structure_master_sha256':sha(master),'notes':'Supplemental construction matched to warm small-brick reference; dimensions are game design values. Foliage is not present in this part and will be byte-preserved by GLB assembly.'}
(OUT/'masonry_recipe.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('S10_BRICK_PART',brick_count,len(o.data.polygons),sha(target))
