"""Bind current guild sources to per-item source/native/gallery/HTTP evidence.

Read-only for models/maps/library. Writes only this task's isolated JSON reports.
Historical evidence is retained but never promoted across a different SHA.
"""
from pathlib import Path
import collections
import datetime
import hashlib
import json

REPO=Path(__file__).resolve().parents[1]
ROOT=REPO/'review_artifacts/guild_reference_recheck_20261013'
ART=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')


def load(path):
    try:return json.loads(path.read_text('utf8'))
    except (OSError, ValueError):return {}


def digest(path):
    if not path.is_file():return None
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+'.pending')
    temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
    temporary.replace(path)


def checked_images(images):
    """Only explicit, hashed and actually viewed image records are visual proof."""
    result=[]
    for value in images:
        if not isinstance(value,dict):
            result.append(dict(path=value,actually_viewed=False,file_matches=False))
            continue
        image_path=Path(value.get('path',''))
        stored=value.get('sha256')
        result.append(dict(path=str(image_path),actually_viewed=value.get('actually_viewed',False),
            stored_sha256=stored,file_matches=bool(stored) and digest(image_path)==stored))
    return result


def manual_decision_matches(decision,current_sha):
    images=checked_images(decision.get('viewed_images',[]))
    return (decision.get('source_sha256')==current_sha and decision.get('status')=='passed'
        and bool(images) and all(r['actually_viewed'] and r['file_matches'] for r in images))


def manual_optimization_matches(decision,current_sha):
    """An explicit optimization verdict is independent of requested art changes."""
    images=checked_images(decision.get('optimization_viewed_images',[]))
    return (decision.get('source_sha256')==current_sha and decision.get('optimization_status')=='passed'
        and bool(images) and all(r['actually_viewed'] and r['file_matches'] for r in images))


def gallery_inventory(expected):
    rows=[]
    for folder in ROOT.iterdir():
        if not folder.is_dir() or folder.name in ['resource_audit','acceptance']:continue
        for path in [folder/'report.json', *folder.glob('*/report.json')]:
            report=load(path); identity=report.get('identity',{})
            aid=identity.get('asset_id',identity.get('id'))
            if aid not in expected:continue
            rows.append(dict(id=aid,report=str(path),report_sha256=digest(path),source_sha256=identity.get('sha256'),
                current_source_match=identity.get('sha256')==expected[aid],passed=report.get('passed',False),
                gallery_completed=report.get('gallery_completed',False),generator=report.get('generator'),
                native_sha256=report.get('native_sha'),native_bytes=report.get('native_bytes'),
                screenshots=len(report.get('screenshots',[]))))
    return rows


def manual_evidence(aid,current_sha):
    path=ROOT/'independent_library_review'/(aid+'.json');report=load(path)
    images=report.get('viewed_images',[])
    source_match=report.get('audited_source_sha256')==current_sha
    image_records=checked_images(images)
    passed=source_match and str(report.get('visual_status','')).startswith('通过') and not report.get('batch_repair_pending',True) and bool(images) and all(r['actually_viewed'] and r['file_matches'] for r in image_records)
    decision=load(ROOT/'visual_decisions.json').get(aid,{})
    if manual_decision_matches(decision,current_sha):
        return dict(status='passed',report=str(ROOT/'visual_decisions.json'),source_sha256=current_sha,
            image_records=checked_images(decision.get('viewed_images',[])),decision=decision)
    return dict(status='passed' if passed else 'pending',report=str(path) if report else None,
        source_sha256=report.get('audited_source_sha256'),current_source_match=source_match,
        original_status=report.get('visual_status'),image_records=image_records,
        observations=report.get('observations',[]),references=report.get('reference_paths',{}))


def implementation_matches(report):
    identities=report.get('runtime_implementation',{})
    return bool(identities) and all(digest(REPO/'scripts/world3d'/name)==value for name,value in identities.items())


def current_evidence(paths,predicate,fallback):
    matching=[path for path in paths if predicate(load(path))]
    return max(matching,key=lambda p:p.stat().st_mtime) if matching else fallback


