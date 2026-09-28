"""Run isolated native controls for the optional C-IPC follow input adapter."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', required=True, type=Path)
    parser.add_argument('--module-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = [
        ('disabled', ['--case', 'follow', '--without-follow'], True),
        ('soft', ['--case', 'follow'], True),
        ('free', ['--case', 'follow', '--follow-weight', '1'], True),
        ('substep', ['--case', 'follow', '--dt', '.0025'], True),
        ('travel_limit', ['--case', 'follow', '--follow-max-travel', '.8'], True),
        ('invalid_hard_weight', ['--case', 'follow', '--follow-weight', '0'], False),
        ('invalid_weight', ['--case', 'follow', '--follow-weight', '2'], False),
        ('freefall', ['--case', 'freefall'], True),
        ('follow_contact', ['--case', 'follow_contact'], True),
        ('follow_contact_off', ['--case', 'follow_contact', '--without-contact'], 'penetration'),
    ]
    rows = []
    for name, flags, expected in cases:
        directory = args.output / name
        # Refuse stale results instead of mistaking a failed process for success.
        if (directory / 'result.json').exists():
            raise ValueError('Choose a fresh output directory: ' + str(directory))
        with (args.output / (name+'.log')).open('w') as log:
            process = subprocess.run([sys.executable, str(Path(__file__).with_name('probe_codim_reference.py')),
                                      '--checkout', str(args.checkout), '--module-dir', str(args.module_dir),
                                      '--output', str(directory), *flags], stdout=log, stderr=subprocess.STDOUT,
                                     timeout=120)
        result_file = directory / 'result.json'
        result = json.loads(result_file.read_text()) if result_file.exists() else None
        if expected == 'penetration':
            ok = process.returncode != 0 and result is not None and not result['accepted'] and result['frames'][-1]['body_gap'] < 0
        elif expected:
            ok = process.returncode == 0 and result is not None and result['accepted']
        else:
            message = (args.output / (name+'.log')).read_text()
            ok = process.returncode != 0 and result is None and 'RMMO cloth weight outside soft/free range' in message
        rows.append(dict(name=name, expected_valid=expected, returncode=process.returncode, passed=ok, result=result))
        print(name, 'PASS' if ok else 'FAIL', flush=True)
    modules = list(args.module_dir.glob('JGSL*.so'))
    if len(modules) != 1:
        raise ValueError('Expected one native module')
    report = dict(scope='native predictor adapter controls; not garment acceptance',
                  module_sha256=hashlib.sha256(modules[0].read_bytes()).hexdigest(),
                  cases=rows, accepted=all(r['passed'] for r in rows))
    (args.output/'suite.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return 0 if report['accepted'] else 2


if __name__ == '__main__':
    sys.exit(main())
