"""Bind completed reviews to one final candidate; never fabricates visual approval."""
from pathlib import Path
import argparse, hashlib, json

ROOT = Path('D:/code/rmmo')
REVIEW = ROOT / 'review_artifacts/axel_landmarks_20261016'
SOURCE = Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016')

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.file_digest(Path(path).open('rb'), 'sha256').hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset', choices=['church', 'guardhouse', 'watermill'], required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--http', type=Path, required=True)
    args = parser.parse_args()
    a, v = args.asset, args.version
    if not v.startswith('v') or not v[1:].isdigit():
        raise ValueError('Simple numbered version required')
    source = SOURCE / a / v / f'axel_{a}.glb'
    digest = sha(source)
    cpu_path = {'church': REVIEW/a/v/'source_geometry_semantic_checks.json',
                'guardhouse': REVIEW/a/f'{v}_cpu_audit.json',
                'watermill': REVIEW/a/f'cpu_audit_{v}.json'}[a]
    cpu = read(cpu_path)
    assert cpu.get('failed', cpu.get('fail')) == 0
    assert cpu.get('sha256', cpu.get('source_sha256')) == digest
    gpu_path = REVIEW/a/v/'gpu/report.json'
    gpu = read(gpu_path)
    assert gpu['identity']['sha256'] == digest
    assert all(gpu.get(k) is True for k in ['passed', 'visual_accepted', 'engine_error_free', 'physics_completed'])
    assert gpu['native_build']['ok'] and gpu['footprint']['ok']
    for shot in gpu['screenshots']:
        path = Path(shot['path']); receipt = read(str(path)+'.review-image.json')
        assert sha(path) == shot['sha256'] == receipt['sha256']
        assert receipt['quality'] == 90 and receipt['lossless'] is False
    http = read(args.http)
    assert http['failed'] == 0 and http['passed'] > 0
    assert not http['formal_map_modified'] and not http['formal_catalog_modified']
    rows = [s for s in http['sources'] if s['name'] == a]
    assert len(rows) == 1 and rows[0]['source']['sha256'] == digest
    assert rows[0]['imported_sha256'] == digest and rows[0]['compiled']['ok']
    own_checks = [c for c in http['checks'] if c['check'].startswith(a+':')]
    assert own_checks and all(c['ok'] for c in own_checks)
    contract_path = REVIEW/'pipeline/source_contracts.json'
    contracts = read(contract_path)
    assert contracts['failed'] == 0
    assert any(c['asset'] == a and c['sha256'] == digest and c['ok'] for c in contracts['candidates'])
    paths = [cpu_path, gpu_path, args.http, contract_path,
             REVIEW/'pipeline/component_logic.json',
             REVIEW/'pipeline/independent_runtime_audit.json', REVIEW/'lod_decisions.json']
    for key in ['reuse_evidence', 'unchanged_structure_report']:
        path = gpu.get('visual_review', {}).get(key)
        if path: paths.append(Path(path))
    result = {
        'schema': 1, 'asset': a, 'version': v, 'passed': True,
        'source_path': source.as_posix(), 'source_sha256': digest,
        'resource_status': 'passed', 'visual_status': 'passed', 'pipeline_status': 'passed',
        'formal_library_status': 'pending_publication', 'formal_map_status': 'owned_by_layout_task_not_modified',
        'cpu_checks': cpu.get('passed', cpu.get('pass')), 'http_model_checks': len(own_checks),
        'http_all_checks': http['passed'], 'visual_scope': gpu.get('visual_scope', gpu.get('visual_review', {})),
        'evidence': [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in paths],
        'limits': ['Actual RSS/VRAM and whole-map FPS are not measured.',
                   'Thin colored glass is a realtime transmission approximation; no colored caustics claim.',
                   'Independent runtime mechanisms retain pivots; no waterwheel automatic animation claim.',
                   'Formal catalog placement/save/reopen follows publication; formal map placement belongs to layout owner.'],
    }
    output = REVIEW/a/v/'acceptance.json'
    if output.exists():
        assert read(output) == result, 'Existing acceptance differs; preserve it and resolve evidence before publishing'
    else:
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'asset': a, 'path': output.as_posix(), 'sha256': sha(output)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
