"""Compare an original queue to the actual stable production queue.

This compiles a small CPU executable with real Godot Tuple/LocalVector/Vector
and memory.cpp. Mutex/CV instrumentation and error exits are standalone hooks;
it is not the engine tests=yes target or a GPU/whole-game acceptance run.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def extract(raw):
    text = raw.decode('utf-8').replace('\r\n', '\n')
    begin = text.index('\tclass SimpleCommandQueue {')
    end = text.index('\n\t// Helper class to manage RID_Owner', begin)
    return text[begin:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True, help='Frozen original header with memcpy queue')
    parser.add_argument('--candidate-source', type=Path, required=True)
    parser.add_argument('--godot-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=Path('C:/mingw64/bin/g++.exe'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    before = args.source.read_bytes()
    after = args.candidate_source.read_bytes()
    original, stable = extract(before), extract(after)
    assert 'memcpy(cmd_buffer' in original
    assert 'CommandBase *head' in stable and 'CommandBase *tail' in stable
    assert 'memcpy' not in stable and 'LocalVector' not in stable
    (args.output/'source_before.h').write_bytes(before)
    (args.output/'source_candidate.h').write_bytes(after)
    (args.output/'queue_original.inc').write_text(original, encoding='utf-8')
    # The legacy ownership harness names its second namespace/file "moved".
    # Here that file contains the actual stable production queue, not a transform.
    (args.output/'queue_moved.inc').write_text(stable, encoding='utf-8')
    fixture_dir = Path(__file__).parent/'fixtures'
    names = ['simple_command_queue_std_compat.h', 'simple_command_queue_ownership_harness.cpp',
             'simple_command_queue_stability_harness.cpp', 'simple_command_queue_error_hooks.cpp']
    for name in names:
        (args.output/name).write_bytes((fixture_dir/name).read_bytes())
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    env = os.environ.copy()
    env['PATH'] = str(args.compiler.parent)+os.pathsep+env.get('PATH', '')
    version = subprocess.run([str(args.compiler), '--version'], capture_output=True, text=True,
                             env=env, creationflags=flags, check=True).stdout
    common = [str(args.compiler), '-std=c++17', '-O2', '-g', '-DDEBUG_ENABLED', '-DRMMO_REAL_GODOT_CORE',
              '-pthread', '-Wall', '-Wextra', '-Wpedantic', '-Wno-unused-parameter',
              '-I'+str(args.godot_source), '-I'+str(args.godot_source/'platform/windows')]
    sources = [args.output/'simple_command_queue_stability_harness.cpp',
               args.output/'simple_command_queue_error_hooks.cpp', args.godot_source/'core/os/memory.cpp']
    commands, objects, dependencies, compile_logs = [], [], {}, []
    for index, source in enumerate(sources):
        obj = args.output/f'fixture_{index}.o'
        dep = args.output/f'fixture_{index}.d'
        command = common+['-MMD', '-MF', str(dep), '-c', str(source), '-o', str(obj)]
        built = subprocess.run(command, capture_output=True, text=True, env=env, creationflags=flags, timeout=90)
        commands.append(command); compile_logs.append(built.stdout+built.stderr)
        if built.returncode:
            (args.output/'compile.log').write_text(''.join(compile_logs), encoding='utf-8')
            print(built.stderr)
            return built.returncode
        objects.append(obj)
        for name in dep.read_text().replace('\\\n', '').split(': ', 1)[1].split():
            path = Path(name)
            if path.exists():
                dependencies[path.as_posix()] = sha(path.read_bytes())
    exe = args.output/'stability_test.exe'
    command = [str(args.compiler), '-pthread', *map(str, objects), '-o', str(exe)]
    built = subprocess.run(command, capture_output=True, text=True, env=env, creationflags=flags, timeout=60)
    commands.append(command); compile_logs.append(built.stdout+built.stderr)
    (args.output/'compile.log').write_text(''.join(compile_logs), encoding='utf-8')
    manifest = {
        'original_header_sha256': sha(before), 'original_queue_sha256': sha(original.encode()),
        'candidate_header_sha256': sha(after), 'candidate_queue_sha256': sha(stable.encode()),
        'runner_sha256': sha(Path(__file__).read_bytes()),
        'fixture_sha256': {name: sha((args.output/name).read_bytes()) for name in names},
        'compiled_dependency_sha256': dependencies, 'compiler': version, 'compile_commands': commands,
        'compile_exit': built.returncode,
        'real_godot_core': ['Tuple', 'LocalVector', 'Vector<uint8_t> (the PackedByteArray alias)', 'CowData',
                            'Memory::alloc_static/free_static', 'Memory::alloc_aligned_static/free_aligned_static'],
        'boundaries': [
            'Standalone executable, not the Godot tests=yes engine or GPU/whole-map acceptance',
            'Mutex/condition-variable hooks use standard primitives with lock-depth counters; engine error exits abort',
            'Actual Ref/Callable/ObjectDB lifecycle integration is covered separately by native engine tests',
            'Only the stable queue runs real Vector ownership, over-alignment, destructor-reentry and internal thread cases',
            'Original ownership/address probes keep observer controls alive; no freed payload control memory is read',
            'Original polymorphic memcpy is outside the C++ lifetime model; its scalar throughput is an observation, not validation',
            'Internal producer threads join before stop; no external thread suspension, debugger or unsafe shutdown race injection',
            'Producers must quiesce before reset/destruction; void push must never silently reject a synchronous completion',
            'Godot normal allocation counters exclude allocator metadata and aligned-allocation bytes; not RSS or VRAM',
            'Small-command timing is isolated ABBA observation, not a whole-engine performance estimate',
        ],
    }
    if not built.returncode:
        manifest['executable_sha256'] = sha(exe.read_bytes())
        for variant in ['original', 'stable', 'benchmark']:
            run = subprocess.run([str(exe), variant], capture_output=True, text=True,
                                 env=env, creationflags=flags, timeout=60)
            (args.output/(variant+'.jsonl')).write_text(run.stdout, encoding='utf-8')
            (args.output/(variant+'.stderr')).write_text(run.stderr, encoding='utf-8')
            manifest[variant] = {'exit': run.returncode, 'cases': [json.loads(line) for line in run.stdout.splitlines()],
                                 'stderr': run.stderr}
    (args.output/'result.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'candidate_queue_sha256': manifest['candidate_queue_sha256'],
                      'compile_exit': built.returncode,
                      **{name: {'exit': manifest[name]['exit'],
                                'passed': sum(row['passed'] for row in manifest[name]['cases']),
                                'failed': [row['case'] for row in manifest[name]['cases'] if not row['passed']]}
                         for name in ['original', 'stable', 'benchmark'] if name in manifest}}))
    return 0 if not built.returncode and manifest['original']['exit'] == 1 and manifest['stable']['exit'] == 0 and manifest['benchmark']['exit'] == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
