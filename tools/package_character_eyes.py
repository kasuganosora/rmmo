"""Package a local eye atlas without repainting or changing its UV layout."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from art_paths import art_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    member = 'Custom/Atom/Person/Textures/AWWalker/AWWEyes/shawni2023.1005-brown.jpg'
    with zipfile.ZipFile(args.package) as archive:
        metadata = json.loads(archive.read('meta.json'))
        if metadata.get('licenseType') != 'CC BY':
            raise ValueError('Source metadata changed; review the source before packaging')
        pixels = archive.read(member)
    target = art_path('characters/materials/eyes_brown_01')
    target.mkdir(parents=True, exist_ok=True)
    (target / 'albedo.jpg').write_bytes(pixels)
    manifest = dict(id='eyes_brown_01', author='AWWalker', license='CC BY',
                    source_package=args.package.name, source_member=member,
                    uv_layout='Genesis 2 Base Female eye atlas',
                    materials=['Irises', 'Pupils', 'Sclera'],
                    sha256=hashlib.sha256(pixels).hexdigest(),
                    changes='Renamed only; original image bytes retained. Runtime material separate from skin.')
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(target)


if __name__ == '__main__':
    main()
