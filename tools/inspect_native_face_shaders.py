"""Read-only native face shader evidence; run with the existing UnityPy Python env.

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
from UnityPy.export.ShaderConverter import ShaderProgram
from UnityPy.streams import EndianBinaryReader

source = Path('D:/Games/vamzhb/VaM_Data/StreamingAssets/z_sha')
output = Path('D:/code/rmmo_runtime/assets/characters/materials/face_native_01/shaders')
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
    name = str(obj.path_id)
    if obj.path_id not in (7358276954335225155, 2974384552914773945, 799377694740325251, 4747844213144197078):
        continue
    (output / f'{name}.shader.txt').write_text(shader.export(), encoding='utf-8')
    (output / f'{name}_parsed.json').write_text(json.dumps(obj.read_typetree()['m_ParsedForm']), encoding='utf-8')
    blob = bytes(shader.compressedBlob)
    offset, length = shader.offsets[0], shader.compressedLengths[0]
    raw = CompressionHelper.decompress_lz4(blob[offset:offset + length], shader.decompressedLengths[0])
    programs = ShaderProgram(EndianBinaryReader(raw, endian='<'), shader.object_reader.version)
    count = 0
    # Physical blob order is not pass order. Resolve the exact pass index.
    for pass_index, shader_pass in enumerate(shader.m_ParsedForm.m_SubShaders[0].m_Passes):
        variants = shader_pass.progFragment.m_SubPrograms
        if not variants:
            continue
        variant = variants[0]
        data = bytes(programs.m_SubPrograms[variant.m_BlobIndex].m_ProgramCode)
        position = data.find(b'DXBC')
        assert position >= 0
        size = struct.unpack_from('<I', data, position + 24)[0]
        assert size >= 32 and position + size <= len(data)
        code = data[position:position + size]
        pointer = ctypes.c_void_p()
        buffer = ctypes.create_string_buffer(code)
        assert disassemble(buffer, len(code), 0, None, ctypes.byref(pointer)) == 0
        table = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        try:
            address = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(table[3])(pointer)
            size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(table[4])(pointer)
            text = ctypes.string_at(address, size).decode('utf-8').rstrip('\0')
            assert 'ps_5_0' in text or 'ps_4_0' in text
            (output / f'{name}_pass{pass_index}.asm').write_text(text, encoding='utf-8')
        finally:
            ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(table[2])(pointer)
        count += 1
    assert count
    report['shaders'][name] = count
(output / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(report)