def scoped_roof_inheritance(current_sha):
    """Only the independently proved normal-only amendment may reuse e24 scopes."""
    path=ROOT/'roof_normal_scope/independent_scope_audit.json';report=load(path)
    if not report.get('passed') or report.get('after',{}).get('sha256')!=current_sha:return {}
    if report.get('audit_tool_sha256')!=digest(REPO/'tools/audit_guild_roof_scope.py'):return {}
    for key in ['before','after']:
        identity=report.get(key,{})
        if not identity.get('sha256') or digest(Path(identity.get('path','')))!=identity['sha256']:return {}
    for key in ['json_except_declared_fields_identical','all_non_image_buffer_views_identical',
                'all_geometry_attributes_and_extras_identical','all_other_material_channels_identical']:
        if report.get(key) is not True:return {}
    prior=report.get('prior_decisions',{})
    for key in ['manual','lighting']:
        identity=prior.get(key,{})
        if not identity.get('sha256') or digest(Path(identity.get('path','')))!=identity['sha256']:return {}
    return dict(report=str(path),report_sha256=digest(path),before=report['before'],after=report['after'],
        inherited_scopes=report['inherited_scopes'],fresh_evidence_required=report['fresh_evidence_required'],
        prior_decisions=prior,note='Scope inheritance only: earlier GPU reports retain their original source SHA. Fresh current-source cost/native/HTTP and changed roof visuals remain mandatory.')


def write_overview(result,summary):
    """Readable index; each row's JSON retains complete hashes and evidence."""
    def state(value):
        if value=='not_applicable':return '不适用'
        if value.startswith('passed') and 'inherit' in value:return '通过（未受影响合同复用）'
        if value.startswith('passed') or value.startswith('derived_LOD_') or value.startswith('cost_and_current_'):return '通过'
        return '待验'
    lines=['# 公会 53 件逐件验收索引','',
        '生成时间：'+summary['timestamp'],'',
        '此表由实际导出 SHA 和当前实现指纹绑定证据生成。人工画面、资源成本、真实 HTTP、运行活动件/照明及优化分别判定；身份复验不冒充 HTTP。正式地图及正式库未发布。','',
        'GLB 合计 %.2f MiB；native 磁盘文件合计 %.2f MiB。独立家具与整楼包含重复内容，这些文件合计不是场景内存。纹理解码和准入峰值均为保守预算，不是实测 RSS/VRAM。'%(summary['source_bytes_sum']/2**20,summary['native_bytes_sum']/2**20),'',
        '|模型（逐件报告）|GLB / native MiB|资源|native 画廊|人工参考|实际 HTTP|活动件|实际照明|优化|',
        '|---|---:|---|---|---|---|---|---|---|']
    for row in result:
        stages=row['stages'];native_bytes=row['native_import'].get('native_manifest',{}).get('bytes',0)
        lines.append('|[%s](%s.json)|%.2f / %.2f|%s|%s|%s|%s|%s|%s|%s|'%(
            row['id'],row['id'],(row['source_bytes'] or 0)/2**20,native_bytes/2**20,
            *[state(stages[k]) for k in ['resource_with_native_cost','current_SHA_native_gallery','manual_reference_visual',
                'production_import_and_HTTP','runtime_component_semantics','runtime_lighting','optimization_review']]))
    lines+=['','优化列包括三种明确范围：整楼实际合批/LOD 同相机对比、塔楼显式 LOD，以及家具按当前成本/距离画面判断是否需要额外减面。每件 JSON 记录具体类型，不表示全部手工减面。','',
        '正式地图接入、房间/楼层/屋顶自动隐藏、整城性能和整城夜景均独立于此表；待验不会因同源其他模型通过而自动消失。','']
    (ROOT/'acceptance/README.md').write_text('\n'.join(lines),encoding='utf8')


