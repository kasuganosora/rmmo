"""Build confined reference-map validation fixtures, never modify production assets/caches.

The only engine operation invokes the CPU reference reader/writer; no native model build.
"""
import copy
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

REPO = Path('D:/code/rmmo')
CONTENT = Path('D:/code/rmmo_runtime')
SOURCE = CONTENT / 'maps/medieval_river_town/map.gltf'
EXPECTED = '779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f'
HANDOFF = REPO / 'review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json'
GODOT = Path('D:/tools/godot/Godot_v4.7.2-stable_win64.exe')


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def canonical(path):
    return Path(path).resolve().as_posix()


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def load_glb(path):
    raw = Path(path).read_bytes()
    magic, version, total = struct.unpack_from('<III', raw)
    assert (magic, version, total) == (0x46546C67, 2, len(raw))
    chunks = []
    cursor = 12
    while cursor < len(raw):
        size, kind = struct.unpack_from('<II', raw, cursor)
        assert size % 4 == 0 and cursor + 8 + size <= len(raw)
        chunks.append((kind, raw[cursor + 8:cursor + 8 + size]))
        cursor += 8 + size
    assert cursor == len(raw) and chunks[0][0] == 0x4E4F534A
    assert sum(kind == 0x4E4F534A for kind, _ in chunks) == 1
    return json.loads(chunks[0][1]), chunks[1:]


def encode_glb(doc, tail):
    encoded = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    chunks = [(0x4E4F534A, encoded)] + tail
    size = 12 + sum(8 + len(data) for _, data in chunks)
    return struct.pack('<III', 0x46546C67, 2, size) + b''.join(struct.pack('<II', len(data), kind) + data for kind, data in chunks)


def strip_picking(doc):
    value = copy.deepcopy(doc)
    removed = {}
    for index, node in enumerate(value.get('nodes', [])):
        extras = node.get('extras', {})
        if 'rmmo_editor_picking' in extras:
            removed[index] = extras.pop('rmmo_editor_picking')
    return value, removed


def make_combined(root, handoff, metadata, protected):
    preferred_by_original = {canonical(r['original']): r for r in handoff['preferred']}
    fallback_origins = {canonical(r['candidate']): canonical(r['original']) for r in handoff['exact_fallbacks']}
    mappings = {canonical(r['original']): canonical(r['candidate']) for r in handoff['preferred']}
    evidence = []
    for row in metadata['rows']:
        if row['status'] != 'candidate_ready_metadata_only':
            continue
        base_path = Path(row['path']); donor_path = Path(row['candidate'])
        protected[canonical(base_path)] = row['sha256']
        protected[canonical(donor_path)] = row['candidate_sha256']
        assert sha(base_path) == row['sha256'] and sha(donor_path) == row['candidate_sha256']
        base, base_tail = load_glb(base_path)
        donor, donor_tail = load_glb(donor_path)
        plain, tagged = strip_picking(donor)
        assert plain == base and base_tail == donor_tail and tagged
        assert not strip_picking(base)[1]
        origin = fallback_origins.get(canonical(base_path), canonical(base_path))
        preferred = preferred_by_original.get(origin)
        receiver_path = Path(preferred['candidate']) if preferred else base_path
        receiver, receiver_tail = load_glb(receiver_path)
        # Node identity/topology/pose/mesh assignment/existing extras must match exactly.
        assert receiver.get('nodes') == base.get('nodes')
        assert receiver.get('scenes') == base.get('scenes') and receiver.get('scene') == base.get('scene')
        assert not strip_picking(receiver)[1]
        combined = copy.deepcopy(receiver)
        for index, flag in tagged.items():
            assert set(flag) == {'version', 'group', 'role'} and flag['version'] == 1
            assert flag['role'] in ['canonical', 'render_lod'] and flag['group']
            if flag['role'] == 'render_lod':
                assert combined['nodes'][index]['extras']['rmmo_collision'] == 'none'
            combined['nodes'][index]['extras']['rmmo_editor_picking'] = copy.deepcopy(flag)
        assert sum(flag['role'] == 'canonical' for flag in tagged.values()) == 1
        encoded = encode_glb(combined, receiver_tail)
        digest = hashlib.sha256(encoded).hexdigest()
        target = root / 'combined_assets' / (digest + '.glb')
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(encoded)
        written, written_tail = load_glb(target)
        assert strip_picking(written)[0] == receiver and written_tail == receiver_tail
        assert strip_picking(written)[1] == tagged
        mappings[origin] = canonical(target)
        evidence.append({'label': row['label'], 'original_map_path': origin, 'receiver': canonical(receiver_path),
                         'receiver_sha256': sha(receiver_path), 'donor': canonical(donor_path), 'donor_sha256': row['candidate_sha256'],
                         'candidate': canonical(target), 'candidate_sha256': digest, 'tagged_nodes': sorted(tagged),
                         'all_other_json_exact': True, 'bin_and_other_chunks_exact': True, 'nodes_identity_exact': True,
                         'status': 'metadata_only_fixture_pending_joint_gpu_http_validation'})
    assert len(evidence) == 7 and len(mappings) == 14
    return mappings, evidence


