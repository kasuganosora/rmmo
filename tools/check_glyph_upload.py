"""Check queued glyph atlas integrity with safe/separate rendering, off-screen.

Uses an external font read-only. GPU readback deliberately follows a burst of
atlas mutations; this contract measures correctness, not frame/load speed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

from run_godot_background import run_background


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output, engine, font = (p.resolve() for p in (args.output, args.engine, args.font))
    if output.exists() or output.is_relative_to(root):
        parser.error('--output must be a new external directory')
    if not engine.is_file() or not font.is_file():
        parser.error('--engine and --font must exist')
    project = output / 'project'
    project.mkdir(parents=True)
    fixture = root / 'tools/engine_patches/glyph_upload_contract/probe.gd'
    shutil.copyfile(fixture, project / 'probe.gd')
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Glyph upload contract"\n', encoding='utf8')
    files = [engine, font, fixture, Path(__file__), root / 'tools/run_godot_background.py',
             project / 'probe.gd', project / 'project.godot']
    before = {str(p): sha(p) for p in files}
    report = {'cases': [], 'scope': 'font atlas integrity, not performance evidence'}
    old = {key: os.environ.get(key) for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')}
    try:
        for mode in ('safe', 'separate'):
            case = output / mode
            case.mkdir()
            for key in old:
                folder = case / key
                folder.mkdir()
                os.environ[key] = str(folder)
            command = [str(engine), '--path', str(project), '--rendering-method', 'forward_plus',
                       '--rendering-driver', 'vulkan', '--render-thread', mode,
                       '--script', 'res://probe.gd', '--', '--mode=' + mode,
                       '--font=' + str(font), '--output=' + str(case / 'evidence.json')]
            result = run_background(command, cwd=project, timeout=120)
            (case / 'run.log').write_bytes(result.stdout)
            errors = [line for line in result.stdout.decode('utf8', errors='replace').splitlines()
                      if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL '))]
            evidence_path = case / 'evidence.json'
            evidence = json.loads(evidence_path.read_text(encoding='utf8')) if evidence_path.exists() else {}
            passed = (result.returncode == 0 and not errors and evidence.get('failed') == 0
                      and len(evidence.get('checks', [])) >= 20
                      and all(row['pass'] for row in evidence['checks']))
            report['cases'].append({'mode': mode, 'command': command, 'exit': result.returncode,
                                    'errors': errors, 'evidence': evidence, 'passed': passed})
            print(json.dumps({'mode': mode, 'passed': passed, 'errors': errors,
                              'checks': len(evidence.get('checks', []))}), flush=True)
            if not passed:
                break
        if len(report['cases']) == 2 and all(row['passed'] for row in report['cases']):
            report['same_work'] = (report['cases'][0]['evidence']['cases']
                                   == report['cases'][1]['evidence']['cases'])
    except Exception as error:
        report['runner_error'] = repr(error)
    finally:
        for key, value in old.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        after = {str(p): sha(p) for p in files}
        report['identity_stable'] = before == after
        report['passed'] = bool(report.get('same_work') and before == after and not report.get('runner_error'))
        (output / 'before.json').write_text(json.dumps(before, indent=2), encoding='utf8')
        (output / 'after.json').write_text(json.dumps(after, indent=2), encoding='utf8')
        (output / 'run.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
