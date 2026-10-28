"""Run a Godot 4.8 streaming contract on the private Windows desktop.

Copies the fixture to a new external directory and uses a read-only source image.
GPU readbacks, polling and flush (forced probe only) are test instrumentation,
not frame/load benchmarks. Does not change the project or installed engine.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import time

from run_godot_background import run_background


def sha(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def lossy_webp(path):
    raw = path.read_bytes()
    if raw[:4] != b'RIFF' or raw[8:12] != b'WEBP':
        return False
    at, lossy = 12, False
    while at + 8 <= len(raw):
        kind, size = raw[at:at + 4], int.from_bytes(raw[at + 4:at + 8], 'little')
        if at + 8 + size > len(raw) or kind == b'VP8L':
            return False
        lossy |= kind == b'VP8 '
        at += 8 + size + (size & 1)
    return lossy and at == len(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--probe', choices=('forced', 'camera', 'world-uv', 'worker', 'budget', 'product', 'surface'), default='camera')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    engine, source = args.engine.resolve(), args.source.resolve()
    if output.is_relative_to(root) or output.exists():
        parser.error('--output must be a new directory outside the Godot project')
    if not engine.is_file() or not source.is_file():
        parser.error('--engine and --source must be existing files')
    fixture = root / 'tools/engine_patches/texture_streaming_contract'
    project = output / 'project'
    project.mkdir(parents=True)
    for name in ('project.godot', 'probe.gd', 'camera_probe.gd', 'world_uv_probe.gd',
                 'worker_probe.gd', 'budget_probe.gd', 'product_probe.gd', 'surface_probe.gd'):
        shutil.copy2(fixture / name, project / name)
    shutil.copy2(root / 'scripts/world3d/streamed_texture_product.gd', project / 'streamed_texture_product.gd')
    shader_files = []
    if args.probe == 'surface':
        target = project / 'scripts/world3d'
        target.mkdir(parents=True)
        for name in ('streaming_surface_shader.gd', 'streaming_surface_feedback.gdshaderinc',
                     'river_terrain.gdshader', 'river_bank.gdshader', 'normal_texture_decode.gdshaderinc'):
            shutil.copy2(root / 'scripts/world3d' / name, target / name)
            shader_files.append(target / name)
    config = project / 'project.godot'
    if args.probe != 'forced':
        text = config.read_text().replace('viewport_width=640', 'viewport_width=1280')
        text = text.replace('viewport_height=480', 'viewport_height=960')
        if args.probe == 'budget':
            text = text.replace('textures/streaming/memory_budget_enabled=false',
                                'textures/streaming/memory_budget_enabled=true')
        # Exercise decay promptly. This is explicit fixture configuration;
        # the upstream production default remains 5000 ms.
        config.write_text(text + 'textures/streaming/inactivity_decay_rate_ms=1000\n', encoding='utf8')
    script = {'forced': 'probe.gd', 'camera': 'camera_probe.gd', 'world-uv': 'world_uv_probe.gd',
              'worker': 'worker_probe.gd', 'budget': 'budget_probe.gd', 'product': 'product_probe.gd',
              'surface': 'surface_probe.gd'}[args.probe]
    command = [str(engine), '--path', str(project), '--rendering-method', 'forward_plus',
               '--rendering-driver', 'vulkan', '--script', str(project / script), '--',
               '--source=' + str(source), '--output=' + str(output / 'evidence')]
    files = [engine, source, Path(__file__), root / 'tools/run_godot_background.py',
             *(path for path in project.iterdir() if path.is_file()), *shader_files]
    before = {str(path): sha(path) for path in files}
    (output / 'before.json').write_text(json.dumps(before, indent=2), encoding='utf8')
    report = {'command': command, 'probe': args.probe, 'not_performance_evidence': True}
    old_environment = {key: os.environ.get(key) for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')}
    started = time.monotonic()
    try:
        for key in old_environment:
            folder = output / key
            folder.mkdir()
            os.environ[key] = str(folder)
        result = run_background(command, cwd=project, timeout=180 if args.probe == 'surface' else 120,
                                on_start=lambda pid, tid: (output / 'pid.json').write_text(
                                    json.dumps({'pid': pid, 'tid': tid}), encoding='utf8'))
        (output / 'run.log').write_bytes(result.stdout)
        text = result.stdout.decode('utf8', errors='replace')
        report.update(exit=result.returncode,
                      errors=[line for line in text.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:'))])
        evidence = output / 'evidence/result.json'
        data = json.loads(evidence.read_text(encoding='utf8')) if evidence.exists() else None
        report['checks'] = data.get('checks') if data else None
        report['failed'] = data.get('failed') if data else None
        report['preview_encoding_valid'] = all(
            row.get('quality') == 90 and row.get('lossy') is True
            and sha(Path(row['path'])) == row['sha256'] and lossy_webp(Path(row['path']))
            for row in data.get('previews', [])) if data else False
        report['passed'] = bool(result.returncode == 0 and not report['errors'] and data
                                and report['preview_encoding_valid']
                                and data.get('failed') == 0 and data.get('checks')
                                and all(row['pass'] for row in data['checks']))
    except Exception as error:
        report.update(passed=False, runner_error=repr(error))
    finally:
        for key, value in old_environment.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        after = {str(path): sha(path) for path in files}
        (output / 'after.json').write_text(json.dumps(after, indent=2), encoding='utf8')
        report['identity_stable'] = before == after
        report['passed'] = report.get('passed', False) and report['identity_stable']
        report['elapsed_s'] = time.monotonic() - started
        (output / 'run.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, ensure_ascii=False), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
