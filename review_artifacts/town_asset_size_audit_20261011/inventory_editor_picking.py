"""Add explicit, validated LOD pick groups to independent GLB candidates only.

Copies the entire BIN chunk exactly. No production code, source asset or map edits.
"""
import collections,copy,hashlib,importlib.util,json,struct
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
ART=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011')
OUT=ART/'editor_picking'
spec=importlib.util.spec_from_file_location('glb_exact',ROOT/'tools/optimize_bridge_pennant_glb.py')
exact=importlib.util.module_from_spec(spec);spec.loader.exec_module(exact)
hashbytes=lambda data:hashlib.sha256(data).hexdigest()

def sources():
    audit=json.loads((ART/'architecture/oak_9ba5457e_audit.json').read_text(encoding='utf-8'))
    yield {'label':'oak_canopy','path':audit['candidate'],'sha256':audit['candidate_sha256'],
           'group':'oak_canopy','lod_names':['Oak_Canopy_LOD0','Oak_Canopy_LOD1','Oak_Canopy_LOD2'],
           'source_kind':'validated_lossless_candidate','source_audit':str(ART/'architecture/oak_9ba5457e_audit.json')}
    foliage=json.loads((ART/'foliage/foliage_manifest.json').read_text(encoding='utf-8'))['assets']
    for row in foliage:
        label=row['asset']
        yield {'label':label,'path':row['candidate'],'sha256':row['candidate_sha256'],
               'group':label+'_foliage','lod_names':[]if label=='foliage_boxwood'else[label+'_LOD0',label+'_LOD1'],
               'source_kind':'validated_lossless_candidate','source_audit':str(ART/'foliage'/label/'lossless_audit.json')}
    handoff=json.loads((ROOT/'review_artifacts/town_large_asset_art_handoff_20261011.json').read_text(encoding='utf-8'))['rows']
    for prefix,label in [('117f47a0','arch_A'),('c9c641df','arch_B'),('2abd3fe0','arch_C')]:
        row=next(r for r in handoff if Path(r['path']).name.startswith(prefix))
        yield {'label':label,'path':row['path'],'sha256':row['source_sha256'],
               'group':label.lower()+'_grass','lod_names':[label+'_LOD0',label+'_LOD1',label+'_LOD2'],
               'source_kind':'current_map_original_hash_source','source_audit':str(ROOT/'review_artifacts/town_large_asset_art_handoff_20261011.json')}

