"""Archive verified scalar evidence; all importable assets/media stay external."""
import hashlib
from collections import Counter
import json
import re
import shutil
import statistics
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTERNAL = Path('D:/code/rmmo_runtime/review_artifacts/staged_far_20261017')
OUT = ROOT / 'review_artifacts/staged_far_20261017'
LOGS = ['contract', 'entry_readiness', 'local_entry_authority', 'ground_batch_lifetime',
        'terrain_incremental', 'vegetation_scatter', 'wind_lod_optimization',
        'bridge_lod_retention', 'automatic_entry', 'entry_http', 'cutout_http',
        'terrain_gpu', 'cpu_river_gpu', 'building_traversal_gpu', 'collision_first_gpu']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def copy(name):
    source = EXTERNAL / name
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    return {'path': target.relative_to(ROOT).as_posix(), 'sha256': sha(target)}


def verified_log(name):
    content = (EXTERNAL / name).read_text(encoding='utf-8-sig')
    assert not re.search(r'^FAIL|SCRIPT ERROR|^ERROR:', content, re.M), name
    assert re.search(r'failures[=:] ?0|failures": ?0|0 failures|GROUND_BATCH_LIFETIME PASS|WIND_LOD_FAILURES 0', content), name
    return {'log': copy(name), 'printed_pass_checks': len(re.findall(r'^PASS(?:[: ]|$)', content, re.M)), 'failures': 0,
            'warnings': dict(Counter(re.findall(r'^WARNING:.*$', content, re.M)))}


def resource(path, expected=None):
    path = Path(path)
    actual = sha(path)
    if expected is not None:
        assert actual == expected, path
    result = {'path': path.as_posix(), 'sha256': actual, 'bytes': path.stat().st_size}
    if path.suffix == '.gltf':
        result['native_data'] = [resource(p) for p in sorted(Path(str(path) + '.resources').glob('*.rmres'))]
    if path.suffix == '.scn':
        data = path.read_bytes()
        assert data[:4] == b'RSCC' and data[-4:] == b'RSCC'
        mode, block, total = struct.unpack_from('<III', data, 4)
        assert mode <= 4 and 0 < block <= 64*1024*1024 and total > 0
        count = total // block + 1
        lengths = struct.unpack_from('<' + 'I'*count, data, 16)
        assert 16 + count*4 + sum(lengths) == len(data)-4
        result['native_uncompressed_header_bytes'] = total
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / '.gitattributes').write_text('*.json -text whitespace=cr-at-eol\n*.log -text -diff whitespace=cr-at-eol\n', encoding='utf-8', newline='\n')
    tests = [verified_log(name + '.log') for name in LOGS]
    reports = []
    for name in ['automatic_entry.json', 'http.json', 'cutout_http.json', 'terrain_gpu.json']:
        assert read(EXTERNAL / name)['failures'] == 0, name
        reports.append(copy(name))
    reports.append(copy('terrain_preparation.json'))
    terrain = read(EXTERNAL / 'terrain_gpu.json')
    cutout = read(EXTERNAL / 'cutout_http.json')
    media = []
    for folder in [Path(terrain['media']), Path(cutout['media'])]:
        for path in sorted(folder.glob('*.webp')):
            if 'repeat' in path.stem or path.stem == 'normal':
                continue
            record = read(str(path) + '.review-image.json')
            assert record['quality'] == 90 and record['lossless'] is False
            assert sha(path) == record['sha256'] and sha(path.with_suffix('.png')) == record['source_sha256']
            media.append(record)
    assert len(media) == 20, len(media)
    entry = []
    for label in ['a0', 'a1', 'b0', 'a2', 'b1', 'b2', 'a3', 'b3']:
        data = read(EXTERNAL / ('entry_' + label + '.json'))
        assert data['failures'] == 0
        entry.append({'label': label, 'control': data['control'], 'entry_ms': data['entry_ms'],
                      'world_ready_ms': data['profile']['entry_playable_ready_us'] / 1000 - data['profile']['ready_started'],
                      'map_sha256': data['map_sha256'], 'report': copy('entry_' + label + '.json'),
                      'log': verified_log('entry_' + label + '.log')})
    assert len({d['map_sha256'] for d in entry}) == 1
    a = [d['entry_ms'] for d in entry if d['control']]
    b = [d['entry_ms'] for d in entry if not d['control']]
    comparisons = {'entry': entry, 'entry_control_median_ms': statistics.median(a),
                   'entry_staged_median_ms': statistics.median(b), 'entry_control_range_ms': max(a)-min(a),
                   'entry_staged_range_ms': max(b)-min(b),
                   'entry_conclusion': 'Functional staged readiness proven; small-fixture entry difference is inside A/A variability. No overall loading speedup claim.',
                   'terrain_views': terrain['views'],
                   'terrain_gpu_ms_medians': {r['label']: statistics.median(r['gpu_ms']) for r in terrain['measurements']},
                   'cutout_rollout': cutout['rollout']}
    (OUT / 'comparison.json').write_text(json.dumps(comparisons, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    resources = [resource(terrain['geometry'].get('path', Path(terrain['media']) / 'terrain.gltf'), terrain['geometry']['author_sha256']),
                 resource(terrain['hole_map']['path'], terrain['hole_map']['sha256']),
                 resource(cutout['asset']['source'], cutout['asset']['source_sha256']),
                 resource(cutout['asset']['source'] + '.godot_export.glb'),
                 resource(terrain['cutout_audit']['source'], terrain['cutout_audit']['source_sha256']),
                 resource(terrain['cutout_audit']['native'], terrain['cutout_audit']['native_sha256'])]
    sources = {}
    for folder in ['scripts', 'tools']:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.suffix in ['.gd', '.gdshader', '.py']:
                sources[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    payload = {'baseline': 'd1121df18039605a19a7f4aeedc9bd05b0e7b989',
               'branch': 'codex/editor-reliability', 'engine': 'Godot 4.7.2 ed1daf0bf Forward+ Vulkan RX 7900 XTX',
               'tests': tests, 'printed_pass_checks': sum(r['printed_pass_checks'] for r in tests), 'failures': 0,
               'reports': reports, 'comparison': {'path': 'review_artifacts/staged_far_20261017/comparison.json', 'sha256': sha(OUT / 'comparison.json')},
               'resources': resources, 'media': media, 'source_lf_sha256': sources,
               'model_review': {'skill': 'C:/Users/luna/.codex/skills/rmmo-model-review/SKILL.md',
                                'report': 'docs/staged_far_20261017.md',
                                'reviewed_webp_sha256': [r['sha256'] for r in media],
                                'scope': 'Derived terrain geometry/material and independent cutout contract fixture; no formal art placement, RSS, VRAM or whole-town FPS claim.'}}
    (OUT / 'evidence.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'groups': len(tests), 'printed_pass_checks': payload['printed_pass_checks'], 'failures': 0, 'media': len(media)}))


if __name__ == '__main__':
    main()
