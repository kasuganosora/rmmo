"""Replace explicitly named flat GLB parts, proving every other rendering input exact."""
from pathlib import Path
import argparse, copy, hashlib, json, struct
import numpy as np
from optimize_bridge_pennant_glb import Glb, digest, texture_slots, semantic
from optimize_axel_market_payload_20261016 import geometry, image_stats, stats, array
from assemble_axel_market_realism_20261016 import ART, BASE, canonical, write, support_check


def resolved_nodes(g):
    graph = semantic(g)
    result = {}
    for original in graph['nodes']:
        node = copy.deepcopy(original)
        assert 'mesh' in node and not node.get('children')
        node['mesh'] = graph['meshes'][node['mesh']]
        assert node['name'] not in result
        result[node['name']] = node
    return result


def merge(previous, delta, target, names):
    assert not target.exists(), 'Versioned artifacts are immutable'
    before, replacement = Glb(previous), Glb(delta)
    old_nodes, new_nodes = resolved_nodes(before), resolved_nodes(replacement)
    assert names <= old_nodes.keys() and names == new_nodes.keys()
    doc = {'asset': copy.deepcopy(before.j['asset']), 'scene': 0, 'scenes': [{'nodes': []}]}
    for key in ('nodes', 'meshes', 'materials', 'textures', 'images', 'samplers', 'accessors', 'bufferViews'):
        doc[key] = []
    binary = bytearray()
    for source, keep in ((before, lambda n: n['name'] not in names), (replacement, lambda n: n['name'] in names)):
        j = source.j
        assert not j.get('skins') and not j.get('animations')
        maps = {key: {} for key in doc if isinstance(doc[key], list)}

        def take(key, index):
            if index in maps[key]:
                return maps[key][index]
            item = copy.deepcopy(j[key][index])
            if key == 'bufferViews':
                assert item.get('buffer', 0) == 0
                binary.extend(b'\0' * (-len(binary) % 4))
                item['byteOffset'] = len(binary)
                binary.extend(source.blob(index))
            elif key == 'accessors':
                assert not item.get('sparse')
                item['bufferView'] = take('bufferViews', item['bufferView'])
            elif key == 'images':
                assert 'uri' not in item
                item['bufferView'] = take('bufferViews', item['bufferView'])
            elif key == 'textures':
                assert not item.get('extensions')
                item['source'] = take('images', item['source'])
                if 'sampler' in item:
                    item['sampler'] = take('samplers', item['sampler'])
            elif key == 'materials':
                for slot in texture_slots(item):
                    assert slot.get('texCoord', 0) == 0
                    slot['index'] = take('textures', slot['index'])
            elif key == 'meshes':
                for prim in item['primitives']:
                    assert prim.get('mode', 4) == 4 and not prim.get('targets')
                    prim['attributes'] = {k: take('accessors', v) for k, v in prim['attributes'].items()}
                    for field, table in (('indices', 'accessors'), ('material', 'materials')):
                        if field in prim:
                            prim[field] = take(table, prim[field])
            result = len(doc[key])
            doc[key].append(item)
            maps[key][index] = result
            return result

        for old in j['nodes']:
            if keep(old):
                node = copy.deepcopy(old)
                node['mesh'] = take('meshes', node['mesh'])
                doc['scenes'][0]['nodes'].append(len(doc['nodes']))
                doc['nodes'].append(node)
    extensions = set(before.j.get('extensionsUsed', [])) | set(replacement.j.get('extensionsUsed', []))
    if extensions:
        doc['extensionsUsed'] = sorted(extensions)
    doc['buffers'] = [{'byteLength': len(binary)}]
    encoded = canonical(doc).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(binary)) +
                      struct.pack('<II', len(encoded), 0x4e4f534a) + encoded +
                      struct.pack('<II', len(binary), 0x004e4942) + binary)
    after = Glb(target)
    merged = resolved_nodes(after)
    assert old_nodes.keys() == merged.keys()
    for name in old_nodes:
        assert merged[name] == (new_nodes[name] if name in names else old_nodes[name]), name
    identity = {'previous': str(previous), 'previous_sha256': digest(previous),
                'delta': str(delta), 'delta_sha256': digest(delta),
                'candidate': str(target), 'candidate_sha256': digest(target),
                'replaced_nodes': sorted(names), 'unchanged_nodes': sorted(old_nodes.keys() - names),
                'all_unreplaced_resolved_nodes_byte_exact': True,
                'replacement_resolved_nodes_byte_exact': True}
    before.close(); replacement.close(); after.close()
    return identity


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--previous', type=Path, required=True)
    parser.add_argument('--delta', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--asset', required=True)
    parser.add_argument('--node', action='append', required=True)
    args = parser.parse_args()
    out = ART / args.version
    assert out.resolve().is_relative_to(ART.resolve())
    target = out / (args.asset + '.glb')
    identity = merge(args.previous, args.delta, target, set(args.node))
    row = next(r for r in json.loads(BASE.read_text(encoding='utf-8'))['mapping'] if r['asset'] == args.asset)
    source = Path(row['new_glb'])
    assert digest(source) == row['candidate_sha256']
    src, dst = Glb(source), Glb(target)
    a, b = geometry(src), geometry(dst)
    b['collision_evidence'] = ('Support oriented triangles match the original within the recorded tolerance. '
                               'Goods, cloth and binding geometry intentionally changed; unchanged-component '
                               'render identity is proved separately. Actual native collision verification required.')
    support = support_check(src, dst)
    bounds_error = max(np.max(np.abs(np.array(a[k]) - np.array(b[k]))) for k in ('bounds_min', 'bounds_max'))
    assert bounds_error < .001
    for mesh in dst.j['meshes']:
        for prim in mesh['primitives']:
            pos = array(dst, prim['attributes']['POSITION'])
            tri = pos[array(dst, prim['indices']).ravel()].reshape(-1, 3, 3)
            assert not (np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) < 1e-12).any()
    images = image_stats(dst)
    report = {'asset': args.asset, 'source': str(source), 'source_sha256': digest(source),
              'candidate': str(target), 'candidate_sha256': digest(target), 'structure': support,
              'bounds_error_m': float(bounds_error), 'bounds_before': {'min': a['bounds_min'], 'max': a['bounds_max']},
              'bounds_after': {'min': b['bounds_min'], 'max': b['bounds_max']},
              'stats': stats(dst, images, b), 'images': images, 'geometry': b,
              'degenerate_findings': [], 'incremental_identity': identity,
              'scope': 'Intentional near-view material repair; native/GPU/catalog validation required.'}
    write(out / (args.asset + '_source_audit.json'), report)
    write(out / (args.asset + '_incremental_identity.json'), identity)
    manifest = out / 'candidates.json'
    data = json.loads(manifest.read_text(encoding='utf-8')) if manifest.exists() else {'version': 1, 'assets': []}
    data['assets'] = [r for r in data['assets'] if r['asset'] != args.asset] + [
        {k: report[k] for k in ('asset', 'candidate', 'candidate_sha256', 'source', 'source_sha256')}]
    write(manifest, data)
    src.close(); dst.close()
    print(json.dumps(identity, ensure_ascii=False))


if __name__ == '__main__':
    main()
