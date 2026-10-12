"""Read-only exported GLB cost audit; not a runtime benchmark."""
import hashlib
import io
import json
import struct
from collections import Counter
from pathlib import Path
from PIL import Image

OUT = Path(__file__).parent
BASE = OUT.parent

def audit(path):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    accessors = doc['accessors']
    meshes = doc['meshes']
    def mesh_cost(mesh):
        primitives = mesh['primitives']
        return sum(accessors[p['indices']]['count'] // 3 for p in primitives)
    counts = [mesh_cost(m) for m in meshes]
    reachable = set()
    def visit(index):
        if index in reachable:
            return
        reachable.add(index)
        for child in doc['nodes'][index].get('children', []):
            visit(child)
    for index in doc['scenes'][doc.get('scene', 0)].get('nodes', []):
        visit(index)
    rows = []
    for index, node in enumerate(doc['nodes']):
        if 'mesh' not in node:
            continue
        ex = node.get('extras', {})
        rows.append({'name': node.get('name'), 'triangles': counts[node['mesh']],
                     'default_scene': index in reachable,
                     'mesh': node['mesh'], 'surfaces': len(meshes[node['mesh']]['primitives']),
                     'level': ex.get('lod_level', -1), 'part': ex.get('source_part', ''),
                     'collision': ex.get('rmmo_collision', 'unspecified')})
    images = []
    for im in doc.get('images', []):
        view = doc['bufferViews'][im['bufferView']]
        start = view.get('byteOffset', 0)
        payload = binary[start:start + view['byteLength']]
        pic = Image.open(io.BytesIO(payload))
        extrema = pic.getextrema()
        images.append({'name': im.get('name'), 'bytes': len(payload),
                       'width': pic.width, 'height': pic.height, 'mode': pic.mode,
                       'extrema': extrema, 'sha256': hashlib.sha256(payload).hexdigest()})
    mesh_views = set()
    level_meshes = {}
    active_rows = [r for r in rows if r['default_scene']]
    active_meshes = {r['mesh'] for r in active_rows}
    for level in sorted({r['level'] for r in active_rows}):
        ids = {r['mesh'] for r in active_rows if r['level'] == level}
        level_meshes[str(level)] = {'instanced_triangles': sum(r['triangles'] for r in active_rows if r['level'] == level),
                                  'unique_triangles': sum(counts[i] for i in ids), 'unique_meshes': len(ids)}
    for mesh in meshes:
        for prim in mesh['primitives']:
            for idx in [prim['indices'], *prim['attributes'].values()]:
                mesh_views.add(accessors[idx]['bufferView'])
    return {'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(), 'file_bytes': len(raw),
            'levels': level_meshes, 'all_exported_unique_triangles': sum(counts),
            'default_scene_unique_triangles': sum(counts[i] for i in active_meshes),
            'default_scene_unique_meshes': len(active_meshes), 'scene_count': len(doc['scenes']),
            'outside_default_scene': [r for r in rows if not r['default_scene']],
            'encoded_mesh_buffer_bytes': sum(doc['bufferViews'][v]['byteLength'] for v in mesh_views),
            'embedded_texture_bytes': sum(i['bytes'] for i in images),
            'collision_triangles': sum(r['triangles'] for r in rows if r['collision'] == 'block'),
            'collision_nodes': [r for r in rows if r['collision'] == 'block'],
            'nodes': sorted(rows, key=lambda r: (-r['level'], -r['triangles'])), 'images': images}

source = audit(BASE / 'alarm_tower_materials_v3_20261011/guild_alarm_tower.glb')
game = audit(OUT / 'guild_alarm_tower_game.glb')
report = {'source': source, 'game': game,
          'scope': 'Exported GLB geometry and embedded-image payload audit; no FPS or GPU residency claim.'}
(OUT / 'tower_deep_cost_audit.json').write_text(json.dumps(report, indent=2), encoding='utf8')
for label, data in [('source', source), ('game', game)]:
    print(label, json.dumps({k: v for k, v in data.items() if k not in ['images', 'nodes']}))
print('far_parts', json.dumps([r for r in game['nodes'] if r['level'] == 2]))
print('images', json.dumps(game['images']))
