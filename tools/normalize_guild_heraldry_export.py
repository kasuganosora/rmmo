"""Normalize the standalone assembly without changing the building instance."""
import json, struct, hashlib
from pathlib import Path

OUT = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2')
def normalize(path):
    data = path.read_bytes()
    size, kind = struct.unpack_from('<II', data, 12)
    gltf = json.loads(data[20:20+size])
    if gltf.get('extras', {}).get('standalone_mount_origin_v2'):
        return
    # Wall mounting origin: horizontal centre, bottom of cloth, wall plane.
    # This source assembly was authored in the building's world coordinates.
    roots = gltf['scenes'][gltf.get('scene', 0)]['nodes']
    index = len(gltf['nodes'])
    gltf['nodes'].append({'name':'HeraldryMountOrigin', 'children':roots,
                          'translation':[-16.0, -4.75, 0.0]})
    gltf['scenes'][gltf.get('scene', 0)]['nodes'] = [index]
    gltf.setdefault('extras', {})['standalone_mount_origin_v2'] = True
    encoded = json.dumps(gltf,ensure_ascii=False,separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    tail = data[20+size:]
    path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(encoded)+len(tail),len(encoded),kind)+encoded+tail)

if __name__ == '__main__':
    manifest = json.loads((OUT/'repair_manifest.json').read_text(encoding='utf8'))
    for row in manifest['library']:
        if row['asset_id'] != 'guild_facade_heraldry': continue
        normalize(Path(row['path']))
        row['sha256'] = hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()
        row['mount_origin'] = 'wall plane, cloth bottom, horizontal centre'
    (OUT/'repair_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
