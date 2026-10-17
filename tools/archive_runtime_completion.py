"""Archive accepted scalar evidence; generated assets/media remain external."""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
EXTERNAL = Path('D:/code/rmmo_runtime/review_artifacts/runtime_completion_20261017')
OUT = ROOT / 'review_artifacts/runtime_completion_20261017'
CASES = [
    'test_resource_admission', 'test_stream_index_retire', 'test_stream_index_append',
    'test_navigation_streaming_retirement', 'test_deferred_native_admission',
    'test_map_dependency_index', 'test_native_retirement_contract',
    'test_house_batch_share', 'test_ground_batch_lifetime',
    'test_house_residency', 'test_landscape_residency',
    'test_distant_building_proxy_gpu', 'test_target_scene_prefetch_gpu',
    'test_target_scene_prefetch_http', 'test_bridge_lod_retention',
    'test_material_publication', 'test_asset_residency_gpu', 'test_native_residency_gpu',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def copy(name):
    source = EXTERNAL / name
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    return {'path': target.relative_to(ROOT).as_posix(), 'sha256': sha(target)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tests = []
    for name in CASES:
        source = EXTERNAL / (name + '.log')
        content = source.read_text(encoding='utf-8-sig')
        assert not re.search(r'^FAIL|SCRIPT ERROR|^ERROR:', content, re.M), name
        assert re.search(r'failures=0|failures":0|failures": 0|GROUND_BATCH_LIFETIME PASS', content), name
        count = len(re.findall(r'^PASS(?:[: ]|$)', content, re.M))
        tests.append({'case': name, 'checks': count, 'failures': 0, 'log': copy(source.name)})
    reports = [copy(name) for name in ['proxy_gpu.json', 'target_gpu.json', 'native_gpu.json',
                                      'native_contract.json', 'transfer_http/http.json']]
    maps = []
    for name, field in [('proxy_gpu.json', 'source_path'), ('native_gpu.json', 'path'),
                        ('native_contract.json', 'path')]:
        data = json.loads((EXTERNAL / name).read_text(encoding='utf-8'))
        path = Path(data[field])
        expected = data.get('source_sha256', data.get('sha256'))
        assert sha(path) == expected
        resources = sorted(path.parent.glob(path.name + '.resources/*.rmres'))
        maps.append({'path': path.as_posix(), 'sha256': expected, 'bytes': path.stat().st_size,
                     'resources': [{'path': p.as_posix(), 'sha256': sha(p), 'bytes': p.stat().st_size}
                                   for p in resources]})
    media = []
    pixels = []
    folder = EXTERNAL / 'media_shadow_final'
    for label in ['near', 'middle', 'far', 'detail']:
        a = Image.open(folder / (label + '_base.png')).convert('RGB')
        b = Image.open(folder / (label + '_candidate.png')).convert('RGB')
        delta = ImageChops.difference(a, b)
        pixels.append({'view': label, 'dimensions': list(a.size), 'exact_pixels': a.tobytes() == b.tobytes(),
                       'mae_rgb': ImageStat.Stat(delta).mean,
                       'maximum_rgb': [channel[1] for channel in delta.getextrema()],
                       'note': 'diagnostic only; human Q90 WebP inspection recorded in report'})
        for suffix in ['base', 'candidate']:
            path = folder / (label + '_' + suffix + '.webp')
            record = json.loads(Path(str(path) + '.review-image.json').read_text(encoding='utf-8'))
            assert record['quality'] == 90 and record['lossless'] is False and record['sha256'] == sha(path)
            assert record['source_sha256'] == sha(path.with_suffix('.png'))
            media.append(record)
    sources = {}
    for folder in ['scripts', 'tools']:
        for path in sorted((ROOT / folder).rglob('*.gd')):
            sources[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    for name in ['tools/archive_runtime_completion.py', 'tools/run_godot_background.py']:
        sources[name] = hashlib.sha256((ROOT / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    data = {'baseline': '6ad846268142aac687f2eeb1559246cc9ed5f04c',
            'branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
            'engine': 'Godot 4.7.2 stable ed1daf0bf, Forward+, Vulkan AMD RX 7900 XTX',
            'tests': tests, 'total_checks': sum(row['checks'] for row in tests), 'failures': 0,
            'reports': reports, 'maps': maps, 'media': media, 'pixel_diagnostics': pixels,
            'source_lf_sha256': sources,
            'scope': 'Automatic native static HLOD/retirement and admitted target GPU preparation. No formal map edits; no RSS/VRAM/FPS claim.',
            'model_review': {'skill': 'C:/Users/luna/.codex/skills/rmmo-model-review/SKILL.md',
                             'report': 'docs/runtime_completion_20261017.md',
                             'visual_inspection': 'near/middle/far/detail, fixed camera/light/exposure, lossy WebP quality90; house and ground shadows inspected',
                             'source_masters_unchanged': True}}
    (OUT / 'evidence.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'checks': data['total_checks'], 'failures': 0, 'cases': len(tests), 'sources': len(sources)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
