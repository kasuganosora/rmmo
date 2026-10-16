"""Re-map original Fab timber only. No geometry, transform, image or render edits."""
import hashlib
import json
import random
import bpy

WOOD_NAME = 'Fab solid timber - longitudinal grain'
UV_NAME = 'WoodSourceUV'
MATERIAL_NAME = WOOD_NAME + ' / market source UV v2'


def _wood(material):
    return material is not None and material.name in (WOOD_NAME, MATERIAL_NAME)


def _sampling_material(source):
    existing=bpy.data.materials.get(MATERIAL_NAME)
    if existing:
        if existing.get('wood_source_material')!=WOOD_NAME:raise ValueError('Unexpected existing timber material')
        return existing
    images=[n for n in source.node_tree.nodes if n.type=='TEX_IMAGE']
    if len(images)!=3 or any(n.image is None or n.extension!='REPEAT' or n.inputs['Vector'].is_linked for n in images):
        raise ValueError('Original timber PBR sampling changed; inspect before remapping')
    normal=[n for n in source.node_tree.nodes if n.type=='NORMAL_MAP']
    if len(normal)!=1 or normal[0].space!='TANGENT':raise ValueError('Expected original tangent-space timber normal')
    m=source.copy();m.name=MATERIAL_NAME
    m['wood_source_material']=WOOD_NAME
    m['authoring_bake_required']=True
    uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.name='Explicit original timber source UV';uv.uv_map=UV_NAME
    for n in m.node_tree.nodes:
        if n.type=='TEX_IMAGE':m.node_tree.links.new(uv.outputs['UV'],n.inputs['Vector'])
        elif n.type=='NORMAL_MAP':n.uv_map=UV_NAME
    return m


def _cloth(obj):
    if str(obj.get('rmmo_export_group','')).startswith('Cloth'):return True
    return obj.name.startswith(('Replaceable sloping canvas roof','Cloth scalloped valance','Sewn ochre binding'))


def apply(collection):
    """Return JSON-compatible metadata; source images stay shared and untouched.

    The UV map is deliberately explicit in both PBR image and NormalMap nodes,
    so adding/activating a destination atlas does not change source sampling.
    """
    objects=list(collection.all_objects)
    contents={o for c in collection.children_recursive if c.name.endswith('_CONTENTS') for o in c.all_objects}
    records=[];groups={}
    for o in objects:
        if o.type not in ('MESH','CURVE','SURFACE'):continue
        if o in contents:
            if any(_wood(m) for m in o.data.materials):o['rmmo_export_group']='GoodsOpaque'
        elif not _cloth(o):o['rmmo_export_group']='Structure'
        if o.get('rmmo_export_group'):groups[o.name]=str(o['rmmo_export_group'])
        if o.type!='MESH' or not any(_wood(m) for m in o.data.materials):continue
        if o.get('market_wood_uv_version')==2:
            records.append(json.loads(o['market_wood_uv_record']));continue
        if len(o.data.materials)!=1 or not _wood(o.data.materials[0]):raise ValueError('Mixed timber/non-timber mesh requires face-scoped mapping')
        if o.data.users>1:o.data=o.data.copy()
        material=_sampling_material(o.data.materials[0]);o.data.materials[0]=material
        mn=[min(v.co[i] for v in o.data.vertices) for i in range(3)]
        mx=[max(v.co[i] for v in o.data.vertices) for i in range(3)]
        extent=[mx[i]-mn[i] for i in range(3)]
        axis=max(range(3),key=lambda i:extent[i]);cross=[i for i in range(3) if i!=axis]
        seed=int(hashlib.sha256((collection.name+'|'+o.name).encode()).hexdigest()[:16],16)
        rng=random.Random(seed);u0=rng.random();v0=rng.random();scale=rng.uniform(.94,1.06)
        # The original PBR grain was visually checked: longitudinal grain is V.
        # One complete source tile represents ~1.6m across / 2.6m along grain.
        us=scale/1.6;vs=scale/2.6
        uv=o.data.uv_layers.get(UV_NAME) or o.data.uv_layers.new(name=UV_NAME)
        for face in o.data.polygons:
            normal_axis=max(range(3),key=lambda i:abs(face.normal[i]))
            transverse=next((i for i in cross if i!=normal_axis),cross[0])
            for li in face.loop_indices:
                p=o.data.vertices[o.data.loops[li].vertex_index].co
                if normal_axis==axis:
                    # Small end faces use the same original PBR; no invented
                    # scanned end-grain claim. Geometry and material count stay.
                    u=(p[cross[0]]-mn[cross[0]])*us+u0
                    v=(p[cross[1]]-mn[cross[1]])*vs+v0
                else:
                    u=(p[transverse]-mn[transverse])*us+u0
                    v=(p[axis]-mn[axis])*vs+v0
                uv.data[li].uv=(u,v)
        record={'object':o.name,'long_axis_local':axis,'source_uv':UV_NAME,'source_tile_metres':[1.6,2.6],'scale':scale,'offset':[u0,v0],'material':material.name,'export_group':str(o.get('rmmo_export_group',''))}
        o['market_wood_uv_version']=2;o['market_wood_uv_record']=json.dumps(record,sort_keys=True)
        records.append(record)
    if not records:raise ValueError('No exact recognized Fab timber in this collection')
    return {'version':2,'collection':collection.name,'objects':records,'wood_object_count':len(records),'groups':groups,'geometry_changed':False,'source_images_changed':False,'source_material':WOOD_NAME,'source_uv':UV_NAME,'bake_required':True,'gpu_status':'pending','limitation':'Small exposed end faces retain original longitudinal timber source; dedicated end-grain photograph not introduced.'}
