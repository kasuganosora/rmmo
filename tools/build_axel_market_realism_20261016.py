"""Author revised market merchandise and textile surfaces without touching originals.

Run Blender in background, CPU Cycles only. Output is a versioned delta; the
separate GLB assembler retains the original structural mesh bytes/materials.
"""
import argparse, hashlib, importlib, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path('D:/code/rmmo')
RUNTIME = ROOT.parent/'rmmo_runtime'
ART = RUNTIME/'art_sources/axel_market_realism_20261016'
MASTER = RUNTIME/'art_sources/town_market_stalls/town_market_stalls.blend'
COLLECTIONS = {'pottery':'02_plum_vendor','potion':'03_potion_vendor',
               'scroll':'04_scroll_vendor','ore':'05_ore_vendor'}
sys.path.insert(0, str(ROOT/'tools'))

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.hide_set(False);o.hide_viewport=False;o.hide_render=False;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]

def math_node(nt, op, a, b=None):
    n=nt.nodes.new('ShaderNodeMath');n.operation=op
    for idx,v in enumerate([a,b]):
        if v is None:continue
        if isinstance(v,(float,int)):n.inputs[idx].default_value=v
        else:nt.links.new(v,n.inputs[idx])
    return n.outputs[0]

def linen_material(name, color, span):
    m=bpy.data.materials.new(name);m.use_nodes=True
    nt=m.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Metallic'].default_value=0
    p.inputs['Specular IOR Level'].default_value=.22
    uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='SourceUV'
    scale=nt.nodes.new('ShaderNodeVectorMath');scale.operation='MULTIPLY'
    nt.links.new(uv.outputs[0],scale.inputs[0]);scale.inputs[1].default_value=(*span,1)
    sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(scale.outputs[0],sep.inputs[0])
    # Broad dyed fibres plus subdued warp/weft relief. Pitch in metres.
    warp=math_node(nt,'SINE',math_node(nt,'MULTIPLY',sep.outputs['X'],math.tau/.006))
    weft=math_node(nt,'SINE',math_node(nt,'MULTIPLY',sep.outputs['Y'],math.tau/.0068))
    weave=math_node(nt,'MULTIPLY',warp,weft)
    grain=nt.nodes.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=180
    grain.inputs['Detail'].default_value=2;grain.inputs['Roughness'].default_value=.65
    nt.links.new(scale.outputs[0],grain.inputs['Vector'])
    broad=nt.nodes.new('ShaderNodeTexNoise');broad.inputs['Scale'].default_value=5.5
    broad.inputs['Detail'].default_value=2;nt.links.new(scale.outputs[0],broad.inputs['Vector'])
    micro=math_node(nt,'ADD',math_node(nt,'MULTIPLY',weave,.27),math_node(nt,'MULTIPLY',grain.outputs['Fac'],.35))
    bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.55
    bump.inputs['Distance'].default_value=.00075;nt.links.new(micro,bump.inputs['Height'])
    nt.links.new(bump.outputs[0],p.inputs['Normal'])
    variation=math_node(nt,'ADD',.68,math_node(nt,'MULTIPLY',broad.outputs['Fac'],.20))
    variation=math_node(nt,'ADD',variation,math_node(nt,'MULTIPLY',grain.outputs['Fac'],.12))
    mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
    mix.inputs[1].default_value=(*color,1);nt.links.new(variation,mix.inputs[2]);nt.links.new(mix.outputs[0],p.inputs['Base Color'])
    rough=math_node(nt,'ADD',.76,math_node(nt,'MULTIPLY',grain.outputs['Fac'],.16))
    nt.links.new(rough,p.inputs['Roughness'])
    return m

