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

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=DEFAULT)
    parser.add_argument('--no-doc', action='store_true')
    args = parser.parse_args()
    out = args.out
    names = ['build.json', 'runtime/result.json', 'visual_acceptance.json', 'publication.json',
             'housing_recipe.json', 'house_templates.json', 'house_template_native_audit.json']
    receipts = {n: read(out / n) for n in names}
    build, runtime, visual, publication = (receipts[n] for n in names[:4])
    recipe, index, native = (receipts[n] for n in names[4:])
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
    pub_evidence = publication.get('evidence', {})
    publication_ok = (publication.get('published') is True and publication.get('status') == 'passed'
                      and publication.get('failures') == 0 and publication.get('candidate_sha256') == candidate_sha
                      and bool(publication.get('formal_sha256'))
                      and sha(publication.get('formal_path', '')) == publication.get('formal_sha256')
                      and all(pub_evidence.get(k) == sha(out / n) for k, n in
                              [('build_sha256', 'build.json'), ('runtime_sha256', 'runtime/result.json'),
                               ('visual_sha256', 'visual_acceptance.json')])
                      and bool(publication.get('checks')) and all(r.get('passed') is True for r in publication['checks']))
    models = []
    for tid in used:
        template = templates.get(tid, {})
        review_path = out / 'templates' / (tid + '.review.json')
        review = read(review_path)
        native_row = native_rows.get(tid, {})
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
                 'visual_evidence': images}
        models.append(model)
        if review:
            review.setdefault('authoring_stages', review.get('stages', {}))
            review['stages'] = {k: v['status'] for k, v in stages.items()}
            review['layout_acceptance'] = model
            review_path.write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding='utf8')
    completed = bool(models and all(all(v['status'] == 'passed' for v in m['stages'].values()) for m in models))
    report = {'status': 'passed' if completed else 'pending', 'planned_house_count': len(planned),
              'built_house_count': len(built), 'reference_shots': sorted({h['shot'] for h in planned}),
              'candidate_sha256': candidate_sha, 'candidate_current': candidate_current,
              'formal_published_receipt_verified': publication_ok, 'formal_sha256': publication.get('formal_sha256'),
              'receipts': {n: {'path': str(out/n), 'sha256': sha(out/n), 'present': bool(receipts[n])} for n in names},
              'used_templates': models, 'reviewed_images': list(checked_images.values()),
              'scope_limits': ['14 residences across S1/S2/S10/S12; not full-town background infill or complete shot restoration.',
                               'No repeated component-house interior tests; runtime scope is outdoor approaches and current layout.',
                               pole_note,
                               'Native geometry/surface/texture budgets are distinct from measured runtime draw calls or VRAM.'],
              'visual_schema': {'template_reviews': [{'template_id': '...', 'template_sha256': '...', 'passed': True,
                               'notes': 'Actual visual conclusion', 'image_paths': ['absolute .webp path']}],
                               'images': [{'path': 'absolute .webp path', 'sha256': '...', 'quality': 90, 'reviewed': True}]}}
    (out/'house_layout_review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    if not args.no_doc:
        stage_names = {'passed': '通过', 'pending': '待验', 'failed': '未通过'}
        lines = ['# 阿克塞尔参考住宅布局（2026-10-14）', '',
                 f'计划 14 栋住宅，对应 S1、S2、S10、S12 四组参考。当前构建记录包含 {len(built)} 栋；整体结论：{stage_names[report["status"]]}。', '',
                 ('正式原子发布与重开已核对。正式文件 SHA：`'+str(report['formal_sha256'])+'`。' if publication_ok else '本页当前记录候选制作与验收阶段，尚无完整正式接入通过结论。'), '',
                 '住宅均为居民用途，保留整栋窗型、楼层/屋顶隐藏和活动门窗语义。S1 使用规整小砌块外墙与闭合留门院墙；S2 低宅有真实圆山墙窗；S12 采用真实通高拱洞、独立双柱外拱和山墙雕饰。不可见部分与游戏尺寸属于项目补充设计。', '',
                 '本轮没有补齐整城背景，也不能视为四个镜头完整还原。既有组件房室内不重复测试；运行验收覆盖本轮室外入口和通路。', '',
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
