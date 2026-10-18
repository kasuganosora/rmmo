#!/usr/bin/env python3
"""Run existing logic tests with Mock initialized without optional 2D resources."""
from pathlib import Path
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[1]
TESTS = [('test_net_client.gd', '_run'), ('test_request_pipeline.gd', '_run'),
         ('test_player_waypoint_progress.gd', 'run')]

def run_tests(tests):
    for script, entry in tests:
        with tempfile.TemporaryDirectory(prefix='rmmo-network-test-') as temporary:
            wrapper = Path(temporary) / 'run.gd'
            wrapper.write_text(f'extends "res://tools/{script}"\n'
                               f'func {entry}()->void:\n'
                               '\tProjectSettings.set_setting("rmmo/startup_profile","world3d")\n'
                               '\troot.get_node("ServerConnection").configure(false)\n'
                               f'\tawait super.{entry}()\n')
            try:
                run = subprocess.run(['godot', '--headless', '--path', str(ROOT), '--script', str(wrapper),
                                      '--', '--backend=real'], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=30)
            except subprocess.TimeoutExpired as error:
                print(f'{script}: timed out')
                output = error.stdout or b''
                print(output.decode(errors='replace') if isinstance(output, bytes) else output)
                raise SystemExit(1) from error
            passes = sum(line.strip().startswith(('PASS ', 'OK ')) for line in run.stdout.splitlines())
            print(f'{script}: {passes} checks, exit={run.returncode}')
            if run.returncode or 'ERROR:' in run.stdout or re.search(r'(?m)^\s*FAIL\b', run.stdout):
                print(run.stdout)
                raise SystemExit(run.returncode or 1)

if __name__ == '__main__':
    run_tests(TESTS)
