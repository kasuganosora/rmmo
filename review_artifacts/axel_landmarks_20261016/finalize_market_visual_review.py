"""Record the 28 candidate frames actually viewed by the church reviewer.

Does not rewrite automatic reports, source assets, catalog, or comparison proofs.
Acceptance is for the lossless payload replacement, not baseline art completion.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import time

ROOT = Path('D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016/gpu_ab02')
ART = Path('D:/code/rmmo_runtime/art_sources/axel_market_optimization_20261016')
VIEWS = ['near', 'medium', 'far', 'back', 'cloth_detail', 'goods_detail', 'structure_detail']
ISSUES = {
    'pottery': ['陶罐侧轮廓有明显分段折线，泥釉和表面微变化不足。'],
    'scroll': ['展开纸面厚度偏大，统一浅色与规则横线不满足最终近景纸张细化。'],
    'potion': ['瓶体透明/折射层次弱、颜色均一，近景仍有塑料感；与基线一致。'],
    'ore': ['矿石及蓝色晶体为明显的无表面纹理三角切面造型，不作为最终写实矿石验收。'],
}
COMMON = ['棚布大面褶皱与张力层次较弱。', '木材纹理重复明显，货品摆列机械；留待布局后统一细化。']

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def put(path, value):
    assert not path.exists(), f'Immutable evidence already exists: {path}'
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

status = read(ROOT / 'status.json')
assert status['state'] == 'completed_awaiting_visual_inspection'
assert len(status['jobs']) == 12 and all(j['returncode'] == 0 for j in status['jobs'])
query = "Get-CimInstance Win32_Process | Where-Object {$_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
processes = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', query], capture_output=True, text=True, check=True).stdout.strip()
assert not processes, 'Another non-headless Godot process is active'
summary = read(ART / 'summary.json')
rows = []
acceptance = {'version': 1, 'visual_accepted': True, 'scope': 'Lossless payload replacement relative to unchanged baseline only', 'final_art_accepted': False, 'assets': {}}
all_receipts = []
for item in summary['rows']:
    asset = item['asset']
    folder = ROOT / asset
    base, candidate, compare = [read(folder / (case + '.json')) for case in ['baseline', 'candidate', 'compare']]
    assert all(report['passed'] and not report['failures'] for report in [base, candidate, compare])
    assert len(compare['images']) == 7 and all(frame['exact'] and frame['changed_pixel_fraction'] == 0 for frame in compare['images'])
    assert sha(Path(item['source'])) == item['source_sha256']
    assert sha(Path(item['candidate'])) == item['candidate_sha256']
    receipts = read(folder / 'image_upload_receipts.json')
    assert len(receipts) == 14
    for receipt in receipts:
        p = Path(receipt['path'])
        assert receipt['quality'] == 90 and receipt['lossless'] is False
        assert receipt['dimensions'] == [1400, 1000] and sha(p) == receipt['sha256']
        raw = p.read_bytes()
        assert raw[:4] == b'RIFF' and raw[8:12] == b'WEBP'
    all_receipts += receipts
    viewed = []
    for view in VIEWS:
        path = folder / 'candidate' / (view + '.webp')
        viewed.append({'view': view, 'path': str(path), 'sha256': sha(path), 'actually_viewed': True})
    baseline_viewed = folder / 'baseline/goods_detail.webp'
    acceptance['assets'][asset] = {
        'candidate_sha256': item['candidate_sha256'],
        'compare_sha256': sha(folder / 'compare.json'),
        'visual_accepted': True,
        'viewed_image_sha256': [v['sha256'] for v in viewed],
        'final_art_accepted': False,
        'baseline_limitations': ISSUES[asset] + COMMON,
    }
    rows.append({
        'asset': asset, 'source_sha256': item['source_sha256'], 'candidate_sha256': item['candidate_sha256'],
        'optimization_visual_accepted': True, 'final_art_accepted': False,
        'native_pipeline_accepted': True, 'formal_library': 'PENDING authorized publisher', 'formal_map': 'NOT modified',
        'viewed_candidate_images': viewed,
        'viewed_baseline_images': [{'path': str(baseline_viewed), 'sha256': sha(baseline_viewed), 'actually_viewed': True}],
        'remaining_baseline_images': 'Not separately viewed; all seven PNG comparisons are exact and corresponding Q90 SHA matches candidate.',
        'observations': ['近中远轮廓、货品数量、棚边、斜撑、投影、木纹及货品颜色与基线无变化。'] + ISSUES[asset] + COMMON,
        'source_bytes': item['source_bytes'], 'candidate_bytes': item['candidate_bytes'],
        'native_bytes_baseline': base['native']['native_bytes'], 'native_bytes_candidate': candidate['native']['native_bytes'],
        'native_sha256': candidate['native']['payload_sha256'], 'native_stats': candidate['native']['stats'],
        'conservative_admission_bytes': candidate['native']['estimate']['estimated_bytes'],
        'source_triangles': item['candidate_stats']['unique_mesh_triangles'],
        'draw_calls_by_view': {s['name']: s['draw_calls'] for s in candidate['screenshots']},
        'lod_decision': '本轮仅去除不可达及重复载荷，几何/LOD不变。先保留现有近中远轮廓；多实例正式地图profile若证实几何瓶颈，再按同镜头验证LOD，不为压缩比例进一步削面。',
        'compare': {'path': str(folder / 'compare.json'), 'sha256': sha(folder / 'compare.json'), 'exact_frames': 7},
    })
put(ROOT / 'visual_review.json', {
    'version': 1, 'reviewer': '/root/blender_church', 'timestamp': time.time(),
    'scope': 'Existing market assets: lossless payload optimization, not new final realism acceptance',
    'resource_audit': 'PASS CPU reachable graph and actual native identities',
    'visual_optimization': 'PASS 28 candidate Q90 actual views and four baseline goods detail actual views; 28 fixed-frame PNG comparisons exact',
    'pipeline': 'PASS isolated production native compile/read, picking/walk collider input identity, private library save/reopen',
    'integration': 'PENDING publisher formal library and real HTTP checks; no production map edit',
    'final_art_accepted': False, 'baseline_art_backlog_preserved': True,
    'no_performance_claim': 'No process RSS, dedicated VRAM, FPS, city profile or newly implemented wind/animation measured. Native file sizes and active texture budgets remain effectively unchanged.',
    'source_bytes_total': summary['source_bytes_total'], 'candidate_bytes_total': summary['candidate_bytes_total'], 'saved_bytes_total': summary['saved_bytes_total'],
    'upload_compression': {'images': len(all_receipts), 'source_png_bytes': sum(r['source_bytes'] for r in all_receipts), 'webp_q90_bytes': sum(r['bytes'] for r in all_receipts), 'dimensions': [1400, 1000], 'lossless': False, 'quality': 90},
    'assets': rows,
})
acceptance['visual_review_sha256'] = sha(ROOT / 'visual_review.json')
put(ROOT / 'acceptance.json', acceptance)
put(ROOT / 'gpu_release.json', {'version': 1, 'owner': '/root/blender_church', 'state': 'released_to_blender_watermill', 'active_nonheadless_godot': [], 'timestamp': time.time(), 'acceptance_sha256': sha(ROOT / 'acceptance.json')})
print(json.dumps({'acceptance': str(ROOT / 'acceptance.json'), 'sha256': sha(ROOT / 'acceptance.json'), 'visual_review_sha256': sha(ROOT / 'visual_review.json'), 'gpu_released': True}, ensure_ascii=False))
