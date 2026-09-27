"""Convert source wrap anchors to the frozen clean body, retaining original garments.

Each garment control point has one surface frame (shared across UV seams).
Grafted anchors are explicitly rebound to a clean-body triangle, never clamped.
This is surface attachment data, not a conversion of the source cloth simulator.
"""
import hashlib
import argparse
import json
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from PIL import Image
from inspect_vam_cloth_physics import decode_tail
from art_paths import art_path


def frame(points):
    tangent = points.mean(axis=0) - points[0]
    normal = -np.cross(points[1]-points[0], points[2]-points[0])
    normal /= np.linalg.norm(normal)
    # Tangent length carries surface stretch. Normal offsets retain thickness.
    return points[0], np.stack([tangent, np.cross(tangent, normal), normal], axis=1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', help='Rebuild one source group')
    args = parser.parse_args()
    body_path = art_path('characters/base/female_base_v2/female_display_topology.json')
    body_data = json.loads(body_path.read_text())
    body = np.asarray(body_data['points'])
    triangles = np.array([(p[0], p[i], p[i+1]) for p in body_data['base_faces']
                          for i in range(1, len(p)-1)], dtype=np.int32)
    areas = np.linalg.norm(np.cross(body[triangles[:, 1]]-body[triangles[:, 0]],
                                    body[triangles[:, 2]]-body[triangles[:, 0]]), axis=1)
    triangles = triangles[areas > 1e-10]
    tree = cKDTree(body[triangles].mean(axis=1))
    source_root = art_path('characters/source_models/garment_validation_set')
    output_root = art_path('characters/equipment/surface_bound')
    catalog = []
    for folder in sorted(source_root.glob('*/item_*')):
        if args.only and folder.parent.name != args.only: continue
        source_path = folder / 'clothing_data.json'
        data = json.loads(source_path.read_text())
        points = np.asarray(data['vertices'])
        point_uv = np.full(len(points), -1, dtype=int)
        for face, uv_face in zip(data['faces'], data['uv_faces']):
            for v, u in zip(face['vertices'], uv_face['vertices']):
                if point_uv[v] < 0: point_uv[v] = u
        assert np.all(point_uv >= 0), 'Unreferenced garment vertex needs an explicit policy'
        bindings, rebound = [], 0
        for i, uv in enumerate(point_uv):
            ids = np.array(data['bindings'][uv][1:4], dtype=int)
            invalid = np.any(ids >= len(body)) or len(set(ids)) != 3
            if not invalid:
                invalid = np.linalg.norm(np.cross(body[ids[1]]-body[ids[0]], body[ids[2]]-body[ids[0]])) < 1e-10
            if invalid:
                # Nearest triangle centroid provides a local surface frame; the
                # complete offset is retained, so rest shape stays exact.
                ids = triangles[tree.query(points[i])[1]]
                rebound += 1
            center, basis = frame(body[ids])
            offset = np.linalg.solve(basis, points[i]-center)
            assert np.linalg.norm(center+basis@offset-points[i]) < 1e-10
            bindings.append([*map(int, ids), *map(float, offset)])
        edges = set()
        for face in data['faces']:
            p = face['vertices']
            for j in range(len(p)):
                edges.add(tuple(sorted((p[j], p[(j+1) % len(p)]))))
        config = json.loads(next(folder.glob('*.vaj')).read_text(encoding='utf-8-sig'))
        tail = decode_tail(next(folder.glob('*.vab')).read_bytes(), data['unparsed_tail_bytes'])
        material_settings = [{} for _ in data['materials']]
        for material in tail['materials']:
            suffix = material['alias'].lstrip('+')
            settings = next((s for s in config['storables'] if s['id'].endswith(suffix)), {})
            for slot in material['slots']:
                assert 0 <= slot < len(material_settings)
                material_settings[slot] = settings
        pins = np.ones(len(points), dtype=np.float32)
        physics = tail['physics']
        physics_to_base = {}
        if physics:
            for i, uv in enumerate(point_uv):
                physics_id = physics['mesh_to_physics'][uv]
                assert 0 <= physics_id < len(physics['points'])
                # Cached particles include source wrap thickness/morph offsets.
                # Identity comes from the serialized UV map, not proximity.
                # Rest distances below are rebuilt from the original garment.
                assert np.linalg.norm(points[i]-physics['points'][physics_id]) < .2
                physics_to_base[physics_id] = i
                pins[i] = physics['blend'][uv]**4
            for face, uv_face in zip(data['faces'], data['uv_faces']):
                for v, u in zip(face['vertices'], uv_face['vertices']):
                    assert physics['mesh_to_physics'][u] == physics['mesh_to_physics'][point_uv[v]]
        samples = [[] for _ in points]
        sim_maps = {}
        for material, name in enumerate(data['materials']):
            settings = material_settings[material]
            filename = settings.get('simTexture')
            if filename:
                sim_maps[material] = np.asarray(Image.open(folder/filename).convert('RGB'))[:, :, 0] / 255.0
        for face, uv_face in zip(data['faces'], data['uv_faces']):
            if face['material'] not in sim_maps: continue
            image = sim_maps[face['material']]
            h, w = image.shape
            for v, u in zip(face['vertices'], uv_face['vertices']):
                x, y = data['uv'][u]
                x = (x % 1.0)*w-.5; y = ((1.0-y) % 1.0)*h-.5
                ix, iy = int(np.floor(x)), int(np.floor(y)); fx, fy = x-ix, y-iy
                red = sum(image[(iy+dy)%h, (ix+dx)%w] * (fx if dx else 1-fx) * (fy if dy else 1-fy)
                          for dx in (0, 1) for dy in (0, 1))
                samples[v].append(red**4)
        for i, values in enumerate(samples):
            if values: pins[i] = max(values)  # A seam's strongest authored attachment wins.
        # Weld duplicate control positions; do not alter UVs or original render topology.
        edges.update(cKDTree(points).query_pairs(1e-6))
        neighbors = [set() for _ in points]
        for a, b in edges: neighbors[a].add(b); neighbors[b].add(a)
        constraints = [dict.fromkeys(n, 1.0) for n in neighbors]
        if physics:
            for field, strength in [('distance_groups', 1.0), ('bend_groups', .12), ('nearby_groups', .3)]:
                for group in physics[field]:
                    for a, b in group:
                        a, b = physics_to_base[a], physics_to_base[b]
                        constraints[a][b] = max(constraints[a].get(b, 0), strength)
                        constraints[b][a] = max(constraints[b].get(a, 0), strength)
        spans, links = [], []
        for a, row in enumerate(constraints):
            spans.append([len(links), len(row)])
            links.extend([[b, float(np.linalg.norm(points[a]-points[b])), strength, 0] for b, strength in sorted(row.items())])
        incident = [[] for _ in points]
        for face in data['faces']:
            p = face['vertices']
            for j in range(1, len(p)-1):
                tri = [p[0], p[j], p[j+1], 0]
                for v in tri[:3]: incident[v].append(tri)
        tri_spans, tri_links = [], []
        for row in incident: tri_spans.append([len(tri_links), len(row)]); tri_links.extend(row)
        output = output_root / folder.parent.name / folder.name
        output.mkdir(parents=True, exist_ok=True)
        result = dict(version=3, frame='surface_tangent_scale', body_vertex_count=len(body),
                      body_sha256=hashlib.sha256(body_path.read_bytes()).hexdigest(),
                      source_sha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                      source_relative=str(folder.relative_to(art_path(''))).replace('\\', '/'),
                      anchors=bindings, rebound_vertices=rebound,
                      edges=[[a, b, float(np.linalg.norm(points[a]-points[b]))] for a, b in sorted(edges)])
        (output/'binding.json').write_text(json.dumps(result, separators=(',', ':')))
        (output/'material_settings.json').write_text(json.dumps(material_settings))
        (output/'source_cloth_data.json').write_text(json.dumps(tail, separators=(',', ':')))
        np.column_stack([points, pins]).astype('<f4').tofile(output/'cloth_rest.bin')
        np.asarray(spans, dtype='<u4').tofile(output/'cloth_spans.bin')
        np.asarray(links, dtype='<f4').tofile(output/'cloth_links.bin')
        np.asarray(tri_spans, dtype='<u4').tofile(output/'cloth_tri_spans.bin')
        np.asarray(tri_links, dtype='<u4').tofile(output/'cloth_tri_links.bin')
        (output/'cloth.json').write_text(json.dumps(dict(vertices=len(points),
            freely_simulated=int(np.count_nonzero(pins<0.01)), anchored=int(np.count_nonzero(pins>.99)),
            pin_source='embedded authored blend, overridden by simTexture red when present, fourth power',
            status='project cloth prototype, not original source simulator')))
        # Two RGBA texels per vertex; all IDs fit exactly in float32.
        packed = np.zeros((int(np.ceil(len(points)*2/512)), 512, 4), dtype='<f4')
        flat = packed.reshape(-1, 4)
        error = 0.0
        for i, binding in enumerate(bindings):
            flat[i*2, :3] = binding[:3]
            flat[i*2+1, :3] = binding[3:]
            ids = np.asarray(binding[:3])
            center, basis = frame(body[ids])
            error = max(error, float(np.linalg.norm(center+basis@flat[i*2+1, :3]-points[i])))
        assert error < 1e-6
        (output/'anchors.rgba32f').write_bytes(packed.tobytes())
        catalog.append(dict(id=str(folder.relative_to(source_root)).replace('\\', '/'),
                            vertices=len(points), rebound=rebound, rest_error=error))
        print('PASS', catalog[-1], flush=True)
    if not args.only: (output_root/'catalog.json').write_text(json.dumps(catalog, indent=2))


if __name__ == '__main__': main()
