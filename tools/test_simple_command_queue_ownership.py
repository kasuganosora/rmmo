"""Extract the real queue and test ownership with permanently live control blocks.

This is a single-thread CPU semantic reproduction, NOT complete Godot testing.
The original memcpy of a non-trivially-copyable polymorphic command is itself
outside the C++ object model. The harness observes counters without freeing or
dereferencing a freed payload. It does not endorse memcpy as legal relocation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=Path('C:/mingw64/bin/g++.exe'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    original_bytes = args.source.read_bytes()
    source = original_bytes.decode('utf-8').replace('\r\n', '\n')
    start = source.index('\tclass SimpleCommandQueue {')
    end = source.index('\n\t// Helper class to manage RID_Owner', start)
    extracted = source[start:end]
    assert 'memcpy(cmd_buffer, (char *)cmd, size);' in extracted, 'source is not the expected memcpy queue'
    fixed = extracted.replace('virtual void call() = 0;', 'virtual void call() = 0;\n\t\t\tvirtual void move_to(void *destination) = 0;', 1)
    marker = '\t\t\tvoid call() override {'
    assert fixed.count(marker) == 1
    fixed = fixed.replace(marker, '\t\t\tvoid move_to(void *destination) override { new (destination) Command(std::move(*this)); }\n\n'+marker, 1)
    fixed = fixed.replace('char cmd_buffer[MAX_COMMAND_SIZE];', 'alignas(std::max_align_t) char cmd_buffer[MAX_COMMAND_SIZE];', 1)
    old = '''\t\t\t\t// Copy command to local buffer so we can safely unlock during execution.
\t\t\t\t// The copy is shallow - complex types like Callable share internal data with the original.
\t\t\t\tmemcpy(cmd_buffer, (char *)cmd, size);

\t\t\t\tread_ptr += size;

\t\t\t\t// Unlock while executing the command (allows new commands to be pushed)
\t\t\t\tp_lock.temp_unlock();
\t\t\t\treinterpret_cast<CommandBase *>(cmd_buffer)->call();
\t\t\t\tp_lock.temp_relock();

\t\t\t\t// Destroy the ORIGINAL after execution completes.
\t\t\t\t// We must not destroy before call() because the backup is a shallow copy
\t\t\t\t// that shares internal data (e.g., Callable's bound arguments).
\t\t\t\t// Handle potential realloc that may have happened during unlock.
\t\t\t\tcmd = reinterpret_cast<CommandBase *>(&command_mem[read_ptr - size]);
\t\t\t\tcmd->~CommandBase();'''
    new = '''\t\t\t\tcmd->move_to(cmd_buffer);
\t\t\t\tcmd->~CommandBase(); // Moved-from command dies while queue storage is stable.
\t\t\t\tread_ptr += size;
\t\t\t\tp_lock.temp_unlock();
\t\t\t\tauto *local = reinterpret_cast<CommandBase *>(cmd_buffer);
\t\t\t\tlocal->call();
\t\t\t\tlocal->~CommandBase(); // Owning destruction is outside the queue mutex.
\t\t\t\tp_lock.temp_relock();'''
    assert fixed.count(old) == 1, 'flush source changed; review before adapting fixture'
    fixed = fixed.replace(old, new, 1)
    (args.output/'queue_original.inc').write_text(extracted, encoding='utf-8')
    (args.output/'queue_moved.inc').write_text(fixed, encoding='utf-8')
    fixtures = Path(__file__).parent/'fixtures'
    for name in ['simple_command_queue_std_compat.h', 'simple_command_queue_ownership_harness.cpp']:
        (args.output/name).write_bytes((fixtures/name).read_bytes())
    exe = args.output/'ownership_test.exe'
    command = [str(args.compiler), '-std=c++17', '-O0', '-g', '-Wall', '-Wextra', '-Wpedantic', str(args.output/'simple_command_queue_ownership_harness.cpp'), '-o', str(exe)]
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    env = os.environ.copy(); env['PATH'] = str(args.compiler.parent)+os.pathsep+env.get('PATH', '')
    compiler_version = subprocess.run([str(args.compiler), '--version'], capture_output=True, text=True, check=True, creationflags=flags).stdout
    built = subprocess.run(command, capture_output=True, text=True, env=env, creationflags=flags, timeout=60)
    (args.output/'compile.log').write_text(built.stdout+built.stderr, encoding='utf-8')
    manifest = {'engine_header':str(args.source), 'engine_header_sha256':sha(original_bytes), 'extracted_queue_sha256':sha(extracted.encode()), 'candidate_queue_sha256':sha(fixed.encode()), 'compiler':compiler_version, 'compile_command':command, 'compile_exit':built.returncode,
                'limits':['single-thread; no debugger or native engine process','control blocks outlive every owner and are never freed by the counter','std::tuple/std::vector/std::mutex compatibility, not full Godot container/ABI validation','payloads align <=8 and commands stay under initial 64KiB reserve; does not validate raw-buffer growth relocation','original memcpy has nontrivial-object lifetime UB; counters are an observation, not a proof of defined baseline behavior','test candidate is generated in the external output directory; no production C++ source edits']}
    if built.returncode:
        (args.output/'result.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8'); print(built.stderr); return built.returncode
    for variant in ['original', 'moved']:
        result = subprocess.run([str(exe), variant], capture_output=True, text=True, env=env, creationflags=flags, timeout=10)
        (args.output/(variant+'.jsonl')).write_text(result.stdout, encoding='utf-8')
        (args.output/(variant+'.stderr')).write_text(result.stderr, encoding='utf-8')
        manifest[variant] = {'exit':result.returncode, 'cases':[json.loads(line) for line in result.stdout.splitlines()], 'stderr':result.stderr}
    (args.output/'result.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'source_sha':manifest['engine_header_sha256'], 'queue_sha':manifest['extracted_queue_sha256'], **{name:{'exit':manifest[name]['exit'], 'failed':[row['case'] for row in manifest[name]['cases'] if not row['passed']]} for name in ['original','moved']}}))
    return 0 if manifest['original']['exit'] == 1 and manifest['moved']['exit'] == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
