#!/usr/bin/env python3
"""Run existing logic tests with Mock initialized without optional 2D resources."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TESTS = [('test_net_client.gd', '_run'), ('test_request_pipeline.gd', '_run'),
         ('test_player_waypoint_progress.gd', 'run')]

def main():
    for script, entry in TESTS:
        with tempfile.TemporaryDirectory(prefix='rmmo-network-test-') as temporary:
            wrapper = Path(temporary) / 'run.gd'
            wrapper.write_text(f'extends "res://tools/{script}"\n'
                               f'func {entry}()->void:\n'
                               '\tProjectSettings.set_setting("rmmo/startup_profile","world3d")\n'
                               '\troot.get_node("ServerConnection").configure(false)\n'
                               f'\tsuper.{entry}()\n')
            run = subprocess.run(['godot', '--headless', '--path', str(ROOT), '--script', str(wrapper),
                                  '--', '--backend=real'], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=30)
            passes = sum(line.startswith('PASS ') for line in run.stdout.splitlines())
            print(f'{script}: {passes} checks, exit={run.returncode}')
            if run.returncode or 'SCRIPT ERROR:' in run.stdout or '\nFAIL ' in run.stdout:
                print(run.stdout)
                raise SystemExit(run.returncode or 1)

if __name__ == '__main__':
    main()