def cloth_displacement(world, offset):
    x,y,z=world;x-=offset
    if abs(x)>1.503 or abs(y)>.8875:
        return Vector((0,0,0))
    top=2.48+.34*((y+.85)/1.7)+.022
    # Fixed top edges and corners retain the original outside footprint.
    u=max(0,min(1,(x+1.48)/2.96));v=max(0,min(1,(y+.85)/1.7))
    if abs(z-top)<.075 and -.8501<y<.8501 and -1.4801<x<1.4801:
        mask=math.sin(math.pi*u)*math.sin(math.pi*v)
        return Vector((0,0,mask*(.016*math.sin(u*math.pi*8+v*1.5)+.008*math.sin(u*math.pi*17-v*3)-.018)))
    # Valance and sewn binding deform together. Keep the supported top fixed.
    drop=max(0,min(1,(top-z)/.34))
    if drop>.04 and (abs(y)>.83 or abs(x)>1.43):
        n=Vector((0,-1 if y<0 else 1,0)) if abs(y)>.83 else Vector((-1 if x<0 else 1,0,0))
        axis=x if abs(y)>.83 else y
        # Inward only: no extension of the old catalogue bounds.
        return n*(-.010*math.sin(axis*15.2+1.1)**2*drop)+Vector((0,0,.003*math.sin(axis*21)*drop))
    return Vector((0,0,0))

def prepare_cloth(collection,offset,variant):
    count=0
    for o in collection.all_objects:
        if o.type!='MESH':continue
        is_roof=o.name.startswith('Replaceable sloping canvas roof')
        is_valance=o.name.startswith('Cloth scalloped valance')
        is_trim=o.name.startswith('Sewn ochre binding')
        if not (is_roof or is_valance or is_trim):continue
        o.data=o.data.copy()
        for vert in o.data.vertices:
            w=o.matrix_world@vert.co;vert.co+=o.matrix_world.to_3x3().inverted()@cloth_displacement(w,offset)
        o.data.update()
        # Every original panel retains its own authored UVs before the bake.
        if not o.data.uv_layers:o.data.uv_layers.new(name='SourceUV')
        o.data.uv_layers.active.name='SourceUV'
        span=(2.96,1.73) if is_roof else ((.25,.34) if is_valance else (1,1))
        col=variant['trim_color'] if is_trim else variant['canopy_color']
        # Preserve hue while reducing the previous very pale uniform response.
        col=tuple(float(c)*(.44 if is_trim else .66) for c in col)
        o.data.materials.clear();o.data.materials.append(linen_material('Woven linen '+o.name,col,span))
        o['rmmo_export_group']='CanopyTrim' if is_trim else 'CanopyCloth'
        for f in o.data.polygons:f.use_smooth=True
        count+=1
    return count

def evaluated_copy(o,deps,pivot):
    data=bpy.data.meshes.new_from_object(o.evaluated_get(deps),depsgraph=deps)
    n=bpy.data.objects.new(o.name+'_runtime',data);bpy.context.scene.collection.objects.link(n)
    # Bake in the original world/object coordinates, then move only final meshes.
    n.matrix_world=o.matrix_world.copy()
    for key in o.keys():
        if key!='_RNA_UI':n[key]=o[key]
    if o.get('rmmo_export_group','').startswith(('Glass','Liquid','Crystal')):
        return n  # Exact material names are part of the runtime optical contract.
    # Freeze object-space procedural coordinates before merging the bake group.
    for slot in n.material_slots:
        if not slot.material:continue
        slot.material=slot.material.copy();m=slot.material
        if not m.use_nodes:continue
        for node in list(m.node_tree.nodes):
            if node.type=='TEX_COORD' and node.object is None:node.object=o
    return n

