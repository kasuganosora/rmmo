"""Read-only A/B evidence aggregation; writes independent review report."""
import json
import statistics
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT = Path('D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009')


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf8'))


def main():
    result = {'failures': [], 'images': {}, 'timings': {}, 'median_ms': {}}
    for pose in ['wide', 'deck_rim', 'arch']:
        with Image.open(ROOT / f'original_{pose}.png') as a, Image.open(ROOT / f'candidate_{pose}.png') as b:
            d = ImageChops.difference(a.convert('RGB'), b.convert('RGB'))
            exact = d.getbbox() is None
            result['images'][pose] = {'equal': exact, 'max_channel_delta': max(hi for lo, hi in d.getextrema()),
                                     'mean_channel_delta': sum(ImageStat.Stat(d).mean) / 3}
            if not exact: result['failures'].append(f'pixels {pose}')
    hashes = set()
    for case in ['original', 'candidate']:
        rows = [read(f'profile_{case}_{i}.json') for i in range(1, 4)]
        result['timings'][case] = rows
        for row in rows:
            result['failures'].extend(row['failures'])
            hashes.add(row['collision_faces_sha256'])
        keys = ['prepare_cpu_ms', 'publish_prepared_cold_materials_ms',
                'publish_prepared_warm_materials_ms', 'segmented_restore_ms',
                'geometry_identity_ms', 'physics_shape_ms']
        result['median_ms'][case] = {k: statistics.median(r[k] for r in rows) for k in keys}
        for key in ['materials_ms', 'cpu_meshes_ms']:
            result['median_ms'][case][key] = statistics.median(r['restore'][key] for r in rows)
    if len(hashes) != 1: result['failures'].append('collision mismatch')
    result['collision_faces_sha256'] = sorted(hashes)
    result['candidate_audit'] = read('candidate_audit.json')
    result['texture_profile'] = read('texture_profile_original_1.json')['texture_profile']
    result['recommendation'] = 'Keep original: exact vertex compaction is too small, compressed rmres is larger, and there is no demonstrated repeatable publication gain.'
    result['gpu_window'] = 'released: no more GPU tests required for this candidate'
    result['passed_fidelity'] = not result['failures']
    (ROOT / 'comparison.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf8')
    print(json.dumps({k: v for k, v in result.items() if k != 'timings'}, indent=2, ensure_ascii=False))
    return 0 if result['passed_fidelity'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
