"""Aggregate exact final-map outdoor runtime receipts; never approve visuals."""
import argparse
import hashlib
import json
import os
from pathlib import Path

OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016')
DEFAULTS = ('fortification_runtime/result.json', 'market_exterior_runtime/result.json',
            'functional_building_exterior_runtime/result.json')


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def combine(paths, expected_sha):
    errors, children, shots, seen, checks = [], [], [], set(), []
    functional = None
    deferred = []
    for path in paths:
        path = Path(path)
        try:
            before = sha(path)
            child = json.loads(path.read_text(encoding='utf-8-sig'))
            if not isinstance(child, dict):
                raise ValueError('runtime must be a JSON object')
            if sha(path) != before:
                raise ValueError('receipt changed while reading')
        except (OSError, ValueError) as error:
            errors.append(f'{path}: {error}')
            continue
        children.append({'path': str(path), 'sha256': before})
        for item in child.get('deferred_checks', []):
            deferred.append({'source_report': str(path), 'check': item, 'status': 'failed_deferred_not_repaired'})
        if not (child.get('map_sha256') == expected_sha and child.get('phase') == 'complete'
                and child.get('status') == 'passed' and child.get('failures') == 0):
            errors.append(f'{path}: incomplete/failed/stale runtime')
        # Preserve actual child findings, including their own failure details.
        checks.append({'child_path': str(path), 'checks': child.get('checks', [])})
        if not child.get('screenshots'):
            errors.append(f'{path}: no actual screenshots')
        for shot in child.get('screenshots', []):
            identifier = shot.get('id', '')
            if not identifier or identifier in seen:
                errors.append(f'{path}: duplicate/empty screenshot ID {identifier}')
                continue
            seen.add(identifier)
            try:
                image_path = Path(shot['path'])
                receipt = json.loads(Path(str(image_path) + '.review-image.json').read_text(encoding='utf-8-sig'))
                if not (image_path.suffix.lower() == '.webp' and sha(image_path) == shot['sha256']
                        and receipt.get('sha256') == shot['sha256'] and receipt.get('quality') == 90
                        and receipt.get('lossless') is False):
                    raise ValueError('missing exact Q90 lossy image evidence')
            except (OSError, ValueError, KeyError) as error:
                errors.append(f'{identifier}: {error}')
            shots.append(shot)
        if 'functional_buildings' in child:
            if functional is not None:
                errors.append('Duplicate functional building runtime section')
            functional = child['functional_buildings']
    if len(children) != len(paths) or len(paths) != 3:
        errors.append('Exactly three final runtime receipts are required')
    if not isinstance(functional, dict) or functional.get('passed') is not True:
        errors.append('Functional building exterior runtime not passed')
    else:
        for key in ('guardhouse', 'church', 'watermill'):
            if not any(c.get('key') == key and c.get('passed') is True for c in functional.get('checks', [])):
                errors.append('Missing actual outdoor building check: ' + key)
    return {'status': 'passed' if not errors else 'failed', 'phase': 'complete' if not errors else 'pending',
            'failures': len(errors), 'errors': errors, 'map_sha256': expected_sha,
            'child_reports': children, 'screenshots': shots, 'child_checks': checks,
            'functional_buildings': functional or {},
            'deferred_checks': deferred, 'all_work_complete': not deferred,
            'scope': 'Layout-stage outdoor runtime evidence, with separately disclosed failed locomotion follow-ups. No visual approval inferred; all images still need explicit review.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--reports', nargs=3, type=Path)
    args = parser.parse_args()
    if len(args.expected_sha) != 64 or any(c not in '0123456789abcdef' for c in args.expected_sha):
        parser.error('--expected-sha must be the actual final candidate SHA256')
    paths = args.reports or [args.out / p for p in DEFAULTS]
    result = combine(paths, args.expected_sha)
    # Failed aggregation never overwrites a successful runtime receipt.
    output = args.out / ('layout_runtime.json' if result['status'] == 'passed' else 'layout_runtime.pending.json')
    temporary = output.with_suffix('.json.pending')
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temporary, output)
    print(json.dumps({'path': str(output), 'status': result['status'], 'errors': result['errors']}))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
