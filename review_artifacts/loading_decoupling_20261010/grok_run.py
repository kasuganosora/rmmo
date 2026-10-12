from pathlib import Path
import json
import subprocess
import time

root = Path('D:/code/rmmo')
out = root / 'review_artifacts/loading_decoupling_20261010'
args = ['C:/Users/luna/.grok/bin/agent.exe', '--cwd', str(root), '--no-subagents',
        '--max-turns', '3', '--permission-mode', 'plan', '--disable-web-search',
        '--prompt-file', str(out / 'grok_prompt.txt'), '--output-format', 'plain']
started = time.monotonic()
status = {'argv': args, 'limit_seconds': 120, 'timed_out': False}
with (out / 'grok_stdout.txt').open('wb') as stdout, (out / 'grok_stderr.txt').open('wb') as stderr:
    process = subprocess.Popen(args, cwd=root, stdout=stdout, stderr=stderr,
                               creationflags=subprocess.CREATE_NO_WINDOW)
    status['pid'] = process.pid
    try:
        status['exit_code'] = process.wait(timeout=120)
    except subprocess.TimeoutExpired:
        status['timed_out'] = True
        killed = subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                capture_output=True, text=True,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        status['termination_exit_code'] = killed.returncode
        status['termination_report'] = killed.stdout.strip()
        status['termination_error'] = killed.stderr.strip()
        try:
            status['exit_code'] = process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            status['exit_code'] = None
    status['process_alive_after_wait'] = process.poll() is None
status['elapsed_seconds'] = round(time.monotonic() - started, 3)
status['stdout_bytes'] = (out / 'grok_stdout.txt').stat().st_size
status['stderr_bytes'] = (out / 'grok_stderr.txt').stat().st_size
(out / 'grok_status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(status, ensure_ascii=False))
