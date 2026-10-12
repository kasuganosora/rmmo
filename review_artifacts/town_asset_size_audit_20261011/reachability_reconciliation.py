"""Independent read-only reconciliation; no candidate generation or GPU."""
import collections,hashlib,importlib.util,json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
spec=importlib.util.spec_from_file_location('compact',HERE/'architecture_lossless.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
ref=helper.ref
input_path=ROOT/'review_artifacts/model_texture_code_audit_20261011.json'
code=json.loads(input_path.read_text(encoding='utf-8'))
inventory=json.loads((HERE/'inventory_report.json').read_text(encoding='utf-8'))
rows=[];extras=collections.Counter();extension_locations=[];declared_ext=set()

def walk(value,path='',extra=False):
    if isinstance(value,dict):
        for key,item in value.items():
            if key=='extras':yield(path+'/extras',item,True)
            if key=='extensions' and item:yield(path+'/extensions',item,False)
            if key not in ['extras','extensions']:yield from walk(item,path+'/'+key,extra)
    elif isinstance(value,list):
        for i,item in enumerate(value):yield from walk(item,path+'/'+str(i),extra)

def images_for(j,materials):
    tex={slot['index']for i in materials for slot in ref.texture_slots(j['materials'][i])}
    result=set()
    for index in tex:
        t=j['textures'][index]
        if 'source'in t:result.add(t['source'])
        for ext in t.get('extensions',{}).values():
            if isinstance(ext,dict)and'source'in ext:result.add(ext['source'])
    return result

for source in inventory['rows']:
    src=ref.Glb(Path(source['path']));j=src.j
    declared_ext.update(j.get('extensionsUsed')or[])
    for location,value,is_extra in walk(j):
        if is_extra:extras.update(value.keys())
        else:extension_locations.append({'asset':source['path'],'location':location,'keys':list(value)})
    mats={p['material']for mesh in j.get('meshes',[])for p in mesh['primitives']if'material'in p}
    reachable=images_for(j,mats)
    anymaterial=images_for(j,range(len(j.get('materials',[]))))
    anytexture={t['source']for t in j.get('textures',[])if'source'in t}
    allimages=set(range(len(j.get('images',[]))))
    defaults={x['index']for x in source['gltf_audit']['images']if x['used_by_default_scene_material']}
    live_accessors=set()
    for m in j.get('meshes',[]):
        for p in m['primitives']:
            live_accessors.update(p['attributes'].values())
            if'indices'in p:live_accessors.add(p['indices'])
            for t in p.get('targets',[]):live_accessors.update(t.values())
    accessor_views={j['accessors'][i]['bufferView']for i in live_accessors}
    image_views={j['images'][i]['bufferView']for i in reachable}
    orphanimage_views={j['images'][i]['bufferView']for i in allimages-reachable}
    top_ext=[x for x in extension_locations if x['asset']==source['path']]
    try:helper.guard_graph(j);guard='supported'
    except AssertionError as error:guard='rejected: '+str(error)
    prior=next(x for x in code['assets']if x['path'].lower()==source['path'].lower())
    unused_bytes=sum(len(src.blob(j['images'][i]['bufferView']))for i in allimages-reachable)
    row={'path':source['path'],'declared_images':len(allimages),'all_mesh_material_reachable_images':len(reachable),
         'any_material_referenced_images':len(anymaterial),'unused_material_only_images':len(anymaterial-reachable),
         'no_material_reference_images':len(allimages-anymaterial),'any_texture_source_images':len(anytexture),
         'unused_encoded_image_bytes':unused_bytes,'matches_prior_code_audit':len(reachable)==prior['images_reachable_from_all_mesh_materials']and unused_bytes==prior['encoded_unreachable_bytes'],
         'default_scene_vs_all_declared_mesh_image_sets_equal':defaults==reachable,
         'source_image_views_also_used_by_live_accessor':sorted(image_views&accessor_views),
         'orphan_image_views_retained_by_live_accessor':sorted(orphanimage_views&accessor_views),
         'view_shared_by_live_and_unused_image':sorted(orphanimage_views&image_views),
         'extension_declarations':j.get('extensionsUsed',[]),'active_extension_objects':top_ext,'compactor_guard':guard,
         'lod_nodes':[{'name':n.get('name'),'range':n.get('extras',{}).get('rmmo_visibility_range'),'collision':n.get('extras',{}).get('rmmo_collision')}for n in j['nodes']if'rmmo_visibility_range'in n.get('extras',{})]}
    rows.append(row);src.close()

base=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011')
checks=[]
audit_files=sorted(list((base/'architecture').glob('*_audit.json'))+list((base/'secondary').glob('*_audit.json'))+list((base/'foliage').glob('*/lossless_audit.json')))
for path in audit_files:
    audit=json.loads(path.read_text(encoding='utf-8'))
    before=ref.Glb(Path(audit['source']));after=ref.Glb(Path(audit.get('candidate',audit.get('output'))))
    helper.guard_graph(before.j);helper.guard_graph(after.j)
    equal=helper.graph(before)==helper.graph(after)
    maps=audit['remap']
    direct=all(before.blob(int(old))==after.blob(new)for old,new in maps['bufferViews'].items())
    source_sha=ref.digest(Path(audit['source']))
    target=Path(audit.get('candidate',audit.get('output')))
    current_sha=ref.digest(target)
    checks.append({'audit':str(path),'source':audit['source'],'candidate':str(target),'source_sha256':source_sha,
                   'candidate_sha256':current_sha,'source_matches_build':source_sha==audit['source_sha256'],
                   'candidate_matches_build':current_sha==audit.get('candidate_sha256',audit.get('output_sha256')),
                   'all_declared_mesh_resolved_graph_equal':equal,'all_kept_buffer_view_bytes_equal':direct,
                   'all_nodes_extras_and_scene_fields_equal':before.j['nodes']==after.j['nodes']and before.j['scenes']==after.j['scenes']})
    before.close();after.close()

known_extras={
 'rmmo_collision':'string collision mode; independent from editor picking layer',
 'rmmo_wind':'named mesh selector/profile/anchor plus physical numbers and booleans; no table indices',
 'rmmo_leaf_backlight':'per-surface scalar array; mesh primitive order is unchanged',
 'rmmo_visibility_range':'distance scalars and six AABB coordinates; no table indices',
 'rmmo_opacity_packed':'boolean import/art hint',
 'asset_role':'descriptive role string',
 'rmmo_small_wall_lantern':'boolean light behavior flag',
 'artwork_slot':'descriptive authoring-slot string',
 'rmmo_grass':'boolean behavior flag',
 'source_fab':'source listing identifier string',
 'slot':'logical slot number retained unchanged; not consumed as a glTF index by project code',
 'rmmo_banner_slot':'boolean replaceable banner flag',
}
totals={key:sum(r[key]for r in rows)for key in ['declared_images','all_mesh_material_reachable_images','any_material_referenced_images','unused_material_only_images','no_material_reference_images','any_texture_source_images','unused_encoded_image_bytes']}
out={'scope':'Read-only source/candidate and implementation reconciliation. No Godot/GPU, no rebuild, no map/asset mutations. Only this report and its note are written.',
     'code_audit_path':str(input_path),'code_audit_sha256':ref.digest(input_path),'summary':totals,
     'all_32_counts_and_encoded_bytes_match_code_audit':all(r['matches_prior_code_audit']for r in rows),
     'inventory_default_scene_vs_all_mesh_roots_equal_for_this_dataset':all(r['default_scene_vs_all_declared_mesh_image_sets_equal']for r in rows),
     'wording_correction':'236 images are outside the all-declared-mesh/material graph, not reference-free: 106 are referenced only by unused materials and 130 by no material; all 366 still have declared texture.source references. Prune material/texture dependencies and remap before images.',
     'extensions_used_declarations':sorted(declared_ext),'actual_extension_objects':extension_locations,
     'extension_guard_boundary':'Current ten lossless candidate sources have no active extension object. KHR_materials_specular declaration-only is preserved. The architecture helper rejects animations, skins, sparse/URI accessors/images, required extensions, active extension objects and unsupported declaration names. One untouched streetlamp source declares KHR_materials_transmission and is rejected, not silently pruned. Future extension support requires complete references/remap/resolved tests.',
     'shared_buffer_view_boundary':'Compactor keeps the union of live accessor and live image views before repacking. It rewrites both accessor.bufferView and image.bufferView, retains view metadata and accessor byteOffset/count/stride recipes, checks all kept bytes directly. No shared live geometry/image view or unused-image/live-accessor overlap exists in these 32 sources. Whole-view union nevertheless prevents blindly deleting a view solely because an image is unused.',
     'custom_extras_keys_counts':dict(extras),'custom_extras_semantics':known_extras,
     'custom_extras_boundary':'All observed keys are the reviewed 12 schemas, and all candidate nodes/mesh/material/root extras remain exact with primitive order unchanged. Metadata is not generically index-aware: guard_graph deliberately skips extras, so preservation alone is not sufficient for arbitrary future numeric glTF references. Unknown extras must be classified/rejected before reusing this tool generally.',
     'observed_custom_extras_all_classified':set(extras)<=set(known_extras),
     'rows':rows,'lossless_candidates_verified':checks,
     'lossy_candidate_boundary':'Pennant shared/detail/balanced and foliage resolution profiles intentionally change texture data. They are outside exact-image equality claims, require their separate pixel/alpha/normal/roughness and GPU reports, and must not be mislabeled lossless.',
     'lod_and_picking_recommendations':[
       {'status':'proposed_not_implemented','recommendation':'Keep authored LOD groups and rmmo_visibility_range metadata. Visibility-range culling does not set Node.visible; current editor _add_bodies traverses every enabled MeshInstance3D and can build pick shapes for multiple LODs. Future optimization should share a canonical per-authoring-object pick proxy or use a stable finest pick mesh per LOD group, without duplicating geometry for each LOD.', 'code':['scripts/world3d/asset_visibility_range.gd:8','scripts/world_editor/world_editor.gd:606','scripts/world_editor/world_editor.gd:613','scripts/world_editor/picking_shape_cache.gd:10']},
       {'status':'required_behavior','recommendation':'rmmo_collision:none disables gameplay/walk physical blocking, not editor selection. Retain editor picking layer 1, author UUID and independent selection while excluding WALK_MASK. Never optimize by skipping all none meshes or deleting their pickability. A future proxy must remain pickable for flags/foliage even when gameplay collision is none.', 'code':['scripts/world_editor/world_editor.gd:623','scripts/world_editor/walk_mode.gd:31']},
       {'status':'required_behavior','recommendation':'Any future proxy/LOD optimization must honor hidden/floor-excluded states, locks, precise overlapping/alpha-card selection expectations, transform/undo/save identity and moving wind geometry selection bounds; do not merge the whole map or use a coarse filled AABB as proven equivalent.'}
     ]}
assert out['all_32_counts_and_encoded_bytes_match_code_audit']
assert all(all(c[k]for k in ['source_matches_build','candidate_matches_build','all_declared_mesh_resolved_graph_equal','all_kept_buffer_view_bytes_equal','all_nodes_extras_and_scene_fields_equal'])for c in checks)
(HERE/'reachability_reconciliation.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
note='''# 可达图复核补充（2026-10-11）

32项与 `model_texture_code_audit_20261011.json` 完全吻合：366张声明图像中130张从所有mesh材质可达；其余236张=106张仅由未使用材质引用+130张没有材质引用。**全部366张都有texture.source引用**，此前“未引用图片”应准确写作“未从mesh材质图可达的图片”，不能直接删image表而不清理texture/material和索引。

初版inventory以默认场景为根，新复核以全部声明mesh为根；这32项两个集合恰好完全相同。当前无真实extension对象，仅有specular/transmission声明。十件无损候选复核全部通过：源/候选SHA、全部mesh解析图、保留bufferView逐字节、节点/场景/extras一致。transmission声明的路灯不在这十件中，保守helper会拒绝，未静默处理未知扩展。

清理取活跃accessor与image的bufferView并集，重映射两类引用且保留view/accessor布局；当前32项没有图像与几何共用view。12类当前extras已逐类核对，均无需要重映射的GLB表索引。**工具不是通用extras索引解析器**：未来未知扩展或custom extras应先分类/拒绝，不能凭“extras字典没改”就判定可安全清理。

彩旗与植物降分辨率候选有明确像素变化，不纳入无损图像相等结论。未运行GPU、未修改正式资源或地图。

LOD/拾取后续建议：保持LOD组和author UUID，以独立稳定的精确拾取代理避免每个LOD重复建拾取形状。`rmmo_collision:none`只去掉游戏/行走碰撞，**必须仍能在编辑器选择**：保留layer 1，单独排除WALK_MASK。当前visibility range不改变Node.visible，不能据距离自动假定其它LOD无需拾取。代理优化尚未实现，需另外验证隐藏/楼层、重叠物、风场位移、撤销保存。

完整逐项证据：`reachability_reconciliation.json`；复查脚本：`reachability_reconciliation.py`。
'''
(HERE/'reachability_reconciliation.md').write_text(note,encoding='utf-8')
print(json.dumps({'summary':totals,'strict_candidates':len(checks),'all_match':out['all_32_counts_and_encoded_bytes_match_code_audit']},indent=2))
