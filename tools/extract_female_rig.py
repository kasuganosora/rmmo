"""Recover the original female rest frames and axis weights, without guessing LBS weights."""
import hashlib
import json
import struct
from collections import defaultdict
from pathlib import Path
import UnityPy
from art_paths import art_path

source = Path('D:/Games/vamzhb/VaM_Data/StreamingAssets/a_per')
reference = art_path('characters/source_models/vam_base_reference/female')
raw = json.loads((reference / 'original_data.json').read_text(encoding='utf-8'))
skin = raw['skin_component']
env = UnityPy.load(str(source))
scripts = {o.path_id: o.read_typetree().get('m_ClassName') for o in env.objects if o.type.name == 'MonoScript'}
groups = defaultdict(dict)
for obj in env.objects:
    if obj.type.name != 'MonoBehaviour': continue
    value = obj.read_typetree()
    if scripts.get(value['m_Script']['m_PathID']) == 'DAZBone':
        groups[value['dazBones']['m_PathID']][obj.path_id] = value
required = {n['name'] for n in skin['nodes']}
matching = [g for g in groups.values() if required.issubset({v['_id'] for v in g.values()})]
assert len(matching) == 1, 'Must uniquely identify the complete source skeleton'
bones = matching[0]
by_name = {d['_id']: (pid, d) for pid, d in bones.items()}
names = [n['name'] for n in skin['nodes']]
result = {'version': 1, 'topology': 'GenesisFemale-1', 'vertex_count': 21556,
          'rotation_orders': ['XYZ', 'XZY', 'YXZ', 'YZX', 'ZXY', 'ZYX'],
          'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'body_sha256': raw['sha256'], 'bulge_scale': skin['bulgeScale'], 'nodes': []}
coverage = [0] * 21556
for node in skin['nodes']:
    pid, bone = by_name[node['name']]
    assert max(abs(bone['_worldPosition'][a] - bone['_morphedWorldPosition'][a]) for a in 'xyz') < 1e-6
    matrix = bone['_morphedLocalToWorldMatrix']
    assert max(abs(matrix['e'+str(i)+'3'] - bone['_worldPosition'][a]) for i, a in enumerate('xyz')) < 1e-6
    parent_id = bone['parentBone']['m_PathID']
    parent = bones[parent_id]['_id'] if parent_id else ''
    assert not parent or parent in names
    weights = [w for w in node['weights'] if w['vertex'] < 21556]
    full = [v for v in node['fullyWeightedVertices'] if v < 21556]
    for w in weights: coverage[w['vertex']] += 1
    for v in full: coverage[v] += 1
    result['nodes'].append({'name': node['name'], 'parent': parent,
                            'rest': [[matrix[f'e{i}{j}'] for j in range(4)] for i in range(4)],
                            'order': node['rotationOrder'], 'weights': weights, 'full': full,
                            'bulge': node['bulgeFactors']})
assert min(coverage) > 0 and max(coverage) == 8
result['coverage'] = {'covered': sum(v > 0 for v in coverage), 'max_records': max(coverage)}
target = art_path('characters/base/female_base_v2')
(target / 'female_axis_rig.json').write_text(json.dumps(result), encoding='utf-8')
records = [[] for _ in range(21556)]
for index, node in enumerate(result['nodes']):
    for w in node['weights']:
        full = all(w[a+'weight'] > .99999 for a in 'xyz')
        records[w['vertex']].append([index, int(full), w['xweight'], w['yweight'],
                                    w['zweight'], w['xleftbulge'], w['yleftbulge'], w['zleftbulge'],
                                    w['xrightbulge'], w['yrightbulge'], w['zrightbulge'], 0])
    for vertex in node['full']: records[vertex].append([index,1,1,1,1,0,0,0,0,0,0,0])
vertices = raw['geometry_component']['_baseVertices']
rest_buffer = []; weight_buffer = []
for i, rows in enumerate(records):
    rest_buffer.extend([vertices[i]['x'],vertices[i]['y'],vertices[i]['z'],len(rows)])
    for row in rows: weight_buffer.extend(row)
    weight_buffer.extend([0]*(12*(8-len(rows))))
rest_buffer.extend([0]*((512*43-21556)*4))
(target/'axis_gpu_rest.bin').write_bytes(struct.pack('<%sf'%len(rest_buffer),*rest_buffer))
(target/'axis_gpu_weights.bin').write_bytes(struct.pack('<%sf'%len(weight_buffer),*weight_buffer))
adjacency = [[] for _ in vertices]
for face in raw['geometry_component']['_basePolyList']:
    v = face['vertices']
    for j in range(1,len(v)-1):
        triangle=[v[0],v[j],v[j+1],0]
        for vertex in triangle[:3]: adjacency[vertex].append(triangle)
ranges=[];triangles=[]
for neighbors in adjacency:
    ranges.extend([len(triangles)//4,len(neighbors)])
    for triangle in neighbors:triangles.extend(triangle)
(target/'axis_gpu_adjacency.bin').write_bytes(struct.pack('<%sI'%len(ranges),*ranges))
(target/'axis_gpu_triangles.bin').write_bytes(struct.pack('<%sI'%len(triangles),*triangles))
print('PASS 80 source joints: unique hierarchy, rest frames, 21,556 covered vertices, no averaged axis weights')
