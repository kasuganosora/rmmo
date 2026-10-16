"""Aggregate pinned house-layout evidence; screenshots alone never grant approval."""
from pathlib import Path
import argparse
import hashlib
import json

DEFAULT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')
DOC = Path(__file__).resolve().parents[1] / 'docs/axel_town_house_layout_20261014.md'

def sha(path):
    p = Path(path)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None

def read(path):
    p = Path(path)
    if not p.is_file():
        return {}
    try:
        value = json.loads(p.read_text(encoding='utf8'))
        return value if isinstance(value, dict) else {}
    except (ValueError, OSError):
        return {}

def state(passed, reason, failed=False):
    return {'status': 'passed' if passed else 'failed' if failed else 'pending', 'reason': reason}

def template_evidence(out, template, native_rows):
    """Resolve evidence beside the active template; never activate a candidate.

    Payload/SHA checks in the caller still reject stale or mismatched evidence.
    Other templates keep their independent original reports and audit rows.
    """
    tid = template.get('id', '')
    source = Path(template.get('loaded_path', ''))
    sibling = source.with_suffix('.review.json') if source.suffix else None
    review_path = Path(template['review_path']) if template.get('review_path') else (
        sibling if sibling and sibling.is_file() else out / 'templates' / (tid + '.review.json'))
    audit_path = Path(template['native_audit_path']) if template.get('native_audit_path') else (
        source.parent.parent / 'house_template_native_audit.json')
    audit = read(audit_path)
    row = next((r for r in audit.get('templates', []) if r.get('id') == tid), None)
    if row is None:
        row = native_rows.get(tid, {})
        audit_path = out / 'house_template_native_audit.json'
    return review_path, read(review_path), row, audit_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=DEFAULT)
    parser.add_argument('--no-doc', action='store_true')
    args = parser.parse_args()
    out = args.out
    names = ['build.json', 'runtime/result.json', 'visual_acceptance.json', 'publication.json',
             'housing_recipe.json', 'house_templates.json', 'house_template_native_audit.json',
             'watercourse_acceptance.json']
    receipts = {n: read(out / n) for n in names}
    build, runtime, visual, publication = (receipts[n] for n in names[:4])
    recipe, index, native = (receipts[n] for n in names[4:7])
    watercourse = receipts['watercourse_acceptance.json']
    planned = recipe.get('houses', [])
    built = build.get('houses', [])
    near_post = next((r for r in build.get('props', {}).get('placements', [])
                      if r.get('key') == 'festival/lane_near_south'), {})
    has_green_post = near_post.get('asset_label') == '绿色金丝带彩柱' and bool(near_post.get('asset_sha256'))
    pole_note = ('S1 桥左蓝柱、桥右浅原木柱保持用户修正。S2 近南柱已使用正式库绿色原木素材。'
                 if has_green_post else
                 'S1 桥左蓝柱、桥右浅原木柱保持用户修正。S2 近南绿色柱尚未接入正式候选。')
    templates = {r['id']: r for r in index.get('templates', [])}
    native_rows = {r['id']: r for r in native.get('templates', [])}
    used = sorted({r['template_id'] for r in planned})
    candidate_sha = build.get('candidate_sha256')
    candidate_current = bool(candidate_sha and sha(build.get('candidate', '')) == candidate_sha)
    build_ok = (build.get('phase') == 'candidate_complete' and build.get('failures') == 0 and candidate_current
                and {r['id'] for r in built} == {r['id'] for r in planned} and bool(planned))
    runtime_ok = (runtime.get('phase') == 'complete' and runtime.get('status') == 'passed'
                  and runtime.get('failures') == 0 and runtime.get('map_sha256') == candidate_sha
                  and runtime.get('build_sha256') == sha(out / 'build.json') and build_ok)
    run_houses = {r['id']: r for r in runtime.get('houses', [])}
    visual_pin = bool(visual.get('passed') is True and visual.get('candidate_sha256') == candidate_sha and candidate_current)
    visual_rows = {r.get('template_id', r.get('id')): r for r in visual.get('template_reviews', [])}
    image_rows = {r.get('path'): r for r in visual.get('images', []) if isinstance(r, dict)}
    checked_images = {}
    for path, image in image_rows.items():
        preparation = read(str(path) + '.review-image.json') if path else {}
        valid = bool(path and Path(path).suffix.lower() == '.webp' and image.get('reviewed') is True
                     and image.get('sha256') and sha(path) == image['sha256']
                     and image.get('quality') == 90
                     and preparation.get('sha256') == image['sha256']
                     and preparation.get('quality') == 90 and preparation.get('lossless') is False)
        checked_images[path] = {**image, 'valid': valid}
    water_views = watercourse.get('views', [])
    required_water_views = {'s12_stream_confluence', 's12_stream_crossing', 's12_stream_rapid',
                            's12_watercourse_overview', 's12_watercourse_source'}
    checked_water_views = []
    for view in water_views:
        image_path = view.get('path', '')
        encoding = read(image_path + '.review-image.json') if image_path else {}
        valid = bool(view.get('passed') is True and Path(image_path).suffix.lower() == '.webp'
                     and view.get('sha256') and sha(image_path) == view['sha256']
                     and encoding.get('sha256') == view['sha256']
                     and encoding.get('quality') == 90 and encoding.get('lossless') is False)
        checked_water_views.append({**view, 'valid': valid})
    watercourse_ok = bool(watercourse.get('passed') is True and candidate_current
                         and watercourse.get('candidate_sha256') == candidate_sha
                         and build.get('watercourse', {}).get('continuous') is True
                         and len(checked_water_views) == len(required_water_views)
                         and {v.get('id') for v in checked_water_views} == required_water_views
                         and all(v['valid'] for v in checked_water_views))
    pub_evidence = publication.get('evidence', {})
    publication_ok = (publication.get('published') is True and publication.get('status') == 'passed'
                      and publication.get('failures') == 0 and publication.get('candidate_sha256') == candidate_sha
                      and bool(publication.get('formal_sha256'))
                      and sha(publication.get('formal_path', '')) == publication.get('formal_sha256')
                      and all(pub_evidence.get(k) == sha(out / n) for k, n in
                              [('build_sha256', 'build.json'), ('runtime_sha256', 'runtime/result.json'),
                               ('visual_sha256', 'visual_acceptance.json'),
                               ('watercourse_sha256', 'watercourse_acceptance.json')])
                      and watercourse_ok
                      and bool(publication.get('checks')) and all(r.get('passed') is True for r in publication['checks']))
    # Reusing approved library assets is a placement review, not a new model review.
    landmark_names = {'landmark/guild': '冒险者公会', 'landmark/alarm': '公会告警塔'}
    landmark_build = build.get('landmarks', {})
    landmark_placements = landmark_build.get('placements', [])
    landmark_runtime = runtime.get('landmarks', [])
    landmark_ids = [r.get('id') for r in landmark_placements]
    landmark_identity_ok = bool(
        len(landmark_placements) == len(landmark_names)
        and landmark_build.get('count') == len(landmark_placements)
        and {r.get('key') for r in landmark_placements} == set(landmark_names)
        and len(set(landmark_ids)) == len(landmark_ids) and all(landmark_ids)
        and all(r.get('asset_sha256') and sha(r.get('asset_path', '')) == r['asset_sha256']
                for r in landmark_placements))
    landmark_native_ok = bool(build_ok and landmark_identity_ok)
    landmark_runtime_ok = bool(
        runtime_ok and landmark_native_ok and len(landmark_runtime) == len(landmark_placements)
        and {(r.get('key'), r.get('id')) for r in landmark_runtime}
            == {(r.get('key'), r.get('id')) for r in landmark_placements}
        and all(len(r.get('walks', [])) == 2 and all(w.get('passed') is True for w in r['walks'])
                and r.get('samples') and all(s.get('passed') is True for s in r['samples'])
                for r in landmark_runtime))
    landmark_view_ids = {'macro_guild_forecourt', 'macro_guild_alarm_context'}
    landmark_views = []
    for view_id in sorted(landmark_view_ids):
        matches = [image for image in checked_images.values()
                   if image.get('id') == view_id or image.get('camera', {}).get('id') == view_id
                   or Path(image.get('path') or '').name in {view_id + '.webp', view_id + '.upload.webp'}]
        landmark_views.append({'id': view_id, 'images': matches,
                               'valid': bool(matches and all(image['valid'] for image in matches))})
    landmark_visual_ok = bool(visual_pin and landmark_native_ok
                              and visual.get('landmark_macro_layout_passed') is True
                              and all(view['valid'] for view in landmark_views))
    landmark_stages = {
        'native_layout': state(landmark_native_ok, 'Completed native candidate contains both reused library assets with unique instance IDs and matching file SHAs.' if landmark_native_ok else 'Completed candidate or both pinned library placements pending.'),
        'outdoor_runtime': state(landmark_runtime_ok, 'Both saved landmark approaches have ground/capsule clearance and two successful exterior walks.' if landmark_runtime_ok else 'Pinned outdoor runtime or exact landmark approach coverage pending.'),
        'visual': state(landmark_visual_ok, 'Explicit candidate-pinned landmark layout acceptance and both reviewed Q90 views.' if landmark_visual_ok else 'Candidate-pinned landmark decision or reviewed Q90 views pending.', visual.get('landmark_macro_layout_passed') is False),
        'formal_integration': state(publication_ok and landmark_native_ok and landmark_runtime_ok and landmark_visual_ok, 'Current publication evidence and actual formal SHA verify the accepted landmark placements.' if publication_ok and landmark_native_ok and landmark_runtime_ok and landmark_visual_ok else 'Formal publication or upstream landmark layout evidence pending.')}
    landmark_ok = all(s['status'] == 'passed' for s in landmark_stages.values())
    landmark_layout = {'status': 'passed' if landmark_ok else 'pending',
                       'scope': 'Placement of two previously delivered formal-library models; public exteriors only, not new model production or interior revalidation.',
                       'expected_count': len(landmark_names), 'built_count': len(landmark_placements),
                       'candidate_sha256': candidate_sha, 'placements': landmark_placements,
                       'runtime_approaches': landmark_runtime, 'views': landmark_views, 'stages': landmark_stages}
    models = []
    for tid in used:
        template = templates.get(tid, {})
        review_path, review, native_row, native_audit_path = template_evidence(out, template, native_rows)
        source_path = template.get('loaded_path', '')
        actual_sha = sha(source_path)
        source_data = read(source_path)
        actual_payloads = {r['house_prefab']['sha256'] for r in source_data.get('records', []) if 'house_prefab' in r}
        resource_ok = bool(actual_sha and actual_sha == template.get('sha256') == review.get('source_sha256')
                           and native_row and not native_row.get('errors')
                           and actual_payloads == {r['sha256'] for r in native_row.get('payloads', [])}
                           and actual_payloads == {r['sha256'] for r in review.get('native_payloads', [])}
                           and review.get('textures') and all(not r.get('missing') and sha(p) == r.get('sha256')
                                                             for p, r in review['textures'].items()))
        houses = [h for h in planned if h['template_id'] == tid]
        walks_ok = all(h['id'] in run_houses and len(run_houses[h['id']].get('walks', [])) == 2
                       and all(w.get('passed') is True for w in run_houses[h['id']]['walks']) for h in houses)
        decision = visual_rows.get(tid, {})
        images = decision.get('image_paths', [])
        visual_ok = bool(visual_pin and decision.get('passed') is True and decision.get('notes')
                         and decision.get('template_sha256') == actual_sha and images
                         and all(checked_images.get(p, {}).get('valid') for p in images))
        stages = {
            'resource': state(resource_ok, 'Actual template SHA, decoded native payload identities and parsed texture costs match.' if resource_ok else 'Resource identity/cost evidence missing or stale.'),
            'visual': state(visual_ok, 'Explicit per-template visual decision with reviewed, hashed WebP evidence.' if visual_ok else 'Per-template visual decision or matching reviewed WebP evidence pending.', decision.get('passed') is False),
            'pipeline': state(build_ok and runtime_ok and walks_ok, 'Pinned native candidate save/reopen and two outdoor entrance approaches per used house.' if build_ok and runtime_ok and walks_ok else 'Candidate completion, pinned runtime or outdoor house coverage pending.', bool(build.get('failures', 0) or runtime.get('failures', 0))),
            'formal_integration': state(publication_ok and build_ok and runtime_ok and visual_ok, 'Atomic publication/reopen receipt and actual formal file SHA verified.' if publication_ok and build_ok and runtime_ok and visual_ok else 'Formal publication/reopen or upstream template evidence pending.')}
        model = {'template_id': tid, 'template_sha256': actual_sha, 'house_ids': [h['id'] for h in houses],
                 'shots': sorted({h['shot'] for h in houses}), 'review_path': str(review_path), 'stages': stages,
                 'native_audit_path': str(native_audit_path), 'native_audit_sha256': sha(native_audit_path),
                 'visual_evidence': images}
        models.append(model)
        if review:
            review.setdefault('authoring_stages', review.get('stages', {}))
            review['stages'] = {k: v['status'] for k, v in stages.items()}
            review['layout_acceptance'] = model
            review_path.write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding='utf8')
    completed = bool(watercourse_ok and landmark_ok and models and all(all(v['status'] == 'passed' for v in m['stages'].values()) for m in models))
    report = {'status': 'passed' if completed else 'pending', 'planned_house_count': len(planned),
              'built_house_count': len(built), 'reference_shots': sorted({h['shot'] for h in planned if h['shot'].startswith('S')}),
              'macro_house_count': sum(h['shot'].startswith('MACRO_') for h in planned),
              'candidate_sha256': candidate_sha, 'candidate_current': candidate_current,
              'formal_published_receipt_verified': publication_ok, 'formal_sha256': publication.get('formal_sha256'),
              'receipts': {n: {'path': str(out/n), 'sha256': sha(out/n), 'present': bool(receipts[n])} for n in names},
              'used_templates': models, 'reviewed_images': list(checked_images.values()),
              'landmark_layout': landmark_layout,
              'watercourse': {'status': 'passed' if watercourse_ok else 'pending',
                              'actual_length_m': build.get('watercourse', {}).get('actual_length_m'),
                              'views': checked_water_views,
                              'reason': 'Pinned continuous course and five reviewed Q90 views.' if watercourse_ok else 'Continuous-course receipt or pinned five-view visual evidence pending.'},
              'scope_limits': [f'{len(planned)} planned residences, including S1/S2/S10/S12 and any recorded macro street infill; not full-town completion or complete shot restoration.',
                               'Guild and alarm tower reuse existing formal-library models; their new placement acceptance is separate from original model delivery.',
                               'Guardhouse, church and mill are not built in this new town. New town walls, gates and water gates remain to be laid out.',
                               'No repeated component-house interior tests; runtime scope is outdoor approaches and current layout.',
                               pole_note,
                               'Native geometry/surface/texture budgets are distinct from measured runtime draw calls or VRAM.'],
              'visual_schema': {'template_reviews': [{'template_id': '...', 'template_sha256': '...', 'passed': True,
                               'notes': 'Actual visual conclusion', 'image_paths': ['absolute .webp path']}],
                               'images': [{'path': 'absolute .webp path', 'sha256': '...', 'quality': 90, 'reviewed': True}]}}
    (out/'house_layout_review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    if not args.no_doc:
        stage_names = {'passed': '通过', 'pending': '待验', 'failed': '未通过'}
        landmark_labels = '、'.join(landmark_names.get(r.get('key'), str(r.get('key'))) for r in landmark_placements) or '待构建记录提供'
        lines = ['# 阿克塞尔参考住宅布局（2026-10-14 建档，2026-10-16 更新）', '',
                 f'计划 {len(planned)} 栋住宅，包含 S1、S2、S10、S12 四组参考及 {report["macro_house_count"]} 栋街区补充住宅。当前构建记录包含 {len(built)} 栋；整体结论：{stage_names[report["status"]]}。', '',
                 ('正式原子发布与重开已核对。正式文件 SHA：`'+str(report['formal_sha256'])+'`。' if publication_ok else '本页当前记录候选制作与验收阶段，尚无完整正式接入通过结论。'), '',
                 '住宅均为居民用途，保留整栋窗型、楼层/屋顶隐藏和活动门窗语义。S1 使用规整小砌块外墙与闭合留门院墙；S2 低宅有真实圆山墙窗；S12 采用真实通高拱洞、独立双柱外拱和山墙雕饰。不可见部分与游戏尺寸属于项目补充设计。', '',
                 '本轮没有补齐整城背景，也不能视为四个镜头完整还原。既有组件房室内不重复测试；运行验收覆盖本轮室外入口和通路。', '',
                 '用户于 2026-10-15 调整顺序：先完成水系、道路桥梁、功能区和住宅通路的整体布局，再统一调整植被密度、装饰与材质细节。当前街区扩展复用既有完整户型，不以无用途空房填满地图。', '',
                 f'地标布局单独验收：目标 2 处，当前构建记录 {len(landmark_placements)} 处（{landmark_labels}）。复用已交付的正式资源库模型，不代表新制作模型；原生布局、室外通路、画面、正式接入依次为：'+
                 '、'.join(stage_names[landmark_stages[k]['status']] for k in ['native_layout', 'outdoor_runtime', 'visual', 'formal_integration'])+'。公会只验公共外部通路，告警塔不声明具有可进入的室内。', '',
                 '新城的警卫处、教会和磨坊尚未建设；城墙、城门及水关仍待布局。本轮住宅与两处地标阶段通过也不等于全城完成，五处特殊建筑保留区与公会前玩家摆摊留白继续保留。', '',
                 'S12 连续支流水系：'+stage_names[report['watercourse']['status']]+'；原生采样实际长度：'+(str(report['watercourse']['actual_length_m'])+' 米' if report['watercourse']['actual_length_m'] is not None else '待构建记录提供')+'。五处验收包括上游、全线、小桥、急流和汇口。', '',
                 pole_note+'三组跨街旗串复用原生风动素材，实际挂点与风姿态以本轮场景证据为准。', '',
                 '| 使用模板 | 资源 | 画质 | 管线 | 正式接入 |', '|---|---|---|---|---|']
        for m in models:
            lines.append('| '+m['template_id']+' | '+' | '.join(stage_names[m['stages'][k]['status']] for k in ['resource','visual','pipeline','formal_integration'])+' |')
        lines += ['', '模型验收图在查看前采用原尺寸有损 WebP quality 90；图像存在不等于视觉通过。每条已审图必须保留实际路径、SHA 和逐模板结论。精确像素比较另用明确标注的无损 WebP。', '',
                  f'- [汇总及完整证据索引]({(out/"house_layout_review.json").as_posix()})',
                  f'- [实际模板与成本]({(out/"house_template_resource_inventory.json").as_posix()})',
                  f'- [道具净空]({(out/"prop_clearance_audit.json").as_posix()})',
                  f'- [旗串挂点与净高]({(out/"festival_span_audit.json").as_posix()})']
        for n in names[:4]:
            lines.append(f'- [{n}]({(out/n).as_posix()}) — '+('已记录' if receipts[n] else '待生成'))
        for image in checked_images.values():
            lines.append(f'- [验收图：{Path(image["path"]).name}]({Path(image["path"]).as_posix()}) — '+('已核对查看记录与 SHA' if image['valid'] else '待核对'))
        DOC.write_text('\n'.join(lines)+'\n', encoding='utf8')
    print(json.dumps({'status': report['status'], 'used_templates': len(models), 'planned_houses':len(planned), 'built_houses':len(built), 'published':publication_ok}))

if __name__ == '__main__':
    main()
