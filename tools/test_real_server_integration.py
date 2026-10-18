#!/usr/bin/env python3
"""Run Godot against an actual Go server using a disposable example content root."""
import argparse
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-bin', required=True, type=Path)
    parser.add_argument('--server-repo', required=True, type=Path)
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rmmo-network-') as temporary:
        directory = Path(temporary)
        content = directory / 'content'
        shutil.copytree(args.server_repo / 'examples/gameplay', content)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        address = f'http://127.0.0.1:{port}'
        command = [str(args.server_bin.resolve()), '-env-file=', '-config=', '-content', str(content),
                   '-map', 'tutorial/yard', '-db', str(directory/'game.sqlite'),
                   '-ntp-required=false', '-ntp-servers=', '-addr', f'127.0.0.1:{port}']
        with (directory/'server.log').open('w+') as log:
            server = subprocess.Popen(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 30
                while True:
                    if server.poll() is not None or time.monotonic() >= deadline:
                        log.seek(0)
                        raise RuntimeError('Server startup failed:\n' + log.read())
                    try:
                        with urllib.request.urlopen(address+'/health', timeout=1) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        time.sleep(.05)
                try:
                    run = subprocess.run([args.godot, '--headless', '--path', str(ROOT), '--script',
                                          'res://tools/test_real_server.gd', '--', '--backend=real',
                                          '--test-server='+address, '--test-content-root='+str(content)],
                                         cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, timeout=45)
                except subprocess.TimeoutExpired as error:
                    print((error.stdout or b'').decode(errors='replace'))
                    raise
                print(run.stdout, end='')
                if run.returncode or 'SCRIPT ERROR:' in run.stdout or 'REAL_SERVER_TESTS failures=0' not in run.stdout:
                    log.seek(0)
                    print(log.read())
                    raise SystemExit(run.returncode or 1)
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()

if __name__ == '__main__':
    main()
