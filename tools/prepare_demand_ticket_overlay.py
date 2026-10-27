"""Create a disposable Godot project with diagnostic-only scheduler instrumentation.

No real project or asset package is modified. The overlay has its own .godot
cache. Exact source anchors are checked; unexpected loader versions fail closed.
Copying and hashing warm OS caches, so resulting runs are not disk-cold samples.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BOUNDARY = Path('D:/code/rmmo_runtime/review_artifacts')
DIRS = ('addons', 'scenes', 'scripts', 'tools')
LOADER = Path('scripts/world3d/deferred_asset_loader.gd')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def files_snapshot(project):
    """Hash all copied source files, including newly added files and UIDs."""
    files = [project / 'project.godot']
    for name in DIRS:
        for path in (project / name).rglob('*'):
            if '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            if path.is_symlink():
                raise ValueError('source symlink is not supported: ' + str(path))
            if path.is_file():
                files.append(path)
    return {path.relative_to(project).as_posix(): sha(path.read_bytes()) for path in sorted(files)}


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('injection anchor missing or ambiguous: ' + repr(old[:120]))
    return text.replace(old, new, 1)


def instrument(source):
    text = source
    pairs = [
        ('var _demand_membership:Dictionary={} # Per live ticket; spatial candidates only, never readiness/leases.\n',
         'var _demand_membership:Dictionary={} # Per live ticket; spatial candidates only, never readiness/leases.\nvar _demand_ticket_trace:RefCounted=null # Diagnostic overlay only.\n'),
        ('func demand_revision_trace_snapshot()->Dictionary:\n',
         'func start_demand_ticket_trace(capacity:int=1024)->void:\n\t_demand_ticket_trace=preload("res://tools/diagnostics/demand_ticket_trace.gd").new(capacity)\n\nfunc demand_ticket_trace_snapshot()->Dictionary:\n\treturn _demand_ticket_trace.snapshot() if _demand_ticket_trace!=null else {}\n\nfunc stop_demand_ticket_trace()->Dictionary:\n\tvar value:Dictionary=demand_ticket_trace_snapshot();_demand_ticket_trace=null;return value\n\nfunc demand_revision_trace_snapshot()->Dictionary:\n'),
        ('\t\tvar eligible:Array=[]\n\t\tinput_rows+=candidates_for_demand.size()\n\t\tfor item:Dictionary in candidates_for_demand:\n',
         '\t\tvar eligible:Array=[]\n\t\tvar ticket_trace:Variant=null\n\t\tif _demand_ticket_trace!=null:ticket_trace=_demand_ticket_trace.begin_ticket(id,origin,priority,_demand_revision,memberships.has(id),candidates_for_demand.size(),support_visits)\n\t\tinput_rows+=candidates_for_demand.size()\n\t\tfor item:Dictionary in candidates_for_demand:\n\t\t\tif ticket_trace!=null:_demand_ticket_trace.member(ticket_trace,item.get("record"))\n'),
        ('\t\t\t\tif excluded:\n', '\t\t\t\tif excluded:\n\t\t\t\t\tif ticket_trace!=null:ticket_trace.kind_excluded+=1\n'),
        ('\t\t\tif item.get("published",false):continue\n\t\t\tvar uuid:String=item.record.uuid\n',
         '\t\t\tif item.get("published",false):\n\t\t\t\tif ticket_trace!=null:ticket_trace.published+=1\n\t\t\t\tcontinue\n\t\t\tvar uuid:String=item.record.uuid\n'),
        ('\t\t\tvar present:bool=not winner.is_empty() and (not reuse_catalogue or int(winner[5])==epoch)\n',
         '\t\t\tvar present:bool=not winner.is_empty() and (not reuse_catalogue or int(winner[5])==epoch)\n\t\t\tif ticket_trace!=null:\n\t\t\t\tif present:ticket_trace.duplicate_uuid+=1\n\t\t\t\telse:ticket_trace.new_uuid+=1\n'),
        ('\t\t\telif not dominated and score<float(winner[0]):\n',
         '\t\t\telif not dominated and score<float(winner[0]):\n\t\t\t\tif ticket_trace!=null:ticket_trace.winner_changes+=1\n'),
        ('\t\t\tprofile.demand_membership_misses=int(profile.get("demand_membership_misses",0))+1\n\tprofile.demand_input_rows=',
         '\t\t\tprofile.demand_membership_misses=int(profile.get("demand_membership_misses",0))+1\n\t\tif ticket_trace!=null:_demand_ticket_trace.end_ticket(ticket_trace,support_visits)\n\tprofile.demand_input_rows='),
    ]
    for old, new in pairs:
        text = replace_once(text, old, new)
    return text


def prepare(output):
    boundary = BOUNDARY.resolve(strict=True)
    output = Path(output).resolve()
    if output == boundary or not output.is_relative_to(boundary):
        raise ValueError('output must be strictly inside review_artifacts')
    if output.exists():
        raise FileExistsError('refusing to overwrite overlay')
    source_files = files_snapshot(ROOT)
    before = (ROOT / LOADER).read_bytes()
    source = before.decode('utf-8').replace('\r\n', '\n')
    patched = instrument(source)
    output.mkdir(parents=True)
    for name in DIRS:
        shutil.copytree(ROOT / name, output / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(ROOT / 'project.godot', output / 'project.godot')
    if files_snapshot(ROOT) != source_files or files_snapshot(output) != source_files:
        raise ValueError('source changed while overlay was copied or overlay copy differs')
    (output / LOADER).write_text(patched, encoding='utf-8', newline='\n')
    diff = ''.join(difflib.unified_diff(source.splitlines(True), patched.splitlines(True), fromfile='original', tofile='overlay'))
    (output / 'ticket_trace_injection.diff').write_bytes(diff.encode('utf-8'))
    manifest = {'original_loader_sha256': sha(before), 'overlay_loader_sha256': sha((output / LOADER).read_bytes()),
                'source_project': str(ROOT), 'output_project': str(output),
                'copy_dirs': DIRS, 'project_sha256': sha((output / 'project.godot').read_bytes()),
                'injection_diff_sha256': sha(diff.encode('utf-8')), 'source_files': source_files,
                'overlay_files': files_snapshot(output), 'finalized_after_import': False,
                'contract': 'Diagnostic project copy only. No shared .godot cache. Copy/hash warms OS cache. Timings include diagnostic work; verify fixture and all source files before/after separately.'}
    (output / 'ticket_trace_overlay_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest


def finalize(output):
    boundary = BOUNDARY.resolve(strict=True)
    output = Path(output).resolve(strict=True)
    if output == boundary or not output.is_relative_to(boundary):
        raise ValueError('output must be strictly inside review_artifacts')
    manifest_path = output / 'ticket_trace_overlay_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if Path(manifest['source_project']).resolve() != ROOT or Path(manifest['output_project']).resolve() != output:
        raise ValueError('overlay identity mismatch')
    if files_snapshot(ROOT) != manifest['source_files']:
        raise ValueError('original source changed since overlay creation')
    initial = manifest['overlay_files']
    after = files_snapshot(output)
    if any(after.get(path) != digest for path, digest in initial.items()):
        raise ValueError('existing overlay source changed during cache initialization')
    added = set(after) - set(initial)
    if any(not path.endswith(('.gd.uid', '.gdshaderinc.uid')) or path[:-4] not in initial for path in added):
        raise ValueError('unexpected new overlay source file during cache initialization')
    manifest['overlay_files'] = after
    manifest['generated_uid_files'] = sorted(added)
    manifest['finalized_after_import'] = True
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--finalize', action='store_true', help='Freeze overlay source hashes after private Godot class-cache initialization')
    args = p.parse_args()
    manifest = finalize(args.output) if args.finalize else prepare(args.output)
    print(json.dumps({'output':manifest['output_project'], 'source_count':len(manifest['source_files']),
                      'overlay_count':len(manifest['overlay_files']), 'finalized_after_import':manifest['finalized_after_import']}))


if __name__ == '__main__':
    main()
