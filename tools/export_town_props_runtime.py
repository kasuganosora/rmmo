"""Bake Blender-only surfaces and export isolated, named game assets. Originals untouched."""
import bpy,json,math,re,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');ART=ROOT/'art_sources';OUT=ROOT/'assets/town_props_20261006';OUT.mkdir(parents=True,exist_ok=True)
inventory=json.loads((ART/'town_prop_source_inventory.json').read_text())
only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
reports=json.loads((OUT/'manifest.json').read_text()) if only and (OUT/'manifest.json').exists() else []
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.hide_set(False);o.hide_viewport=False;o.hide_render=False;o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
def export(file,key,objects):
    if only and key not in only:return
    # Discard presentation, retain each asset's independent component groups.
    for c in bpy.data.collections:c.hide_viewport=False;c.hide_render=False
    objects=[o for o in objects if o.type in {'MESH','CURVE'} and not o.name.startswith(('Review','REVIEW'))]
    if not objects:return
    select(objects)
    # Real evaluated geometry, no drivers or animation baked into a fixed pose.
    for o in objects:
        if o.data and getattr(o.data,'shape_keys',None):
            for k in o.data.shape_keys.key_blocks:k.value=0
    bpy.context.scene.frame_set(1)
    deps=bpy.context.evaluated_depsgraph_get();copies=[]
    for o in objects:
        mesh=bpy.data.meshes.new_from_object(o.evaluated_get(deps),depsgraph=deps)
        n=bpy.data.objects.new(o.name+'_runtime',mesh);bpy.context.scene.collection.objects.link(n);n.matrix_world=o.matrix_world.copy()
        copies.append(n)
    for o in list(bpy.context.scene.objects):
        if o not in copies:bpy.data.objects.remove(o,do_unlink=True)
    bounds=[o.matrix_world@Vector(p) for o in copies for p in o.bound_box]
    pivot=Vector(((min(p.x for p in bounds)+max(p.x for p in bounds))/2,(min(p.y for p in bounds)+max(p.y for p in bounds))/2,min(p.z for p in bounds)))
    for o in copies:o.location-=pivot
    groups={}
    for o in copies:
        name=o.name.lower()
        leaf=any(t in name for t in ['scanned','tall crown'])
        cloth='hanging pennant' in name or 'laundry cloth' in name
        goods=any(t in name for t in ['replaceable','mineral','bottle','scroll','parchment','shelf','sorting bin','manuscript'])
        mats=[m for m in o.data.materials if m and m.use_nodes]
        transmission=any(m.node_tree.nodes.get('Principled BSDF') and m.node_tree.nodes.get('Principled BSDF').inputs['Transmission Weight'].default_value>.01 for m in mats)
        metal=any(m.node_tree.nodes.get('Principled BSDF') and m.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value>.5 for m in mats)
        group=('CandleWarm' if 'night flame' in name else 'Foliage' if leaf else o.name if cloth else 'Glass' if transmission else 'GoodsMetal' if goods and metal else 'Goods' if goods else 'Metal' if metal else 'Structure')
        if name.startswith('wood post '):group='PostBody'
        elif any('golden yellow silk' in m.name.lower() for m in mats):group='GoldSilk'
        elif any(m.node_tree.nodes.get('USER CLOTH COLOR') for m in mats):
            group='CanopyTrim' if any('trim' in m.name.lower() for m in mats) else 'CanopyCloth'
        groups.setdefault(group,[]).append(o)
    output=[];detail=[]
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=4;scene.render.bake.margin=8
    for group,parts in groups.items():
        select(parts);bpy.ops.object.join();o=bpy.context.object;o.name=re.sub(r'[^A-Za-z0-9_]','_',group)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        if group=='Foliage':
            o['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.08,'stiffness':.8,'anchor':'bottom','shelter':True}
        elif 'hanging_pennant' in o.name.lower() or 'laundry_cloth' in o.name.lower():
            o['rmmo_wind']={'profile':'cloth','mesh':'*','amplitude':.18,'stiffness':.35,'anchor':'top','shelter':True}
        if group=='CandleWarm':
            o['rmmo_small_wall_lantern']=True
            m=bpy.data.materials.new('CandleWarm');m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(1,.42,.08,0);p.inputs['Alpha'].default_value=0;m.surface_render_method='DITHERED';o.data.materials.clear();o.data.materials.append(m)
        if group not in ['Foliage','Glass','CandleWarm']:
            # Preserve authored UV coordinates used by source textures before creating the atlas.
            if not o.data.uv_layers:o.data.uv_layers.new(name='SourceUV')
            uv=o.data.uv_layers.active;uv.name='SourceUV'
            mats=[]
            for slot in o.material_slots:
                if not slot.material:continue
                slot.material=slot.material.copy();m=slot.material;m.use_nodes=True;mats.append(m)
                olduv=m.node_tree.nodes.new('ShaderNodeUVMap');olduv.uv_map='SourceUV'
                for n in list(m.node_tree.nodes):
                    if n.type=='TEX_IMAGE' and not n.inputs['Vector'].is_linked:m.node_tree.links.new(olduv.outputs[0],n.inputs['Vector'])
                    if n.type=='TEX_COORD':
                        for link in list(n.outputs['UV'].links):m.node_tree.links.new(olduv.outputs[0],link.to_socket)
            o.data.uv_layers.new(name='GameAtlas');o.data.uv_layers.active_index=len(o.data.uv_layers)-1;o.data.uv_layers.active.active_render=True
            if 'hanging_pennant' not in o.name.lower():
                bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.012);bpy.ops.object.mode_set(mode='OBJECT')
            baked={};targets=[]
            for m in mats:
                node=m.node_tree.nodes.new('ShaderNodeTexImage');m.node_tree.nodes.active=node;targets.append(node)
            for kind in ['DIFFUSE','NORMAL','ROUGHNESS']:
                im=bpy.data.images.new(key+'_'+o.name+'_'+kind,2048,2048,alpha=False)
                if kind!='DIFFUSE':im.colorspace_settings.name='Non-Color'
                for node in targets:node.image=im
                bpy.ops.object.bake(type=kind,pass_filter={'COLOR'} if kind=='DIFFUSE' else set(),use_clear=True)
                im.filepath_raw=str(OUT/(im.name+'.png'));im.file_format='PNG';im.save();im.pack();baked[kind]=im
            m=bpy.data.materials.new(key+'_'+group+'_PBR');m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Metallic'].default_value=.75 if 'Metal' in group else 0
            for kind,socket in [('DIFFUSE','Base Color'),('ROUGHNESS','Roughness'),('NORMAL','Normal')]:
                t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=baked[kind]
                if kind=='NORMAL':
                    n=m.node_tree.nodes.new('ShaderNodeNormalMap');m.node_tree.links.new(t.outputs[0],n.inputs[1]);m.node_tree.links.new(n.outputs[0],p.inputs[socket])
                else:m.node_tree.links.new(t.outputs[0],p.inputs[socket])
            o.data.materials.clear();o.data.materials.append(m)
            for polygon in o.data.polygons:polygon.material_index=0
            # Export one UV channel, the baked atlas.
            o.data.uv_layers.remove(o.data.uv_layers['SourceUV'])
        output.append(o);o.data.calc_loop_triangles();detail.append({'mesh':o.name,'triangles':len(o.data.loop_triangles),'wind':dict(o.get('rmmo_wind',{}))})
    select(output)
    path=OUT/(key+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_animations=False)
    reports[:]=[r for r in reports if r['id']!=key]
    reports.append({'id':key,'source':file,'file':str(path),'parts':detail,'source_pivot':list(pivot)})
    (OUT/'manifest.json').write_text(json.dumps(reports,indent=2),encoding='utf8');print('EXPORTED_PROP',key,flush=True)
for item in inventory:
    f=item['file'];prefix=f.split('/')[0]
    for col in item['collections']:
        name=col['name']
        if name in ['Collection','REVIEW_STAGE'] or name.endswith('_CONTENTS'):continue
        if prefix=='bridge_street_kit' and name.startswith(('01_','05_','06_','07_','11_')):continue
        bpy.ops.wm.open_mainfile(filepath=str(ART/f));objects=list(bpy.data.collections[name].all_objects)
        export(f,prefix+'_'+name,objects)
    if prefix=='town_festival_posts':
        bpy.ops.wm.open_mainfile(filepath=str(ART/f))
        objects=[o for o in bpy.data.collections['Collection'].all_objects if o.name.startswith(('Hanging pennant','Suspended flax'))]
        export(f,'town_festival_posts_bunting',objects)
    if prefix=='small_wall_lantern':
        bpy.ops.wm.open_mainfile(filepath=str(ART/f));root=bpy.data.objects.get('WALL_MOUNT_ORIGIN');export(f,'small_wall_lantern',list(root.children))
print('TOWN_PROP_EXPORT_COMPLETE',len(reports))

