"""Expose existing Fab 2K height maps for terrain blending, without synthesizing them."""
import hashlib
import io
import json
from pathlib import Path
from zipfile import ZipFile
from PIL import Image
from import_fab_materials import write_json

PACK = Path('D:/code/rmmo_runtime/packs/default')
SOURCES = {'mossy_grass': 'Bump', 'bright_desert_sand': 'Displacement',
           'icelandic_jagged_slate': 'Displacement'}

def main():
    catalog_path = PACK / 'sources/fab/catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    manifest_path = Path(__file__).with_name('fab_coastal_terrain_materials.json')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    for slug, suffix in SOURCES.items():
        folder = PACK / 'assets/materials/terrain' / slug
        descriptor = folder / 'material.json'
        value = json.loads(descriptor.read_text(encoding='utf-8'))
        archive = PACK / value['source']['archive']
        if not archive.resolve().is_relative_to((PACK / 'sources/fab').resolve()):
            raise ValueError('Archive outside source root')
        with ZipFile(archive) as z:
            members = [n for n in z.namelist() if n.endswith('_2K_' + suffix + '.jpg')]
            if len(members) != 1:
                raise ValueError('Expected one original 2K height map')
            member = members[0]
            if z.getinfo(member).file_size > 16 * 1024 * 1024:
                raise ValueError('Oversized source height map')
            data = z.read(member)
        with Image.open(io.BytesIO(data)) as image:
            if image.size != (2048, 2048):
                raise ValueError('Height map is not 2K')
        destination = folder / 'height.jpg'
        temporary = destination.with_suffix('.jpg.tmp')
        temporary.write_bytes(data)
        temporary.replace(destination)
        value['material']['height_path'] = destination.name
        value['source']['maps']['height_path'] = {
            'member': member, 'channel': 0, 'size': [2048, 2048],
            'runtime_sha256': hashlib.sha256(data).hexdigest(),
            'use': 'Material blend mask only; not geometric displacement'}
        write_json(descriptor, value)
        write_json(archive.parent / 'source.json', value['source'])
        for row in catalog['materials']:
            if row['material_id'] == 'pack:default:terrain/' + slug + '/material':
                row['source'] = value['source']
        for row in manifest['materials']:
            if row['slug'] == slug:
                row['maps']['height_path'] = member
        print(slug, member, '2048 x 2048, source bytes preserved')
    write_json(catalog_path, catalog)
    write_json(manifest_path, manifest)

if __name__ == '__main__':
    main()