def main():
    manifest=load(ART/'repair_manifest.json');source_rows=[
        dict(asset_id='axel_guild_repaired',path=str(ART/'axel_guild_repaired.glb'),sha256=manifest['final_sha256'],source_master=manifest['source_master']),
        dict(asset_id='guild_alarm_tower',**manifest['tower'])]+manifest['library']
    expected={r['asset_id']:digest(Path(r['path'])) for r in source_rows}
    galleries=gallery_inventory(expected)
    save(ROOT/'gallery_binding_audit.json',dict(timestamp=datetime.datetime.now().astimezone().isoformat(),
        note='Historical/stale galleries remain evidence of earlier iterations, never final current-SHA acceptance.',
        current_count=sum(r['current_source_match'] for r in galleries),stale_count=sum(not r['current_source_match'] for r in galleries),items=galleries))
    expected_generator=load(ROOT/'accepted_building/report.json').get('generator')
    inheritance=scoped_roof_inheritance(expected['axel_guild_repaired'])
    shared_sha=inheritance['before']['sha256'] if inheritance else expected['axel_guild_repaired']
    runtime_paths=['scripts/world3d/model_components.gd','scripts/world3d/runtime_mesh_cache.gd','scripts/world3d/model_collision_requirements.gd','scripts/world3d/ground_batcher.gd','scripts/world_editor/world_editor.gd','scripts/world_editor/mcp_ops.gd']
    runtime_identity={p:digest(REPO/p) for p in runtime_paths}
    runtime_path=current_evidence(ROOT.glob('*/runtime.json'),
        lambda r:r.get('source_sha')==shared_sha and r.get('passed',False) and implementation_matches(r),
        ROOT/'accepted_runtime/runtime.json');runtime_report=load(runtime_path)
    runtime_ok=runtime_report.get('source_sha')==shared_sha and runtime_report.get('passed',False) and implementation_matches(runtime_report)
    lighting_path=current_evidence(ROOT.glob('*/report.json'),
        lambda r:r.get('identity',{}).get('sha256')==shared_sha and r.get('passed',False) and implementation_matches(r)
            and {'lantern_detail_night_still.png','hall_night_still.png'}.issubset({shot.get('name') for shot in r.get('screenshots',[])}),
        ROOT/'accepted_lighting/report.json');lighting_report=load(lighting_path)
    decisions=load(ROOT/'visual_decisions.json')
    lighting_decision=decisions.get('axel_guild_repaired',{})
    separate_lighting=load(ROOT/'lighting_decision.json')
    if inheritance:
        lighting_decision=load(Path(inheritance['prior_decisions']['manual']['path']))
        separate_lighting=load(Path(inheritance['prior_decisions']['lighting']['path']))
    lighting_manual=manual_decision_matches(lighting_decision,shared_sha) and lighting_decision.get('lighting_status')=='passed'
    if manual_decision_matches(separate_lighting,shared_sha) and separate_lighting.get('runtime_implementation')==lighting_report.get('runtime_implementation'):lighting_manual=True
    lighting_ok=lighting_report.get('identity',{}).get('sha256')==shared_sha and lighting_report.get('passed',False) and implementation_matches(lighting_report) and lighting_manual
    optimization_path=current_evidence((REPO/'review_artifacts/axel_guild_finish_20261012').glob('reference_v3*optimization*/compare.json'),
        lambda r:r.get('source_sha256')==shared_sha and r.get('passed',False) and implementation_matches(r),
        REPO/'review_artifacts/axel_guild_finish_20261012/reference_v3_optimization_20261013/compare.json')
    optimization_report=load(optimization_path)
    optimization_ok=optimization_report.get('source_sha256')==shared_sha and optimization_report.get('passed',False) and implementation_matches(optimization_report) and manual_optimization_matches(lighting_decision,shared_sha)
    import_evidence=collections.defaultdict(list)
    for path in ROOT.glob('*/import_report.json'):
        report=load(path)
        for row in report.get('items',[]):
            if row.get('id') in expected and row.get('input_sha')==expected[row['id']]:
                import_evidence[row['id']].append((path,report,row))
    result=[]
    for row in source_rows:
        aid=row['asset_id'];current_sha=expected[aid];resource_path=ROOT/'resource_audit'/(aid+'.json');res=load(resource_path)
        resource_ok=res.get('source_sha256')==current_sha and not res.get('static_errors',['missing report']) and res.get('source_stable_during_audit',False)
        evidence=import_evidence[aid]
        # A newer headless identity-only report may re-prove resource costs but
        # cannot replace a successful real HTTP run. Prefer current runtime
        # evidence, then earlier real HTTP, and retain all candidates separately.
        evidence.sort(key=lambda e:(
            e[1].get('completed',False) and e[1].get('real_http',False) and e[2].get('http_passed',False) and e[1].get('http_runtime_identity')==runtime_identity,
            e[1].get('completed',False) and e[1].get('real_http',False) and e[2].get('http_passed',False),
            e[1].get('completed',False),e[0].stat().st_mtime),reverse=True)
        imported={};pipeline_ok=False;native_cost_ok=False
        if evidence:
            path,envelope,item=evidence[0];native=item.get('native_manifest',{})
            generator_match=expected_generator is not None and native.get('generator')==expected_generator
            semantics_ok=item.get('passed',False) and item.get('semantic_exact',False) and not item.get('native_differences',['missing']) and item.get('bytes_identical',False)
            native_cost_ok=bool(item.get('native_resource_stats')) and bool(item.get('conservative_admission')) and native.get('source_sha')==current_sha and generator_match
            runtime_match=envelope.get('http_runtime_identity')==runtime_identity
            pipeline_ok=semantics_ok and generator_match and runtime_match and item.get('http_passed',False) and envelope.get('completed',False) and envelope.get('real_http',False)
            imported=dict(report=str(path),report_sha256=digest(path),source_sha256=item.get('input_sha'),output_path=item.get('output_path'),output_sha256=item.get('output_sha'),
                bytes_identical=item.get('bytes_identical'),native_manifest=native,generator_matches_current_evidence=generator_match,
                content_root=envelope.get('content_root'),native_cache_directory=envelope.get('native_cache_directory'),isolation_note=envelope.get('isolation_note'),
                source_output_native_semantics=semantics_ok,real_http=envelope.get('real_http',False),http_passed=item.get('http_passed',False),
                http_runtime_identity=envelope.get('http_runtime_identity'),http_runtime_matches_current=runtime_match,
                source_semantic_stats=item.get('stats',{}),
                completed=envelope.get('completed',False),native_resource_stats=item.get('native_resource_stats'),conservative_admission=item.get('conservative_admission'),
                import_elapsed_ms=item.get('import_elapsed_ms'),batch_groups=item.get('batch_groups'),editor_collision_bodies=item.get('editor_collision_bodies'),component_count=item.get('component_count'))
            imported['available_evidence']=[dict(report=str(p),completed=e.get('completed',False),
                identity_check_only=e.get('identity_check_only',False),real_http=e.get('real_http',False),
                item_http_passed=i.get('http_passed',False),runtime_matches=e.get('http_runtime_identity')==runtime_identity)
                for p,e,i in evidence]
        matches=[g for g in galleries if g['id']==aid and g['current_source_match']]
        manual=manual_evidence(aid,current_sha)
        tower=load(ROOT/'final_tower_lod/game_review.json') if aid=='guild_alarm_tower' else {}
        # Missing fresh import evidence means pending, never "not applicable".
        # A scoped normal-only successor retains the prior audited node extras.
        semantic_resource_valid=resource_ok or (aid=='axel_guild_repaired' and bool(inheritance))
        extras=res.get('extras_counts',{}) if semantic_resource_valid else {}
        has_hinges=imported.get('source_semantic_stats',{}).get('hinge_members',0)>0 or extras.get('rmmo_hinge',0)>0
        has_lights=imported.get('source_semantic_stats',{}).get('light_sockets',0)>0 or extras.get('rmmo_light_socket',0)>0
        activity_ok=pipeline_ok and (runtime_ok if aid=='axel_guild_repaired' else bool(imported.get('component_count'))) if has_hinges else None
        light_status=(('passed_shared_runtime_with_proven_scope_inheritance' if inheritance else 'passed_shared_runtime_and_current_scene_visual') if lighting_ok and runtime_ok else 'pending_real_runtime_and_visual') if has_lights else 'not_applicable'
        if aid=='axel_guild_repaired':optimization_status=('passed_scope_inherited' if inheritance else 'passed') if optimization_ok else 'pending_current_same_camera_AB'
        elif aid=='guild_alarm_tower':optimization_status='passed' if tower.get('sha256')==current_sha and tower.get('passed') and manual['status']=='passed' else 'pending_current_explicit_LOD_visual'
        elif res.get('extras_counts',{}).get('rmmo_auto_lod'):
            optimization_status='derived_LOD_and_near_mid_far_reviewed_shared_compiler' if manual['status']=='passed' and any(g['passed'] and g['gallery_completed'] for g in matches) else 'pending_current_derived_LOD_visual'
        else:optimization_status='cost_and_current_visual_reviewed_no_forced_decimation' if resource_ok and manual['status']=='passed' else 'pending_cost_or_visual_review'
        specific={}
        if inheritance and (aid=='axel_guild_repaired' or has_lights or has_hinges):specific['scope_inheritance']=inheritance
        if tower:specific['tower_lod']=dict(report=str(ROOT/'final_tower_lod/game_review.json'),current_source_match=tower.get('sha256')==current_sha,passed=tower.get('passed'),lod_triangles=tower.get('lod_triangles'))
        if has_hinges or has_lights:specific['shared_runtime']=dict(report=str(runtime_path),report_sha256=digest(runtime_path),
            source_sha256=runtime_report.get('source_sha'),current_or_proven_scope_implementation_passed=runtime_ok,light_sockets=runtime_report.get('light_sockets'),
            component_count=runtime_report.get('component_count'),moving_meshes=runtime_report.get('moving_meshes'),
            magic_stone_self_shadow_exclusions=runtime_report.get('magic_stone_self_shadow_exclusions'),lit_lights=runtime_report.get('lit_lights'),
            note='Counts describe the complete current guild scene exercising shared fixtures, not each individual prop. Per-item HTTP independently covers imported hinges and persistence.')
        if has_lights:specific['actual_lighting']=dict(report=str(lighting_path),source_sha256=lighting_report.get('identity',{}).get('sha256'),current_or_proven_scope_implementation_passed=lighting_ok,manual_decision=lighting_manual,note='Real nearby-light controller and visually inspected day/night reception are separate from emissive-material/static gallery acceptance; formal map GI remains pending.')
        if aid=='axel_guild_repaired':specific['optimization_AB']=dict(report=str(optimization_path),source_sha256=optimization_report.get('source_sha256'),current_or_proven_scope_manual_passed=optimization_ok)
        record=dict(id=aid,source_path=row['path'],source_sha256=current_sha,manifest_sha256=row['sha256'],manifest_match=current_sha==row['sha256'],source_master=row['source_master'],
            source_resource_report=str(resource_path),source_resource_sha256=digest(resource_path),source_bytes=res.get('source_bytes'),
            costs={k:res.get(k) for k in ['unique_mesh_triangles','instanced_all_lod_triangles','mesh_nodes','material_count','unique_decoded_rgba_bytes','estimated_rgba8_full_mips_bytes']},
            native_import=imported,matching_galleries=matches,manual_visual=manual,
            specific_tests=specific,
            stages={'source_resource_audit':'passed' if resource_ok else 'pending_or_failed','resource_with_native_cost':'passed' if resource_ok and native_cost_ok else 'pending',
                'current_SHA_native_gallery':'passed' if any(g['passed'] and g['gallery_completed'] for g in matches) else 'pending',
                'manual_reference_visual':manual['status'],'production_import_and_HTTP':'passed' if pipeline_ok else 'pending',
                'runtime_component_semantics':(('passed_scope_inherited' if aid=='axel_guild_repaired' and inheritance else 'passed') if activity_ok else 'pending') if has_hinges else 'not_applicable',
                'runtime_lighting':light_status,'optimization_review':optimization_status,
                'formal_map_integration':'pending; no formal publication in this review'},
            measured_RSS_VRAM=None,budget_scope='Resource counts/decoded images and conservative admission only; no per-model measured RSS/VRAM claim.',
            optimization_assessment=res.get('optimization_assessment'),formal_library_modified=False,production_map_modified=False)
        save(ROOT/'acceptance'/(aid+'.json'),record);result.append(record)
    stages={k:dict(collections.Counter(r['stages'][k] for r in result)) for k in result[0]['stages']}
    source_sum=sum(r['source_bytes'] or 0 for r in result)
    natives=[r['native_import'] for r in result if r['native_import']]
    summary=dict(timestamp=datetime.datetime.now().astimezone().isoformat(),source_manifest_sha256=digest(ART/'repair_manifest.json'),
        assets=53,expected_generator=expected_generator,stages=stages,source_bytes_sum=source_sum,
        exact_current_native_items=len(natives),native_bytes_sum=sum(n.get('native_manifest',{}).get('bytes',0) for n in natives),
        budget_warning='Native byte sum is disk storage only; per-item conservative admission is not aggregate scene RSS/VRAM. Gallery success does not establish manual reference acceptance.',
        items=[dict(id=r['id'],source_sha256=r['source_sha256'],report=str(ROOT/'acceptance'/(r['id']+'.json')),stages=r['stages']) for r in result],
        formal_library_modified=False,production_map_modified=False)
    save(ROOT/'acceptance/index.json',summary)
    write_overview(result,summary)
    inventory_path=ROOT/'today_model_inventory.json';inventory=load(inventory_path)
    indexed={r['id']:r for r in result};manifest_by_id={r['asset_id']:r for r in source_rows}
    street_manifest=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json');street=load(street_manifest);street_rows={r['id']:r for r in street.get('assets',[])}
    for row in inventory.get('assets',[]):
        aid=row['id']
        if aid in indexed:
            r=indexed[aid];baseline=Path(row['baseline_path']);changed=digest(baseline)!=r['source_sha256']
            row.update(path=r['source_path'],sha256=r['source_sha256'],source_bytes=r['source_bytes'],snapshot_manifest_sha256=r['manifest_sha256'],manifest_matches=r['manifest_match'],
                classification='modified_existing' if changed else 'unchanged_copy',count_as_today_authored_model=changed,source_master=r['source_master'],
                final_acceptance_report=str(ROOT/'acceptance'/(aid+'.json')),report_stage=r['stages'],
                open_issues=['Final acceptance stages are recorded independently; formal map integration is still pending.'] + ([] if changed else ['Unchanged source bytes; prior visual evidence may be reused only with its exact matching SHA.']))
            row['author_change_evidence']['reference_changed']=manifest_by_id[aid].get('reference_changed',True)
        elif aid in street_rows:
            r=street_rows[aid];p=Path(r['path']);row.update(path=str(p),sha256=digest(p),source_bytes=p.stat().st_size,source_master=r['source_blend'],manifest_matches=digest(p)==r['sha256'])
            row['author_change_evidence']['manifest']=str(street_manifest)
            street_root=REPO/'review_artifacts/required_street_recheck_20261013'
            resource_report=street_root/aid/'resource_review.json';street_resource=load(resource_report)
            resource_ok=street_resource.get('sha256')==row['sha256'] and street_resource.get('issues')==[]
            gallery_report=street_root/aid/'report.json';street_gallery=load(gallery_report)
            gallery_match=street_gallery.get('identity',{}).get('sha256')==row['sha256']
            row['report_stage']={'resource':'passed' if resource_ok else 'pending current-SHA resource report','appearance':'see independently recorded current-SHA reference decisions','pipeline':'current revision GPU/HTTP pending or separately reported','formal_integration':'pending'}
            row['open_issues']=['Only exact-current-SHA evidence counts; street reference reviewer records final visual and native/HTTP decisions independently.']
            row['existing_report']={'path':str(gallery_report),'current_source_match':gallery_match,'resource_report':str(resource_report),'resource_current_and_passed':resource_ok}
            street_acceptance_path=street_root/'acceptance'/(aid+'.json');street_acceptance=load(street_acceptance_path)
            if street_acceptance.get('source_sha256')==row['sha256'] and isinstance(street_acceptance.get('status'),dict):
                statuses=street_acceptance['status']
                row['final_acceptance_report']=str(street_acceptance_path)
                row['report_stage']={key:value.get('status','pending') for key,value in statuses.items() if isinstance(value,dict)}
                row['open_issues']=[key+': '+str(value.get('note','pending evidence')) for key,value in statuses.items()
                    if isinstance(value,dict) and value.get('status') not in ('passed','not_applicable')]
                row['existing_report']['acceptance_sha256']=digest(street_acceptance_path)
    counts=collections.Counter(r['classification'] for r in inventory['assets']);n=sum(r['count_as_today_authored_model'] for r in inventory['assets'])
    inventory['counts'].update(today_new_or_author_modified_files=n,guild_modified_existing=counts['modified_existing'],guild_unchanged_copies=counts['unchanged_copy'],classification=dict(counts))
    inventory.update(snapshot_at=datetime.datetime.now().astimezone().isoformat(),active_build_caveat='Both guild repair_v3 and street review_v2 are frozen for this acceptance snapshot. Only the recorded current SHA and compatible implementation evidence count; scoped inheritance preserves the original earlier SHA and its explicit proof. This is candidate acceptance, not formal map publication.',
        method=[m for m in inventory['method'] if '34 copied' not in m and not m.startswith('Guild compared every delivery against repair_v2 actual SHA:')]+[f'Guild compared every delivery against repair_v2 actual SHA: {counts["unchanged_copy"]} remain unchanged.'],
        targeted_followup=['Use each current-SHA acceptance report for resource, visual, runtime and isolated editor status. Keep any remaining formal integration stage separate.','Re-review only affected items after a subsequent source or implementation change; preserve earlier evidence without relabelling its SHA.'])
    save(inventory_path,inventory)
    print(json.dumps(dict(stages=stages,inventory_counts=inventory['counts']),ensure_ascii=False))


if __name__=='__main__':main()
