"""Deterministic texture-budget candidates. No mesh or node edits.

Near-identical ORM maps are explicitly a bounded, non-lossless change. Every
input remains intact; image resizing is a quality candidate awaiting GPU review.
"""
import copy
import hashlib
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path('D:/code/rmmo')
sys.path.insert(0, str(ROOT / 'tools'))
from optimize_bridge_pennant_glb import Glb, digest

SOURCE = Path('D:/code/rmmo_runtime/art_sources/bridge_long_pennant_optimization_20261009/bridge_long_pennants_lossless.glb')
OUT = Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/pennants')
OUT.mkdir(parents=True, exist_ok=True)
EXPECTED = 'c88390233a731974ef2d020be023d47365c46104a4dc9a22d85d2f2fc4e5a64d'

def png(image):
    stream = io.BytesIO()
    image.save(stream, format='PNG', compress_level=9)
    return stream.getvalue()

def run(label, diffuse_size, normal_size, rough_size):
    assert digest(SOURCE) == EXPECTED
    src = Glb(SOURCE)
    j = copy.deepcopy(src.j)
    pixels = [Image.open(io.BytesIO(src.blob(x['bufferView']))).copy() for x in j['images']]
    original_nodes = copy.deepcopy(j['nodes'])
    original_meshes = copy.deepcopy(j['meshes'])
    original_materials = copy.deepcopy(j['materials'])
    updates = {}
    differences = []
    for other in [10, 12, 14, 16]:
        delta = np.abs(np.asarray(pixels[other]).astype('int16') - np.asarray(pixels[8]).astype('int16'))
        assert delta.max() == 1 and np.count_nonzero(delta) <= 11
        differences.append({'image': other, 'maximum_channel_difference_8bit': int(delta.max()),
                            'changed_channel_values': int(np.count_nonzero(delta))})
        for texture in j['textures']:
            if texture['source'] == other:
                texture['source'] = 8
    assert pixels[7].getextrema() == ((128, 128), (128, 128), (254, 254), (255, 255))
    updates[7] = Image.new('RGBA', (1, 1), (128, 128, 254, 255))
    for index in range(1, 6):
        if diffuse_size < 2048:
            updates[index] = pixels[index].resize((diffuse_size, diffuse_size), Image.Resampling.BOX)
    for index in [9, 11, 13, 15, 17]:
        if normal_size < 2048:
            # Keep the same averaged normal channels as a box-filter mip.
            # No renormalization/recolour, no normal direction convention change.
            updates[index] = pixels[index].resize((normal_size, normal_size), Image.Resampling.BOX)
    if rough_size < 2048:
        updates[8] = pixels[8].resize((rough_size, rough_size), Image.Resampling.BOX)
    used_images = sorted({t['source'] for t in j['textures']})
    new_images = []
    payloads = {}
    image_remap = {}
    image_changes = []
    for old in used_images:
        image_remap[old] = len(new_images)
        entry = copy.deepcopy(j['images'][old])
        payloads[entry['bufferView']] = png(updates[old]) if old in updates else src.blob(entry['bufferView'])
        im = updates.get(old, pixels[old])
        image_changes.append({'source_image': old, 'name': entry.get('name'), 'source_size': pixels[old].size,
                              'output_size': im.size, 'mode': im.mode, 'reencoded': old in updates,
                              'encoded_bytes': len(payloads[entry['bufferView']])})
        new_images.append(entry)
    j['images'] = new_images
    for texture in j['textures']:
        texture['source'] = image_remap[texture['source']]
    kept_views = sorted({a['bufferView'] for a in j['accessors']} | {im['bufferView'] for im in j['images']})
    binary = bytearray()
    remap = {}
    views = []
    for old in kept_views:
        remap[old] = len(views)
        view = copy.deepcopy(src.j['bufferViews'][old])
        data = payloads.get(old, src.blob(old))
        binary.extend(b'\0' * (-len(binary) % 4))
        view['byteOffset'] = len(binary)
        view['byteLength'] = len(data)
        binary.extend(data)
        views.append(view)
    for item in [*j['accessors'], *j['images']]:
        item['bufferView'] = remap[item['bufferView']]
    j['bufferViews'] = views
    j['buffers'] = [{'byteLength': len(binary)}]
    encoded = json.dumps(j, ensure_ascii=False, separators=(',', ':')).encode('utf8')
    encoded += b' ' * (-len(encoded) % 4)
    binary.extend(b'\0' * (-len(binary) % 4))
    output = OUT / ('bridge_long_pennants_' + label + '.glb')
    with output.open('wb') as f:
        f.write(struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(binary)))
        f.write(struct.pack('<II', len(encoded), 0x4e4f534a)); f.write(encoded)
        f.write(struct.pack('<II', len(binary), 0x004e4942)); f.write(binary)
    dest = Glb(output)
    assert j['nodes'] == original_nodes and j['meshes'] == original_meshes and j['materials'] == original_materials
    for old, after in zip(src.j['accessors'], dest.j['accessors']):
        assert src.blob(old['bufferView']) == dest.blob(after['bufferView'])
        a = dict(old); b = dict(after); a.pop('bufferView'); b.pop('bufferView'); assert a == b
    assert digest(SOURCE) == EXPECTED
    report = {'label': label, 'source': str(SOURCE), 'source_sha256': EXPECTED,
              'candidate': str(output), 'candidate_sha256': digest(output), 'source_bytes': SOURCE.stat().st_size,
              'candidate_bytes': output.stat().st_size, 'nodes_meshes_material_parameters_unchanged': True,
              'accessor_bytes_unchanged': True, 'source_unchanged': True, 'images': image_changes,
              'roughness_near_aliases': differences, 'constant_normal_exact': True,
              'lossless': False, 'gpu_review': 'pending', 'published': False}
    (OUT / (label + '_build.json')).write_text(json.dumps(report, indent=2), encoding='utf8')
    src.close(); dest.close()
    return {k: v for k, v in report.items() if k not in ['images', 'roughness_near_aliases']}

if __name__ == '__main__':
    results = [run('shared', 2048, 2048, 2048), run('balanced', 1024, 1024, 512), run('detail', 2048, 1024, 512)]
    (OUT / 'candidates.json').write_text(json.dumps(results, indent=2), encoding='utf8')
    print(json.dumps(results, indent=2))
