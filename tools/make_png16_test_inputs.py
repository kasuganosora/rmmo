"""Independent PNG filter fixtures using Python's struct/zlib, never production decoder."""
import argparse
import json
import struct
import zlib
from pathlib import Path


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def png(size=17, filter_mode=0, **options):
    values = [min(65535, (x + z) * (256 if size == 129 else 1999) + x % 2)
              for z in range(size) for x in range(size)]
    if size == 17:
        values[:6] = [0, 1, 255, 256, 65534, 65535]
    raw = bytearray()
    previous = bytes(size * 2)
    for z in range(size):
        row = struct.pack('>' + 'H' * size, *values[z * size:(z + 1) * size])
        mode = z % 5 if filter_mode == 5 else filter_mode
        raw.append(mode)
        for x, v in enumerate(row):
            a, b, c = row[x - 2] if x >= 2 else 0, previous[x], previous[x - 2] if x >= 2 else 0
            p = a + b - c
            distances = [abs(p - a), abs(p - b), abs(p - c)]
            paeth = [a, b, c][distances.index(min(distances))]
            predictor = [0, a, b, (a + b) // 2, paeth][mode]
            raw.append((v - predictor) % 256)
        previous = row
    header = struct.pack('>IIBBBBB', size, size, options.get('bits', 16), options.get('color', 0), 0, 0, options.get('interlace', 0))
    payload = zlib.compress(raw + (b'\0' if options.get('excess') else b''))
    split = len(payload) // 2
    body = chunk(b'IHDR', header) + chunk(b'gAMA', struct.pack('>I', 45455))
    if options.get('transparent'):
        body += chunk(b'tRNS', b'\0\0')
    body += chunk(b'IDAT', payload[:split]) + chunk(b'IDAT', payload[split:]) + chunk(b'IEND', b'')
    return b'\x89PNG\r\n\x1a\n' + body, values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = []
    for mode in range(6):
        blob, values = png(filter_mode=mode)
        name = f'filter_{mode}.png'
        (args.output / name).write_bytes(blob)
        cases.append(dict(path=name, ok=True, values=values))
    for name, options in [('interlace', {'interlace': 1}), ('rgb', {'color': 2}), ('eight', {'bits': 8}),
                          ('transparent', {'transparent': True}), ('excess', {'excess': True})]:
        blob, _ = png(**options)
        (args.output / (name + '.png')).write_bytes(blob)
        cases.append(dict(path=name + '.png', ok=False))
    blob, _ = png()
    corrupt = bytearray(blob)
    corrupt[-5] ^= 1
    for name, data in [('crc', corrupt), ('truncated', blob[:-5]), ('tail', blob + b'x')]:
        (args.output / (name + '.png')).write_bytes(data)
        cases.append(dict(path=name + '.png', ok=False))
    blob, _ = png(size=129, filter_mode=5)
    (args.output / 'terrain129.png').write_bytes(blob)
    (args.output / 'cases.json').write_text(json.dumps(cases), encoding='utf-8')


if __name__ == '__main__':
    main()
