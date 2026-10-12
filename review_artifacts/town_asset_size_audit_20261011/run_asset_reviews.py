"""Sequential private-desktop GPU verification. No production cache/map writes."""
import argparse
import json
import subprocess
import shutil
import sys
import time
from pathlib import Path

ROOT = Path('D:/code/rmmo')
ART = Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011')
REVIEW = ROOT / 'review_artifacts/town_asset_size_audit_20261011'
sys.path.insert(0, str(ROOT / 'tools'))
from run_godot_background import run_background

GODOT = 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe'
SCRIPT = 'res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd'

def read(path): return json.loads(path.read_text(encoding='utf8'))

def jobs(group):
    if group == 'pennants':
        return [{'label': 'pennant_' + row['label'], 'source': row['source'], 'candidate': row['candidate'],
                 'changed': True, 'detail': 'pennant'} for row in read(ART / 'pennants/candidates.json')]
    if group == 'lossless':
        result = read(ART / 'architecture/architecture_lossless_summary.json')
        result += read(ART / 'secondary/secondary_lossless_summary.json')
        for row in read(ART / 'foliage/foliage_manifest.json')['assets']:
            result.append(dict(row, label=row['asset']))
        return [dict(row, changed=False, detail='auto') for row in result]
    if group == 'foliage2k':
        return [{'label': row['asset'] + '_' + row['profile'], 'source': row['original_master'], 'candidate': row['output'],
                 'changed': True, 'detail': 'auto'} for row in read(ART / 'foliage/foliage_2k_manifest.json')['assets']]
    raise ValueError(group)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('group', choices=['pennants', 'lossless', 'foliage2k'])
    parser.add_argument('--filter', default='')
    parser.add_argument('--cases', default='baseline,candidate,compare')
    parser.add_argument('--reuse-baseline', default='')
    parser.add_argument('--shadows', action='store_true')
    args = parser.parse_args()
    result = []
    for job in jobs(args.group):
        if args.filter and args.filter not in job['label']:
            continue
        out = ART / 'review' / job['label']
        out.mkdir(parents=True, exist_ok=True)
        if args.reuse_baseline:
            prior = ART / 'review' / args.reuse_baseline
            assert read(prior / 'baseline.json')['passed']
            assert read(prior / 'baseline.json')['original_sha'] == __import__('hashlib').sha256(Path(job['source']).read_bytes()).hexdigest()
            (out / 'baseline').mkdir(exist_ok=True)
            for name in ['baseline.json', 'camera_views.json']:
                shutil.copy2(prior / name, out / name)
            for shot in (prior / 'baseline').glob('*.png'):
                shutil.copy2(shot, out / 'baseline' / shot.name)
            (out / 'baseline_evidence_origin.txt').write_text(str(prior), encoding='utf8')
        common = [f"--source={job['source']}", f"--candidate={job['candidate']}", f'--out={out}', f"--detail={job['detail']}"]
        if job['changed']:
            common.append('--allow-texture-change')
        script = SCRIPT.replace('review_lossless_candidates.gd','review_candidate_shadows.gd') if args.shadows else SCRIPT
        logdir = out / 'shadows' if args.shadows else out
        logdir.mkdir(exist_ok=True)
        for case in args.cases.split(','):
            if case not in ['baseline', 'candidate', 'compare']:
                raise ValueError(case)
            logfile = logdir / (case + '.log')
            command = [GODOT, '--path', str(ROOT), '--rendering-method', 'forward_plus', '--script', script, '--', *common, '--case=' + case]
            began = time.monotonic()
            if case == 'compare':
                command.insert(1, '--headless')
                p = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
                code, log = p.returncode, p.stdout.decode('utf8', errors='replace')
            else:
                completed = run_background(command, cwd=str(ROOT), timeout=180)
                code = completed.returncode
                log = completed.stdout.decode('utf8', errors='replace')
            logfile.write_text(log, encoding='utf8')
            row = {'asset': job['label'], 'case': case, 'exit_code': code, 'wall_seconds': time.monotonic() - began,
                   'log': str(logfile), 'report': str(logdir / (case + '.json'))}
            result.append(row)
            (REVIEW / (args.group + ('_shadow' if args.shadows else '') + '_run_progress.json')).write_text(json.dumps(result, indent=2), encoding='utf8')
            print(json.dumps(row), flush=True)
            if code != 0:
                print(log[-4500:], flush=True)
                return code
    return 0

if __name__ == '__main__': sys.exit(main())