def bake_group(parts,name,out,size,asset):
    select(parts);bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    if not o.data.uv_layers:o.data.uv_layers.new(name='SourceUV')
    if not o.data.uv_layers.get('SourceUV'):
        original=o.data.uv_layers.active
        layer=o.data.uv_layers.new(name='SourceUV',do_init=True)
        o.data.uv_layers.active=original
    mats=[]
    for slot in o.material_slots:
        if not slot.material:continue
        m=slot.material;m.use_nodes=True;mats.append(m)
        uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='SourceUV'
        for node in list(m.node_tree.nodes):
            if node.type=='TEX_IMAGE' and not node.inputs['Vector'].is_linked:m.node_tree.links.new(uv.outputs[0],node.inputs['Vector'])
            elif node.type=='TEX_COORD':
                for link in list(node.outputs['UV'].links):m.node_tree.links.new(uv.outputs[0],link.to_socket)
    o.data.uv_layers.new(name='GameAtlas');o.data.uv_layers.active_index=len(o.data.uv_layers)-1
    o.data.uv_layers.active.active_render=True
    narrow_rolls=(asset=='scroll' and name=='GoodsOpaque')
    bpy.context.scene.render.bake.margin=4 if narrow_rolls else 12
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(72),island_margin=.003 if narrow_rolls else .006)
    bpy.ops.object.mode_set(mode='OBJECT')
    targets=[]
    for m in mats:
        node=m.node_tree.nodes.new('ShaderNodeTexImage');m.node_tree.nodes.active=node;targets.append(node)
    baked={};scene=bpy.context.scene
    for kind in ['DIFFUSE','NORMAL','ROUGHNESS','METALLIC']:
        image=bpy.data.images.new(name+'_'+kind,size,size,alpha=False)
        if kind!='DIFFUSE':image.colorspace_settings.name='Non-Color'
        for node in targets:node.image=image
        backups=[]
        if kind=='METALLIC':
            for m in mats:
                nt=m.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');outnode=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
                links=[(l.from_socket,l.to_socket) for l in outnode.inputs['Surface'].links]
                emit=nt.nodes.new('ShaderNodeEmission');src=p.inputs['Metallic']
                if src.is_linked:nt.links.new(src.links[0].from_socket,emit.inputs['Color'])
                else:emit.inputs['Color'].default_value=(src.default_value,)*3+(1,)
                nt.links.new(emit.outputs[0],outnode.inputs['Surface']);backups.append((nt,emit,links))
        print('BAKE',name,kind,flush=True)
        bpy.ops.object.bake(type='EMIT' if kind=='METALLIC' else kind,pass_filter={'COLOR'} if kind=='DIFFUSE' else set(),use_clear=True)
        for nt,emit,links in backups:
            nt.nodes.remove(emit)
            for a,b in links:nt.links.new(a,b)
        image.filepath_raw=str(out/(name+'_'+kind+'.png'));image.file_format='PNG';image.save();image.pack();baked[kind]=image
    # Technical channel packing, no resampling or colour grading.
    rgba=np.ones((size*size,4),dtype=np.float32)
    rough=np.empty(size*size*4,dtype=np.float32);baked['ROUGHNESS'].pixels.foreach_get(rough)
    metal=np.empty(size*size*4,dtype=np.float32);baked['METALLIC'].pixels.foreach_get(metal)
    rgba[:,1]=rough.reshape(-1,4)[:,0];rgba[:,2]=metal.reshape(-1,4)[:,0]
    orm=bpy.data.images.new(name+'_ORM',size,size,alpha=False);orm.colorspace_settings.name='Non-Color'
    orm.pixels.foreach_set(rgba.ravel());orm.filepath_raw=str(out/(name+'_ORM.png'));orm.file_format='PNG';orm.save();orm.pack()
    m=bpy.data.materials.new(name+'_PBR');m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');nt=m.node_tree
    for kind in ['DIFFUSE','NORMAL']:
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=baked[kind]
        if kind=='NORMAL':
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=1
            nt.links.new(tex.outputs[0],n.inputs['Color']);nt.links.new(n.outputs[0],p.inputs['Normal'])
        else:nt.links.new(tex.outputs[0],p.inputs['Base Color'])
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=orm
    sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(tex.outputs[0],sep.inputs[0])
    nt.links.new(sep.outputs['Green'],p.inputs['Roughness']);nt.links.new(sep.outputs['Blue'],p.inputs['Metallic'])
    if name.startswith('Canopy') or (name in ('GoodsOpaque','PaperSheet') and asset=='scroll'):p.inputs['Specular IOR Level'].default_value=.22
    elif name=='GoodsOpaque' and asset=='pottery':p.inputs['Specular IOR Level'].default_value=.38
    o.data.materials.clear();o.data.materials.append(m)
    for f in o.data.polygons:f.material_index=0
    # RNA layer references shift after remove; re-fetch every deletion.
    while len(o.data.uv_layers)>1:
        uv=next(layer for layer in o.data.uv_layers if layer.name!='GameAtlas')
        o.data.uv_layers.remove(uv)
    assert len(o.data.uv_layers)==1 and o.data.uv_layers[0].name=='GameAtlas'
    o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
    return o

