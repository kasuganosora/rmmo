"""One-level Catmull-Clark stencils evaluated AFTER body deformation at runtime."""
import json
import struct
from collections import defaultdict
from art_paths import art_path

raw = json.loads(art_path('characters/source_models/vam_base_reference/female/original_data.json').read_text(encoding='utf-8'))['geometry_component']
points = [[v[a] for a in 'xyz'] for v in raw['_baseVertices']]
polys = [p['vertices'] for p in raw['_basePolyList']]
adjacent_faces = [[] for _ in points]
adjacent_edges = [set() for _ in points]
edges = {}
for fi, face in enumerate(polys):
    for j, v in enumerate(face):
        adjacent_faces[v].append(fi)
        edge = tuple(sorted((v, face[(j+1) % len(face)])))
        edges.setdefault(edge, []).append(fi)
        for q in edge: adjacent_edges[q].add(edge)

def add(dst, src, scale):
    for key, value in src.items(): dst[key] += value * scale

face_weights = [{i: 1 / len(f) for i in f} for f in polys]
stencils = []
for i in range(len(points)):
    weights = defaultdict(float)
    boundary = [e for e in adjacent_edges[i] if len(edges[e]) == 1]
    if boundary:
        assert len(boundary) == 2
        weights[i] = .75
        for e in boundary: weights[next(v for v in e if v != i)] += .125
    else:
        n = len(adjacent_faces[i]);assert n == len(adjacent_edges[i]) and n > 0
        weights[i] += (n-3)/n
        for fi in adjacent_faces[i]: add(weights, face_weights[fi], 1/(n*n))
        for e in adjacent_edges[i]:
            for v in e: weights[v] += 1/(n*n)
    stencils.append(dict(weights))
edge_ids = {}
for edge, faces in edges.items():
    weights = defaultdict(float)
    if len(faces) == 1:
        for v in edge: weights[v] = .5
    else:
        assert len(faces) == 2
        for v in edge: weights[v] += .25
        for fi in faces: add(weights, face_weights[fi], .25)
    edge_ids[edge] = len(stencils);stencils.append(dict(weights))
face_start = len(stencils)
stencils.extend(face_weights)
display_points = [[sum(points[i][axis]*w for i,w in s.items()) for axis in range(3)] for s in stencils]
assert all(abs(sum(s.values())-1)<1e-6 for s in stencils)
surfaces = [[] for _ in raw['_materialNames']]
def avg(a,b):return [(a[k]+b[k])/2 for k in range(2)]
for fi, face in enumerate(polys):
    uv = [[raw['_OrigUV'][i][a] for a in 'xy'] for i in raw['_UVPolyList'][fi]['vertices']]
    center = [sum(v[a] for v in uv)/len(uv) for a in range(2)]
    for j,v in enumerate(face):
        prev=(j-1)%len(face);nxt=(j+1)%len(face)
        ids=[v,edge_ids[tuple(sorted((v,face[nxt])))],face_start+fi,edge_ids[tuple(sorted((v,face[prev])))]]
        uvs=[uv[j],avg(uv[j],uv[nxt]),center,avg(uv[prev],uv[j])]
        # Clockwise Godot source convention; Blender export also keeps this winding.
        surfaces[raw['_basePolyList'][fi]['materialNum']].append([ids,uvs])
flat=[];ranges=[]
for s in stencils:
    ranges.append([len(flat),len(s)])
    flat.extend((float(i),w,0.,0.) for i,w in s.items())
width=1024;height=(len(flat)+width-1)//width
flat.extend([(0.,0.,0.,0.)]*(width*height-len(flat)))
target=art_path('characters/base/female_base_v2')
(target/'subdivision_stencils.rgba32f').write_bytes(b''.join(struct.pack('<4f',*v) for v in flat))
data={'points':points,'display_points':display_points,'ranges':ranges,'surfaces':surfaces,
      'materials':raw['_materialNames'],'stencil_size':[width,height],
      'base_faces':polys,'display_triangles':sum(len(p)*2 for p in polys)}
(target/'female_display_topology.json').write_text(json.dumps(data),encoding='utf-8')
print('PASS normalized post-deformation subdivision:',len(stencils),'display points,',data['display_triangles'],'triangles')
