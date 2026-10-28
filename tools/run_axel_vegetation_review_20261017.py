"""Serial private-desktop candidate review. No formal resource/map writes."""
import argparse
import importlib.util
import json
import subprocess
import struct
import time
from pathlib import Path
import numpy as np
from PIL import Image
from run_godot_background import run_background
import audit_axel_reused_vegetation_20261017 as audit

ROOT = audit.ROOT
REVIEW = audit.OUT
ART = audit.RUNTIME / 'art_sources/axel_vegetation_optimization_20261017/grass_exact01'
ENGINE = 'D:/tools/godot/godot.windows.editor.x86_64.exe'
MAIN = ROOT / 'tools/review_axel_vegetation_candidates_20261017.gd'
SHADOW = ROOT / 'tools/review_axel_vegetation_shadows_20261017.gd'


def put(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def active_gpu():
    command = "Get-CimInstance Win32_Process | Where-Object {($_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless') -or $_.Name -like '*blender*'} | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
    result = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', command], capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else []


def strip_textures(value):
    if isinstance(value, dict):
        if value.get('__texture'):
            return {'__texture': True}
        return {k: strip_textures(v) for k, v in value.items()}
    if isinstance(value, list):
        return [strip_textures(v) for v in value]
    return value


def camera_contract(views):
    # Godot Vector3 consumes float32. Its JSON float64 round-trip can differ
    # by one float64 ULP while generating exactly the same camera coordinates.
    # Compare actual float32 bits only for those Vector3 fields, no tolerance.
    return [{key: [struct.pack('<f', v).hex() for v in value] if key in ('eye', 'aim') else value
             for key, value in view.items()} for view in views]


def compare(folder, allow_texture_change):
    baseline, candidate = audit.read(folder / 'baseline.json'), audit.read(folder / 'candidate.json')
    checks = {'both_cases_passed': baseline['passed'] and candidate['passed'],
              'same_generator': baseline['compiled_generator'] == candidate['compiled_generator'],
              'same_camera_float32_bits': camera_contract(baseline['camera_views']) == camera_contract(candidate['camera_views']),
              'same_dimensions': baseline['dimensions'] == candidate['dimensions'],
              'nontexture_semantics_exact': strip_textures(baseline['semantic']) == strip_textures(candidate['semantic']),
              'texture_semantics_exact_or_declared_lossy': allow_texture_change or baseline['semantic'] == candidate['semantic']}
    images = []
    for parent in [folder, folder / 'shadows']:
        a, b = audit.read(parent / 'baseline.json'), audit.read(parent / 'candidate.json')
        assert a['passed'] and b['passed']
        assert camera_contract(a.get('camera_views', a.get('views'))) == camera_contract(b.get('camera_views', b.get('views')))
        assert [r['name'] for r in a['screenshots']] == [r['name'] for r in b['screenshots']]
        for shot in a['screenshots']:
            left, right = parent / 'baseline' / shot['name'], parent / 'candidate' / shot['name']
            with Image.open(left) as im:
                aa = np.asarray(im.convert('RGBA'), dtype=np.int16)
            with Image.open(right) as im:
                bb = np.asarray(im.convert('RGBA'), dtype=np.int16)
            assert aa.shape == bb.shape
            diff = np.abs(aa - bb)
            row = {'baseline': audit.identity(left), 'candidate': audit.identity(right),
                   'dimensions': [aa.shape[1], aa.shape[0]], 'exact': bool(not diff.any()),
                   'rgb_mae_8bit': float(diff[:, :, :3].mean()), 'max_channel_error_8bit': int(diff.max()),
                   'changed_pixel_fraction': float(np.any(diff[:, :, :3], axis=2).mean())}
            images.append(row)
    checks['all_rendered_pixels_exact_or_declared_lossy'] = allow_texture_change or all(x['exact'] for x in images)
    report = {'checks': checks, 'passed': all(checks.values()), 'texture_change_allowed': allow_texture_change,
              'images': images, 'camera_comparison': 'Exact float32 Vector3 bits for eye/aim; all other fields exact. No tolerance.',
              'scope': 'Automated contract and fixed-view comparison; visual assessment remains separate'}
    put(folder / 'comparison.json', report)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', default='gpu_01')
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    assert args.run.startswith('gpu_') and Path(args.run).name == args.run
    out = REVIEW / args.run
    if out.exists() and not args.resume:
        raise SystemExit('Output exists; use an explicitly checked resume or a new run')
    out.mkdir(exist_ok=True)
    inventory = audit.read(REVIEW / 'audit01.json')
    sources = []
    for row in inventory['existing_alternative_reuse']:
        sources.append({'label': 'oak' if row['kind'] == 'lossless' else 'boxwood', 'source': row['original'],
                        'source_sha': row['original_sha256'], 'candidate': row['existing_formal_alternative'],
                        'candidate_sha': row['alternative_sha256'], 'allow_texture_change': row['kind'] != 'lossless'})
    for row in audit.read(ART / 'delivery.json')['models']:
        report = audit.read(Path(row['review']['path']))
        sources.append({'label': row['label'], 'source': report['source_master']['path'],
                        'source_sha': report['source_master']['sha256'], 'candidate': row['candidate']['path'],
                        'candidate_sha': row['candidate']['sha256'], 'allow_texture_change': False})
    plan = {'models': sources, 'scripts': [audit.identity(MAIN), audit.identity(SHADOW)],
            'dimensions': [1400, 1000], 'map_before': audit.identity(audit.MAP),
            'catalog_before': audit.identity(audit.ASSETS / 'library.json')}
    if (out / 'plan.json').exists():
        prior = audit.read(out / 'plan.json')
        assert prior['models'] == sources and prior['scripts'] == plan['scripts']
        plan = prior
    else:
        put(out / 'plan.json', plan)
    completed = []
    for model in sources:
        folder = out / model['label']
        folder.mkdir(exist_ok=True)
        assert audit.sha(Path(model['source'])) == model['source_sha']
        assert audit.sha(Path(model['candidate'])) == model['candidate_sha']
        for script, subfolder in [(MAIN, folder), (SHADOW, folder / 'shadows')]:
            for case in ['baseline', 'candidate']:
                report_path = subfolder / (case + '.json')
                if report_path.exists():
                    prior = audit.read(report_path)
                    assert prior.get('passed'), 'Failed reports require a fresh output or diagnosis; never overwrite'
                    assert prior['original_sha'] == model['source_sha' if case == 'baseline' else 'candidate_sha']
                    continue
                if active_gpu():
                    raise SystemExit('Other GPU process detected; resume after it finishes')
                print(f"GPU {model['label']} {script.stem} {case}", flush=True)
                command = [ENGINE, '--path', ROOT.as_posix(), '--script', 'res://' + script.relative_to(ROOT).as_posix(), '--',
                           '--source=' + model['source'], '--candidate=' + model['candidate'], '--out=' + folder.as_posix(), '--case=' + case]
                if model['allow_texture_change']:
                    command.append('--allow-texture-change')
                began = time.monotonic()
                result = run_background(command, cwd=ROOT, timeout=360)
                log_path = folder / (script.stem + '_' + case + '.log')
                log_path.write_bytes(result.stdout)
                if result.returncode or not report_path.exists() or not audit.read(report_path).get('passed'):
                    raise RuntimeError(f'GPU review failed; inspect {log_path}')
                print(f"Finished {model['label']} {case} in {time.monotonic()-began:.1f}s", flush=True)
        result = compare(folder, model['allow_texture_change'])
        if not result['passed']:
            raise RuntimeError(f'Comparison failed: {folder}')
        completed.append({'label': model['label'], 'comparison': audit.identity(folder / 'comparison.json'),
                          'images': len(result['images']), 'exact_images': sum(r['exact'] for r in result['images'])})
        put(out / 'progress.json', {'completed': completed, 'visual_review': 'pending'})
        print(f"PAIR {model['label']} passed, exact {completed[-1]['exact_images']}/{len(result['images'])}", flush=True)
    assert all(audit.sha(Path(row['path'])) == row['sha256'] for row in plan['scripts'])
    put(out / 'automated_acceptance.json', {'completed': completed, 'passed': True,
        'formal_map_unchanged': audit.sha(audit.MAP) == plan['map_before']['sha256'],
        'formal_catalog_unchanged': audit.sha(audit.ASSETS / 'library.json') == plan['catalog_before']['sha256'],
        'visual_review': 'pending', 'formal_integration': 'not_modified'})


if __name__ == '__main__':
    main()
