"""Serial private-desktop v5 shadow diagnosis; no model edits or publication."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
from review_axel_market_realism_20261016 import active_gpu, ENGINE, ROOT, REVIEW
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--take', default='shadow_diagnostic_v5_01')
    parser.add_argument('--source-take', default='gpu_realism_v5_01')
    parser.add_argument('--plan-version', default='v5')
    parser.add_argument('--assets', default='pottery,scroll')
    args = parser.parse_args()
    script = 'res://tools/diagnose_axel_market_shadows_20261016.gd'
    if not args.run:
        result = subprocess.run([str(ENGINE), '--headless', '--path', str(ROOT), '--script', script, '--', '--syntax-only'], capture_output=True)
        print((result.stdout + result.stderr).decode('utf-8', errors='replace'))
        raise SystemExit(result.returncode)
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', args.take) or (REVIEW / args.take).exists():
        raise ValueError('Use a fresh simple diagnostic take')
    spec = importlib.util.spec_from_file_location('review_image', 'C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    summary = {'diagnostic_only': True, 'formal_writes': False, 'jobs': []}
    for asset in args.assets.split(','):
        if asset not in ['pottery','scroll']:raise ValueError('Invalid diagnostic asset')
        if active_gpu():
            raise RuntimeError('GPU queue occupied')
        result = run_background([str(ENGINE), '--path', str(ROOT), '--script', script, '--', f'--asset={asset}', f'--take={args.take}', f'--plan-version={args.plan_version}', f'--source-take={args.source_take}'], cwd=ROOT, timeout=240)
        folder = REVIEW / args.take / asset
        folder.mkdir(parents=True, exist_ok=True)
        log = (result.stdout or b'') + (getattr(result, 'stderr', None) or b'')
        (folder / 'engine.log').write_bytes(log)
        path = folder / 'diagnostic.json'
        report = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
        clean = not re.search(rb'(?m)^(?:SCRIPT ERROR|ERROR):', log)
        passed = result.returncode == 0 and report.get('passed') and clean
        if passed:
            receipts = []
            for shot in report['screenshots']:
                receipt = module.prepare(Path(shot['path']), lossless=False, keep_source=False, quality=90)
                shot['upload'] = receipt; shot['original_local_png_sha256'] = shot.pop('file_sha256')
                shot.pop('path'); receipts.append(receipt)
            path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            (folder / 'image_upload_receipts.json').write_text(json.dumps(receipts, indent=2), encoding='utf-8')
        summary['jobs'].append({'asset': asset, 'passed': bool(passed), 'returncode': result.returncode, 'engine_error_free': clean, 'report': str(path), 'report_sha256': hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ''})
        (REVIEW / args.take / 'runner_result.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
        print(json.dumps(summary['jobs'][-1]), flush=True)
        if not passed:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
