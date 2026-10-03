"""Compare complete static glTF outputs, independently decoding binary accessors.

Usage: python tools/compare_gltf_geometry.py before.gltf after.gltf
Also verifies node metadata/transforms, PBR material JSON and exact image bytes.
"""
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import unquote
import numpy as np

COMPONENTS = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

class Gltf:
    def __init__(self, path):
        self.path = Path(path)
        self.data = json.loads(self.path.read_text(encoding='utf8'))
        self.buffers = [self.resource(x['uri']).read_bytes() for x in self.data.get('buffers', [])]

    def resource(self, uri):
        return self.path.parent / unquote(uri)

    def accessor(self, index):
        a = self.data['accessors'][int(index)]
        assert 'sparse' not in a
        v = self.data['bufferViews'][int(a['bufferView'])]
        dtype = np.dtype(COMPONENTS[a['componentType']])
        width = WIDTHS[a['type']]
        offset = int(v.get('byteOffset', 0) + a.get('byteOffset', 0))
        stride = int(v.get('byteStride', dtype.itemsize * width))
        count = int(a['count'])
        assert offset % dtype.itemsize == 0
        assert (count - 1) * stride + width * dtype.itemsize <= v['byteLength']
        result = np.ndarray((count, width), dtype=dtype, buffer=self.buffers[int(v['buffer'])], offset=offset, strides=(stride, dtype.itemsize))
        if a.get('normalized'):
            result = result.astype(np.float64) / np.iinfo(dtype).max
        assert np.isfinite(result).all()
        if 'min' in a: assert np.allclose(result.min(axis=0), a['min'], atol=1e-5)
        if 'max' in a: assert np.allclose(result.max(axis=0), a['max'], atol=1e-5)
        return result

def compare(before, after):
    a, b = Gltf(before), Gltf(after)
    for section in ['nodes', 'scenes', 'materials', 'textures', 'samplers', 'animations', 'skins', 'extensions', 'extensionsUsed', 'extensionsRequired']:
        assert a.data.get(section) == b.data.get(section), section
    assert len(a.data['images']) == len(b.data['images'])
    for left, right in zip(a.data['images'], b.data['images']):
        assert hashlib.sha256(a.resource(left['uri']).read_bytes()).digest() == hashlib.sha256(b.resource(right['uri']).read_bytes()).digest(), 'image changed'
    assert len(a.data['meshes']) == len(b.data['meshes'])
    surfaces = triangles = 0
    maximum_error = 0.0
    for mi, (left, right) in enumerate(zip(a.data['meshes'], b.data['meshes'])):
        assert {k:v for k,v in left.items() if k != 'primitives'} == {k:v for k,v in right.items() if k != 'primitives'}
        assert len(left['primitives']) == len(right['primitives'])
        for pi, (p, q) in enumerate(zip(left['primitives'], right['primitives'])):
            assert {k:v for k,v in p.items() if k not in ['indices','attributes']} == {k:v for k,v in q.items() if k not in ['indices','attributes']}
            assert p['attributes'].keys() == q['attributes'].keys(), (mi,pi,'attributes')
            ai, bi = a.accessor(p['indices']).reshape(-1), b.accessor(q['indices']).reshape(-1)
            assert len(ai) == len(bi) and len(ai) % 3 == 0
            # Cyclic triangle rotations preserve winding; reversed winding must fail.
            pa = a.accessor(p['attributes']['POSITION'])[ai].reshape(-1,3,3)
            pb = b.accessor(q['attributes']['POSITION'])[bi].reshape(-1,3,3)
            rotations = [np.all(np.isclose(pa, np.roll(pb,r,axis=1),rtol=0,atol=2e-5),axis=(1,2)) for r in range(3)]
            assert np.any(rotations,axis=0).all(), (mi,pi,'positions/winding')
            chosen = np.argmax(rotations,axis=0)
            for key in p['attributes']:
                va = a.accessor(p['attributes'][key])[ai].reshape(len(pa),3,-1)
                vb = b.accessor(q['attributes'][key])[bi].reshape(len(pb),3,-1)
                aligned = vb.copy()
                for r in range(3): aligned[chosen==r] = np.roll(vb[chosen==r],r,axis=1)
                error = float(np.max(np.abs(va-aligned)))
                maximum_error = max(maximum_error,error)
                assert np.allclose(va,aligned,rtol=0,atol=2e-5), (mi,pi,key,error)
            surfaces += 1
            triangles += len(ai)//3
    return {'ok': True, 'meshes': len(a.data['meshes']), 'surfaces': surfaces, 'triangles': triangles, 'max_attribute_error': maximum_error, 'images':len(a.data['images'])}

if __name__ == '__main__':
    print(json.dumps(compare(*sys.argv[1:3]),indent=2))