def triangles(j,node):
    return sum(j['accessors'][p['indices']]['count']//3 if'indices'in p else j['accessors'][p['attributes']['POSITION']]['count']//3 for p in j['meshes'][node['mesh']]['primitives'])

def build(row):
    path=Path(row['path']);assert exact.digest(path)==row['sha256']
    src=exact.Glb(path);j=src.j
    assert not any('rmmo_editor_picking'in n.get('extras',{})for n in j['nodes'])
    if not row['lod_names']:
        assert len(j['nodes'])==1 and'mesh'in j['nodes'][0] and'rmmo_visibility_range'not in j['nodes'][0].get('extras',{})
        result={**row,'status':'skipped_no_lod','reason':'Single Foliage mesh, no LOD ranges or substitute sibling; no fabricated group and no redundant metadata copy.',
                'node':j['nodes'][0]['name'],'source_unchanged':exact.digest(path)==row['sha256']}
        src.close();return result
    names=collections.defaultdict(list)
    for i,node in enumerate(j['nodes']):names[node.get('name','')].append(i)
    indices=[]
    for name in row['lod_names']:
        assert len(names[name])==1;indices.append(names[name][0])
    parents={child:parent for parent,node in enumerate(j['nodes'])for child in node.get('children',[])}
    assert len({parents.get(i)for i in indices})==1,'LOD candidates must share the same parent'
    poses=[{k:j['nodes'][i][k]for k in ['matrix','translation','rotation','scale']if k in j['nodes'][i]}for i in indices]
    assert all(pose==poses[0]for pose in poses),'Unexpected relative LOD pose'
    ranges=[j['nodes'][i]['extras']['rmmo_visibility_range']for i in indices]
    assert ranges[0]['begin']==0
    assert all(r['bounds']==ranges[0]['bounds']for r in ranges)
    assert all(ranges[n]['end']==ranges[n+1]['begin']and ranges[n]['end']>ranges[n]['begin']for n in range(len(ranges)-1))
    assert ranges[-1]['end']==0 or ranges[-1]['end']>ranges[-1]['begin']
    revised=copy.deepcopy(j)
    tagged=[]
    for order,i in enumerate(indices):
        node=revised['nodes'][i];assert'mesh'in node
        role='canonical'if order==0 else'render_lod'
        if role=='render_lod':assert node['extras'].get('rmmo_collision')=='none','Never suppress real walk/block collision'
        node['extras']['rmmo_editor_picking']={'version':1,'group':row['group'],'role':role}
        tagged.append({'node_index':i,'name':node['name'],'mesh_index':node['mesh'],'role':role,'triangles':triangles(j,node),
                       'collision':node['extras'].get('rmmo_collision'),'visibility_range':ranges[order]})
    # Keep every byte of the original BIN chunk, including unused historic data.
    original_bin=bytes(src.raw[src.start:])
    encoded=json.dumps(revised,ensure_ascii=False,separators=(',',':')).encode('utf-8');encoded+=b' '*((-len(encoded))%4)
    output=OUT/(row['label']+'_editor_picking.glb')
    assert output.resolve()!=path.resolve()
    result_bytes=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(original_bin))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(original_bin),0x004e4942)+original_bin
    if output.exists():assert output.read_bytes()==result_bytes,'Refuse to replace a different prior candidate'
    else:output.write_bytes(result_bytes)
    dst=exact.Glb(output)
    untagged=copy.deepcopy(dst.j)
    for i in indices:del untagged['nodes'][i]['extras']['rmmo_editor_picking']
    assert untagged==j,'A non-metadata JSON property changed'
    assert bytes(dst.raw[dst.start:])==original_bin
    assert dst.j['materials']==j['materials']and dst.j['images']==j['images']and dst.j['meshes']==j['meshes']
    assert all(src.blob(i)==dst.blob(i)for i in range(len(j['bufferViews'])))
    grouping=collections.defaultdict(list)
    for i,node in enumerate(dst.j['nodes']):
        metadata=node.get('extras',{}).get('rmmo_editor_picking')
        if metadata is None:continue
        assert set(metadata)=={'version','group','role'}and metadata['version']==1 and metadata['group']
        assert metadata['role']in ['canonical','render_lod']
        if metadata['role']=='render_lod':assert node['extras']['rmmo_collision']=='none'
        grouping[metadata['group']].append((i,metadata['role']))
    assert len(grouping)==1 and list(grouping)==[row['group']]
    assert sum(role=='canonical'for _,role in grouping[row['group']])==1
    assert grouping[row['group']][0]==(indices[0],'canonical')and row['lod_names'][0].endswith('_LOD0')
    assert exact.digest(path)==row['sha256']
    result={**row,'status':'candidate_ready_metadata_only','candidate':str(output),'candidate_sha256':exact.digest(output),
            'source_bytes':path.stat().st_size,'candidate_bytes':output.stat().st_size,'binary_chunk_sha256':hashbytes(original_bin),
            'binary_chunk_exact':True,'all_buffer_views_exact':True,'all_non_added_json_fields_exact':True,
            'geometry_image_material_bytes_unchanged':True,'wind_collision_lod_transform_extras_unchanged':True,'source_unchanged':True,
            'groups_valid':True,'metadata_location':'glTF nodes[i].extras for each MeshInstance node; mesh resource tables untouched',
            'tagged_nodes':tagged,'independent_meshes_untouched':[{'node_index':i,'name':n.get('name'),'collision':n.get('extras',{}).get('rmmo_collision')}for i,n in enumerate(j['nodes'])if'mesh'in n and i not in indices],
            'candidate_canonical_triangle_count':tagged[0]['triangles'],
            'potential_redundant_lod_pick_triangles':sum(n['triangles']for n in tagged[1:]),
            'consumer_boundary':'Potential picking-only savings after a separate validated runtime/editor consumer. No rendering/physics/selection code changed and no speedup claimed.',
            'gpu_run':False,'published':False}
    src.close();dst.close();return result

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[build(row)for row in sources()]
    manifest={'date':'2026-10-11','version':1,'schema':{'version':1,'group':'asset-local unique named LOD group','role':'canonical | render_lod'},
              'scope':'Independent metadata-only candidates for proven substitute LOD groups. Seven candidates, one unmodified single-mesh boxwood exclusion. No production source/resource/map/code replacement and no GPU.',
              'source_choice':'Oak and three shrubs/boxwood use exact lossless cleanup versions; arch_A/B/C use the current immutable hash source because no cleaned approved grass candidate exists in this branch.',
              'compatibility':'Unknown extras must remain preserved by GLB tooling. New consuming editor/runtime code must separately allow and validate rmmo_editor_picking; none still means gameplay collision off, not unselectable.',
              'rows':rows,'summary':{'candidate_count':sum(r['status']=='candidate_ready_metadata_only'for r in rows),'skipped_count':sum(r['status']=='skipped_no_lod'for r in rows),
                                    'group_count':7,'canonical_nodes':7,'render_lod_nodes':sum(len(r.get('tagged_nodes',[]))-1 for r in rows if r.get('tagged_nodes'))}}
    (OUT/'editor_picking_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (HERE/'editor_picking_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(manifest['summary'],indent=2))

if __name__=='__main__':main()
