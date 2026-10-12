"""Read-only comparison of the isolated Godot A/B probe artefacts."""
import json
import statistics
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT = Path('D:/code/rmmo_runtime/art_sources/bridge_long_pennant_optimization_20261009')


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf8'))


def diff(a, b):
    with Image.open(a) as x, Image.open(b) as y:
        assert x.size == y.size
        delta = ImageChops.difference(x.convert('RGB'), y.convert('RGB'))
        return {'equal': delta.getbbox() is None,
                'max_channel_delta': max(high for low, high in delta.getextrema()),
                'mean_channel_delta': sum(ImageStat.Stat(delta).mean) / 3}


def run():
    results = {'checks': [], 'images': {}, 'timings': {}}
    def check(ok, label):
        results['checks'].append({'ok': bool(ok), 'label': label})
    for mode in ['cpu', 'build', 'render']:
        a, b = read(f'{mode}_baseline.json'), read(f'{mode}_optimized.json')
        check(not a['failures'] and not b['failures'], f'{mode} probe assertions')
        check(a['semantic'] == b['semantic'], f'{mode} actual imported semantics')
    a, b = read('render_baseline.json'), read('render_optimized.json')
    for key in ['bounds', 'camera_transform', 'camera_size']:
        check(a[key] == b[key], f'fixed {key}')
    for pose in ['still', 'wind_t1', 'wind_t4']:
        result = diff(ROOT / f'baseline_{pose}.png', ROOT / f'optimized_{pose}.png')
        results['images'][pose] = result
        check(result['equal'], f'exact GPU pixels {pose}')
    movement = diff(ROOT / 'optimized_wind_t1.png', ROOT / 'optimized_wind_t4.png')
    results['wind_pose_difference'] = movement
    check(not movement['equal'], 'wind poses visibly differ')
    for case in ['baseline', 'optimized']:
        results['timings'][case] = []
        for path in sorted(ROOT.glob(f'native_{case}_*.json')):
            row = read(path.name)
            check(not row['failures'], path.name)
            check(row['semantic'] == read(f'build_{case}.json')['semantic'],
                  f'native roundtrip semantics {path.name}')
            results['timings'][case].append({k: row[k] for k in
                ['source_sha_us', 'payload_sha_us', 'native_load_us']})
        check(len(results['timings'][case]) >= 3, f'three native timing runs {case}')
    results['timing_medians_seconds'] = {}
    for case, rows in results['timings'].items():
        keys = ['source_sha_us', 'payload_sha_us', 'native_load_us']
        results['timing_medians_seconds'][case] = {
            **{key: statistics.median(row[key] for row in rows) / 1e6 for key in keys},
            'sum': statistics.median(sum(row[key] for key in keys) for row in rows) / 1e6}
    results['gpu_texture_counter_bytes'] = {
        case: read(f'render_{case}.json')['texture_memory_bytes']
        for case in ['baseline', 'optimized']}
    results['passed'] = all(c['ok'] for c in results['checks'])
    (ROOT / 'comparison.json').write_text(json.dumps(results, indent=2), encoding='utf8')
    print(json.dumps(results, indent=2))
    return 0 if results['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(run())
