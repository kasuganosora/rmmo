"""Read-only source shader evidence; run with the existing UnityPy Python env.

Uses Windows' D3DDisassemble for the original DXBC, not a shader reimplementation.
Exported assembly is inspection data, never loaded by the runtime.
"""
import ctypes
import hashlib
import json
import struct
from pathlib import Path

import UnityPy
from UnityPy.helpers import CompressionHelper

source = Path('D:/Games/Koikatu/abdata/chara/bo_hair_b_00.unity3d')
output = Path('D:/code/rmmo_runtime/assets/characters/source_hair/koikatu/shaders')
output.mkdir(parents=True, exist_ok=True)
dll = ctypes.WinDLL('d3dcompiler_47.dll')
disassemble = dll.D3DDisassemble
disassemble.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint,
                       ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
disassemble.restype = ctypes.c_long
report = {'source': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'shaders': {}}
for obj in UnityPy.load(str(source)).objects:
    if obj.type.name != 'Shader':
        continue
    shader = obj.read()
    name = shader.m_ParsedForm.m_Name.split('/')[-1]
    if name not in ('main_hair', 'main_item'):
        continue
    (output / f'{name}.shader.txt').write_text(shader.export(), encoding='utf-8')
    (output / f'{name}_parsed.json').write_text(json.dumps(obj.read_typetree()['m_ParsedForm']), encoding='utf-8')
    blob = bytes(shader.compressedBlob)
    offset, length = shader.offsets[0], shader.compressedLengths[0]
    raw = CompressionHelper.decompress_lz4(blob[offset:offset + length], shader.decompressedLengths[0])
    position = count = 0
    while True:
        position = raw.find(b'DXBC', position)
        if position < 0:
            break
        size = struct.unpack_from('<I', raw, position + 24)[0]
        assert size >= 32 and position + size <= len(raw)
        code = raw[position:position + size]
        position += size
        pointer = ctypes.c_void_p()
        buffer = ctypes.create_string_buffer(code)
        assert disassemble(buffer, len(code), 0, None, ctypes.byref(pointer)) == 0
        table = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        try:
            address = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(table[3])(pointer)
            size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(table[4])(pointer)
            text = ctypes.string_at(address, size).decode('utf-8').rstrip('\0')
            (output / f'{name}_{count:02}.asm').write_text(text, encoding='utf-8')
        finally:
            ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(table[2])(pointer)
        count += 1
    assert count
    report['shaders'][name] = count
(output / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(report)