def main():
    assert '--run' in sys.argv, 'Explicit --run required'
    assert sha(SOURCE) == EXPECTED
    handoff = json.loads(HANDOFF.read_text(encoding='utf-8'))
    assert handoff['preferred_count'] == len(handoff['preferred']) == 11
    metadata_path = Path(handoff['optional_editor_picking_manifest'])
    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    protected = {canonical(SOURCE): EXPECTED, canonical(HANDOFF): sha(HANDOFF), canonical(metadata_path): sha(metadata_path)}
    for row in handoff['preferred']:
        for key, digest_key in [('original', 'original_sha256'), ('candidate', 'candidate_sha256')]:
            path = Path(row[key]); digest = row[digest_key]
            assert sha(path) == digest, str(path)
            protected[canonical(path)] = digest
    root = CONTENT / 'cache/world3d' / ('joint_model_validation_20261011_' + str(time.time_ns()))
    assert root.parent.resolve() == (CONTENT / 'cache/world3d').resolve() and not root.exists()
    root.mkdir()
    print('FIXTURE_ROOT', root, flush=True)
    mappings = {'preferred': {canonical(r['original']): canonical(r['candidate']) for r in handoff['preferred']}}
    mappings['combined'], merged = make_combined(root, handoff, metadata, protected)
    data = json.loads(SOURCE.read_text(encoding='utf-8'))
    extras = data['nodes'][0]['extras']
    assert len(extras['rmmo_records']) == 4437 and len(extras['building_instances']) == 61
    dependencies = extras['rmmo_resource_dependencies']
    baseline = root / 'baseline/map.gltf'
    baseline.parent.mkdir(); shutil.copyfile(SOURCE, baseline)
    dep_bytes = 0
    for uri, digest in dependencies.items():
        assert uri == 'map.gltf.resources/' + digest + '.rmres'
        origin = SOURCE.parent / uri; target = baseline.parent / uri
        assert not origin.is_symlink() and origin.resolve().parent == (SOURCE.parent / 'map.gltf.resources').resolve()
        assert sha(origin) == digest
        target.parent.mkdir(exist_ok=True); shutil.copyfile(origin, target)
        assert sha(target) == digest
        dep_bytes += target.stat().st_size
    assert sha(baseline) == EXPECTED
    spec = {'source': canonical(SOURCE), 'source_sha256': EXPECTED, 'root': canonical(root), 'mappings': mappings}
    write_json(root / 'fixture_spec.json', spec)
    result = subprocess.run([str(GODOT), '--headless', '--path', str(REPO), '--script', 'res://tools/build_joint_model_fixture.gd', '--',
                             '--spec=' + canonical(root / 'fixture_spec.json')], cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    (root / 'build_cpu.log').write_bytes(result.stdout)
    print(result.stdout.decode('utf-8', errors='replace'), flush=True)
    assert result.returncode == 0 and b'SCRIPT ERROR:' not in result.stdout and b'\nERROR:' not in result.stdout
    report = json.loads((root / 'map_fixture_report.json').read_text(encoding='utf-8'))
    assert report['passed'] and not report['failures']
    for path, expected in protected.items():
        assert sha(path) == expected, 'Protected source changed: ' + path
    for uri, digest in dependencies.items():
        assert sha(SOURCE.parent / uri) == digest, 'Formal definition changed: ' + uri
    manifest = {'version': 1, 'scope': 'Isolated joint model fixtures; not formal integration or GPU acceptance',
                'root': canonical(root), 'source_sha256': EXPECTED, 'protected_source_sha256': protected,
                'preferred_handoff': canonical(HANDOFF), 'preferred_types': 11, 'combined_metadata_types': 7,
                'metadata_transplants': merged, 'fixtures': report['fixtures'], 'cpu_report': canonical(root / 'map_fixture_report.json'),
                'cpu_log': canonical(root / 'build_cpu.log'), 'source_reference_dependencies': len(dependencies),
                'baseline_dependency_bytes': dep_bytes, 'source_and_dependencies_unchanged': True,
                'no_native_caches_built': True, 'no_gpu_or_http_test': True,
                'builder_sha256': {canonical(Path(__file__)): sha(__file__), canonical(REPO / 'tools/build_joint_model_fixture.gd'): sha(REPO / 'tools/build_joint_model_fixture.gd')}}
    write_json(root / 'fixture_manifest.json', manifest)
    print(json.dumps({'manifest': canonical(root / 'fixture_manifest.json'), 'fixtures': {k: {x: v[x] for x in ['map', 'sha256', 'records', 'houses', 'changed_instances']} for k, v in report['fixtures'].items()}}, indent=2), flush=True)


if __name__ == '__main__':
    main()
