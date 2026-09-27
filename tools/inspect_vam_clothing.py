"""Decode a VAB's mesh and persistent surface binding for offline inspection.

Only schema 1.0 is supported. Simulation/material sections remain untouched.
"""
import argparse
import io
import json
import math
import struct
import zipfile
from pathlib import Path


class Reader:
    def __init__(self, data): self.stream = io.BytesIO(data)
    def unpack(self, fmt):
        fmt = '<' + fmt
        return struct.unpack(fmt, self.stream.read(struct.calcsize(fmt)))
    def count(self):
        value, = self.unpack('i')
        if not 0 <= value <= 2_000_000: raise ValueError('Invalid array count')
        return value
    def string(self):
        size = 0
        for shift in range(0, 35, 7):
            byte, = self.unpack('B');size |= (byte & 127) << shift
            if byte < 128:
                raw = self.stream.read(size)
                if len(raw) != size: raise ValueError('Truncated string')
                return raw.decode('utf-8')
        raise ValueError('Invalid string length')
    def section(self, name):
        actual, version = self.string(), self.string()
        if (actual, version) != (name, '1.0'):
            raise ValueError(f'Unsupported {actual} {version}; expected {name} 1.0')


def decode(data):
    r = Reader(data);r.section('DynamicStore');r.section('DAZMesh')
    ids = [r.string() for _ in range(4)]
    vertices = [r.unpack('fff') for _ in range(r.count())]
    materials = [r.string() for _ in range(r.count())]
    count = r.count()
    def polygons():
        result = []
        for _ in range(count):
            material = r.count();size = r.count()
            if not 3 <= size <= 4: raise ValueError('Unsupported polygon')
            result.append({'material': material, 'vertices': r.unpack('i' * size)})
        return result
    faces, uv_faces = polygons(), polygons()
    uv = [r.unpack('ff') for _ in range(r.count())]
    seams = [r.unpack('iii') for _ in range(r.count())]
    r.section('DAZSkinWrap');wrap_name = r.string();r.section('DAZSkinWrapStore')
    bindings = [r.unpack('iiiiffffff') for _ in range(r.count())]
    assert len(bindings) == len(uv)
    for p, up in zip(faces, uv_faces):
        assert p['material'] < len(materials) and len(p['vertices']) == len(up['vertices'])
        assert all(0 <= v < len(vertices) for v in p['vertices'])
        assert all(0 <= v < len(uv) for v in up['vertices'])
    assert all(math.isfinite(x) for row in vertices + uv for x in row)
    assert all(min(row[:4]) >= 0 and all(math.isfinite(x) for x in row[4:]) for row in bindings)
    return {'ids': ids, 'vertices': vertices, 'faces': faces, 'uv_faces': uv_faces,
            'uv': uv, 'seams': seams, 'materials': materials, 'wrap_name': wrap_name,
            'binding_fields': ['triangle', 'v1', 'v2', 'v3', 'normal_offset', 'tangent1_offset',
                               'tangent2_offset', 'normal_dot', 'tangent1_dot', 'tangent2_dot'],
            'bindings': bindings, 'unparsed_tail_bytes': len(data) - r.stream.tell()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--entry', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args();args.output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.package) as z:
        result = decode(z.read(args.entry))
        result['package'] = str(args.package);result['entry'] = args.entry
        for suffix in ['.vaj', '.vam']:
            entry = str(Path(args.entry).with_suffix(suffix)).replace('\\', '/')
            (args.output / ('source' + suffix)).write_bytes(z.read(entry))
        meta = json.loads(z.read('meta.json'))
        result['package_license'] = meta.get('licenseType')
    (args.output / 'clothing_data.json').write_text(json.dumps(result), encoding='utf-8')
    with (args.output / 'garment_original.obj').open('w', encoding='utf-8') as f:
        for p in result['vertices']: f.write('v %g %g %g\n' % p)
        for p in result['uv']: f.write('vt %g %g\n' % p)
        for p, uvp in zip(result['faces'], result['uv_faces']):
            f.write('g ' + result['materials'][p['material']] + '\n')
            f.write('f ' + ' '.join(f'{v+1}/{u+1}' for v,u in zip(p['vertices'],uvp['vertices'])) + '\n')
    print('PASS mesh and wrap:',len(result['vertices']), 'vertices,',len(result['bindings']), 'UV bindings;',
          'body vertex max',max(max(b[1:4]) for b in result['bindings']),
          '; unparsed tail', result['unparsed_tail_bytes'])
