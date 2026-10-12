"""CPU-only exact vertex redundancy audit and independent remap candidate."""
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('D:/code/rmmo_runtime/art_sources/stone_bridge_optimization_20261009')


def main():
    audit = json.loads((ROOT / 'source_audit.json').read_text(encoding='utf8'))
    result = {'surfaces': [], 'textures': [], 'method': 'Exact bytes of every vertex channel; keep triangle order, materials, and collision mesh untouched.'}
    for mesh in audit['meshes']:
        for surface in mesh['surfaces']:
            slots = {s['slot']: s for s in surface['slots']}
            count = slots[0]['count']
            data = {k: np.fromfile(ROOT / s['file'], dtype=np.uint8).reshape(count, -1)
                    for k, s in slots.items() if k != 12}
            vertices = np.ascontiguousarray(np.concatenate(list(data.values()), axis=1))
            # Compare raw bytes; retain the first occurrence in original order.
            keys = vertices.view(np.dtype((np.void, vertices.shape[1]))).ravel()
            _, first, inv = np.unique(keys, return_index=True, return_inverse=True)
            order = np.argsort(first)
            stable_first = first[order]
            reorder = np.empty_like(order); reorder[order] = np.arange(len(order))
            remap = reorder[inv]
            indices = np.fromfile(ROOT / slots[12]['file'], dtype='<i4') if 12 in slots else np.arange(count, dtype=np.int32)
            row = {'mesh': mesh['index'], 'surface': surface['index'], 'vertices': count,
                   'triangles': len(indices) // 3, 'exact_unique_vertices': len(first),
                   'unreferenced_vertices': count - len(np.unique(indices)),
                   'vertex_bytes': vertices.nbytes, 'index_bytes': indices.nbytes}
            positions = np.fromfile(ROOT / slots[0]['file'], dtype='<f4').reshape(-1, 3)
            tris = positions[indices].reshape(-1, 3, 3)
            cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
            row['zero_area_triangles'] = int(np.count_nonzero(np.all(cross == 0, axis=1)))
            # Exact repeated ordered triangles only, not coincident opposite faces.
            tri_keys = np.ascontiguousarray(tris.reshape(-1, 9)).view(np.dtype((np.void, 36))).ravel()
            row['exact_repeated_ordered_triangles'] = len(tris) - len(np.unique(tri_keys))
            # Emit render-only recipe. Collision arrays stay byte-for-byte original.
            if mesh['index'] == audit['entries'][0][1][0]:
                name = f"remap_surface_{surface['index']}"
                stable_first.astype('<i4').tofile(ROOT / (name + '_first.bin'))
                remap[indices].astype('<i4').tofile(ROOT / (name + '_indices.bin'))
                row['candidate_vertex_bytes'] = len(first) * vertices.shape[1]
                assert np.array_equal(vertices[indices], vertices[stable_first][remap[indices]])
                row['expanded_vertex_channels_exact'] = True
            result['surfaces'].append(row)
    for mi, mat in enumerate(audit['materials']):
        for field, path in mat.get('paint', {}).items():
            if not field.endswith('_path') or not path:
                continue
            p = Path(path)
            with Image.open(p) as image:
                result['textures'].append({'material': mi, 'slot': field, 'path': path,
                    'bytes': p.stat().st_size, 'size': image.size, 'mode': image.mode})
    (ROOT / 'array_analysis.json').write_text(json.dumps(result, indent=2), encoding='utf8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