def run():
    parser=argparse.ArgumentParser();parser.add_argument('--asset',choices=COLLECTIONS,required=True)
    parser.add_argument('--version',default='v1');parser.add_argument('--common-only',action='store_true');parser.add_argument('--goods-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);asset=args.asset
    out=ART/args.version/asset;out.mkdir(parents=True,exist_ok=True)
    assert out.resolve().is_relative_to(ART.resolve()) and not (out/'delta.glb').exists()
    bpy.ops.wm.open_mainfile(filepath=str(MASTER))
    for c in bpy.data.collections:c.hide_viewport=False;c.hide_render=False
    collection=bpy.data.collections[COLLECTIONS[asset]]
    cfg=json.loads((ROOT/'tools/town_market_stalls_parameters.json').read_text(encoding='utf-8-sig'))
    variant=next(v for v in cfg['variants'] if v['id']==COLLECTIONS[asset])
    old=json.loads((RUNTIME/'assets/town_props_20261006/manifest.json').read_text())
    pivot=Vector(next(r['source_pivot'] for r in old if r['id']=='town_market_stalls_'+COLLECTIONS[asset]))
    offset=(next(i for i,v in enumerate(cfg['variants']) if v['id']==COLLECTIONS[asset])-2)*3.6
    notes={}
    notes['wood']=importlib.import_module('axel_market_realism_wood').apply(collection)
    if not args.common_only:
        mod=importlib.import_module('axel_market_realism_pottery_scroll' if asset in ('pottery','scroll') else 'axel_market_realism_potion_ore')
        notes['goods']=mod.apply(asset,collection)
    if not args.goods_only:notes['cloth_objects']=prepare_cloth(collection,offset,variant)
    contents=bpy.data.collections[COLLECTIONS[asset]+'_CONTENTS']
    desired=[]
    for o in collection.all_objects:
        if o.type not in ('MESH','CURVE'):continue
        cloth=o.get('rmmo_export_group','').startswith('Canopy')
        structure=o.get('rmmo_export_group','')=='Structure'
        goods=o in set(contents.all_objects)
        if ((cloth or structure) and not args.goods_only) or (goods and not args.common_only):desired.append(o)
    for o in list(bpy.context.scene.objects):
        if o not in set(collection.all_objects):bpy.data.objects.remove(o,do_unlink=True)
    # Save unbaked editable parent with all original structure retained.
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring.blend'))
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
    scene.render.threads_mode='FIXED';scene.render.threads=6;scene.render.bake.margin=12
    scene.frame_set(1);deps=bpy.context.evaluated_depsgraph_get();groups={}
    for o in desired:
        n=evaluated_copy(o,deps,pivot);group=o.get('rmmo_export_group','GoodsOpaque')
        groups.setdefault(group,[]).append(n)
    for o in desired:o.hide_render=True;o.hide_set(True)
    outputs=[];group_report=[]
    for group,parts in groups.items():
        if group.startswith(('Glass','Liquid','Crystal')):
            # Consolidate explicit per-material optics from each authored member.
            specs={}
            for part in parts:
                raw=part.get('rmmo_tinted_glass')
                if raw:specs.update(raw.to_dict()['materials'])
            select(parts);bpy.ops.object.join();o=bpy.context.object;o.name=group
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
            if specs:o['rmmo_tinted_glass']={'version':1,'materials':specs}
        else:o=bake_group(parts,group,out,1024 if group in ('CanopyTrim','PaperSheet') else 2048,asset)
        outputs.append(o);o.data.calc_loop_triangles();group_report.append({'group':group,'triangles':len(o.data.loop_triangles),'materials':[m.name for m in o.data.materials]})
    for o in outputs:o.location-=pivot
    select(outputs)
    bpy.ops.export_scene.gltf(filepath=str(out/'delta.glb'),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_tangents=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'runtime_baked.blend'))
    (out/'build.json').write_text(json.dumps({'asset':asset,'master':str(MASTER),'master_sha256':sha(MASTER),'source_pivot':list(pivot),'groups':group_report,'notes':notes,'delta_sha256':sha(out/'delta.glb'),'cpu_bake':True},ensure_ascii=False,indent=2),encoding='utf-8')
    print('MARKET_REALISM_BUILT',asset,flush=True)

if __name__=='__main__':run()
