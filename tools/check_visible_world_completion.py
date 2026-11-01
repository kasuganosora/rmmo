"""Record actual gameplay entry and post-entry visible-world completion."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from godot_process_monitor import workload_snapshot
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=Path('D:/tools/godot/godot.windows.editor.x86_64.exe'))
    parser.add_argument('--map', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expect-gaps', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'engine': str(args.engine), 'engine_sha256': hashlib.sha256(args.engine.read_bytes()).hexdigest(),
              'map': str(args.map), 'map_sha256': hashlib.sha256(args.map.read_bytes()).hexdigest(),
              'private_desktop': True, 'expect_gaps': args.expect_gaps, 'workload_before': workload_snapshot()}
    report['source_sha256'] = {
        name: hashlib.sha256((repo / name).read_bytes()).hexdigest()
        for name in ('scripts/world3d/world_3d.gd', 'scripts/world3d/world_stream.gd',
                     'scripts/world3d/deferred_asset_loader.gd', 'scripts/world3d/stream_candidate_plan.gd',
                     'scripts/world3d/stream_cell_query.gd', 'scripts/world3d/visual_stream_range.gd',
                     'scripts/world3d/visual_chunk_priority.gd',
                     'tools/probe_visible_world_completion.gd')}
    for key in list(os.environ):
        if key.startswith(('RMMO_', 'VK_')):
            os.environ.pop(key)
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP'):
        private = output / key
        private.mkdir()
        os.environ[key] = str(private)
    os.environ['RMMO_VISIBLE_PROBE_MAP'] = args.map.resolve().as_posix()
    os.environ['RMMO_VISIBLE_PROBE_OUTPUT'] = (output / 'coverage.json').as_posix()
    command = [str(args.engine.resolve()), '--path', str(repo), '--script',
               'res://tools/probe_visible_world_completion.gd']
    report['command'] = command
    try:
        result = run_background(command, cwd=repo, timeout=285)
        (output / 'engine.log').write_bytes(result.stdout)
        report['exit'] = result.returncode
        report['errors'] = [line for line in result.stdout.decode('utf-8', 'replace').splitlines()
                            if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
        coverage = json.loads((output / 'coverage.json').read_text(encoding='utf-8'))
        report['coverage_status'] = coverage['status']
        final = coverage['snapshots'][-1]
        report['summary'] = final['summary']
        gaps = (final['summary']['pending_in_view'] + final['summary']['missing_visual_specs']
                + final['summary'].get('unbacked_cpu_specs', 0))
        report['passed'] = (result.returncode == 0 and not report['errors']
                            and coverage['status'] == 'settled' and coverage['runtime_blackout_frames'] == 0
                            and not final['error'] and not final['path_errors'] and not final['instance_errors']
                            and ((gaps > 0) if args.expect_gaps else (gaps == 0)))
    except BaseException as error:
        if isinstance(error, subprocess.TimeoutExpired) and error.output:
            (output / 'engine.log').write_bytes(error.output)
        report.update(passed=False, error=repr(error))
        raise
    finally:
        report['workload_after'] = workload_snapshot()
        (output / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({key: report.get(key) for key in ('passed', 'exit', 'errors', 'summary')}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
