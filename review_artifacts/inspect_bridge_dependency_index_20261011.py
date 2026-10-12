"""Read-only bounded diagnostic for scalar Godot Variant directory metadata.
Not a runtime proof reader: no source import, asset hash or GPU operations.
"""
import json
import struct
import subprocess
from pathlib import Path

INDEX = Path('D:/code/rmmo_runtime/cache/world3d/dependency_indexes/dbc679c896283f779b107da911bbca7e68fa01f0c1cef4c36823e29a65f2dc12.bin')
REPORT = Path('D:/code/rmmo_runtime/review_artifacts/loading_collision_none_warm_20261011.json')
NODE = 'C:/Users/luna/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'

class Reader:
    def __init__(self, data): self.data, self.pos = data, 0
    def unpack(self, fmt):
        size = struct.calcsize(fmt)
        value = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return value[0] if len(value) == 1 else list(value)
    def u32(self): return self.unpack('<I')
    def text(self):
        n = self.u32()
        assert n <= len(self.data)-self.pos
        value = self.data[self.pos:self.pos+n].decode('utf8')
        self.pos += (n+3) & ~3
        return value
    def value(self, depth=0):
        assert depth < 30
        header = self.u32(); kind = header & 0xffff
        if kind == 0: return None
        if kind == 1: return bool(self.u32())
        if kind == 2: return self.unpack('<q' if header & 0x10000 else '<i')
        if kind == 3: return self.unpack('<d' if header & 0x10000 else '<f')
        if kind in (4, 21): return self.text()
        if kind in (5, 9, 16):
            return self.unpack('<'+str({5:2, 9:3, 16:6}[kind])+('d' if header & 0x10000 else 'f'))
        if kind in (6, 10): return self.unpack('<'+str({6:2, 10:3}[kind])+'i')
        if kind == 27:
            assert header == 27
            n = self.u32() & 0x7fffffff
            return {self.value(depth+1): self.value(depth+1) for _ in range(n)}
        if kind == 28:
            assert header == 28
            return [self.value(depth+1) for _ in range(self.u32() & 0x7fffffff)]
        raise ValueError((kind, header, self.pos))

def overlaps(box, clip):
    return all(box[i] <= clip[i]+clip[i+3] and box[i]+box[i+3] >= clip[i] for i in (0,2))

def main():
    assert INDEX.stat().st_size < 16*1024*1024
    raw = INDEX.read_bytes()
    assert raw[:9] == b'RMMODEPS1' and struct.unpack_from('<Q', raw, 9)[0] == len(raw)-49
    reader = Reader(raw[49:]); index = reader.value()
    assert reader.pos == len(raw)-49
    report = json.loads(REPORT.read_text(encoding='utf-8-sig'))
    assert index['source_sha256'] == report['map_sha']
    core = [320, -100000, 160, 32, 200000, 32]
    safety = [307.2, -100000, 146.3, 44.8, 200000, 45.7]
    groups = {k for k,g in index['groups'].items() if not g['bounds_known'] or overlaps(g['bounds'],core)}
    deferred_ids = set(report['map_profile']['collision_first_core_deferred_ids'])
    selected = []
    for row in index['rows']:
        grouped = bool(row['group_id'])
        wanted = row['group_id'] in groups if grouped else row['classification'] == 'global'
        if not wanted and not grouped:
            halo = max(8, row['terrain_halo']) if row['terrain_halo'] > 0 else 0
            clip = [core[i]-halo for i in range(3)]+[core[i+3]+2*halo for i in range(3)]
            wanted = overlaps(row['bounds'],clip)
        if wanted and row['uuid'] not in deferred_ids: selected.append(row)
    assert len(selected) == report['map_profile']['reference_selected_count'], (len(selected), report['map_profile']['reference_selected_count'])
    selected_ids = {r['uuid'] for r in selected}
    bridge = next(r for r in index['rows'] if r['uuid']=='stone_e_0be972769041dbc9')
    users = {}
    for row in index['rows']:
        for key in row['prefab_textures']:
            if any(name in key for name in ('stone_tiles_facade', 'castle_rubble', 'outdoor_flagstone')):
                users.setdefault(key, []).append({'uuid':row['uuid'], 'selected':row['uuid'] in selected_ids, 'reason':row['reason'], 'group':row['group_id']})
    # Inspect at most four tiny author road definitions, not any prefab payload,
    # GLB or texture. Node's bundled Zstd reads only a <=128 KiB scalar record.
    road_sources = []
    for row in [r for r in selected if r['reason']=='native_road'][:4]:
        ref = row['reference']; path = Path(report['map']).parent / ref['uri']
        if path.stat().st_size > 128*1024: continue
        envelope = path.read_bytes()
        assert envelope[:8] == b'RMMORES1'
        length = struct.unpack_from('<Q',envelope,8)[0]
        if length > 128*1024: continue
        code = 'const f=require("node:fs"),z=require("node:zlib");const b=f.readFileSync(process.argv[1]);process.stdout.write(z.zstdDecompressSync(b.subarray(16),{maxOutputLength:131072}));'
        decoded = subprocess.run([NODE,'-e',code,str(path)],check=True,capture_output=True).stdout
        assert len(decoded) == length
        rr = Reader(decoded); definition = rr.value(); assert rr.pos == len(decoded)
        matches=[]
        def visit(value, fields):
            if isinstance(value,dict):
                for key, child in value.items(): visit(child, fields+[key])
            elif isinstance(value,list):
                for i, child in enumerate(value): visit(child, fields+[i])
            elif isinstance(value,str) and 'outdoor_flagstone/' in value:
                matches.append({'fields':fields,'path':value})
        visit(definition,[])
        if matches:
            road_sources.append({'uuid':row['uuid'],'reason':row['reason'],'reference':ref,'file_bytes':len(envelope),'raw_bytes':length,'matches':matches})
            break
    result = {'index_file':str(INDEX), 'index_bytes':len(raw), 'diagnostic_only':'Metadata decoder cross-checked count/source identity/full buffer consumption. Does not reissue a production ownership proof or hash large asset sources.', 'map_sha': index['source_sha256'], 'rows':len(index['rows']), 'selected_count':len(selected), 'bridge':{'uuid':bridge['uuid'], 'bounds':bridge['bounds'], 'group':bridge['group_id'], 'reason':bridge['reason'], 'core_intersects':overlaps(bridge['bounds'],core), 'safety_intersects':overlaps(bridge['bounds'],safety), 'selected':bridge['uuid'] in selected_ids, 'prefab_texture_count':len(bridge['prefab_textures'])}, 'prefab_texture_users':{k:{'total':len(v),'selected_count':sum(r['selected'] for r in v),'selected_examples':[r for r in v if r['selected']][:12]} for k,v in users.items()}, 'selected_road_definitions':road_sources}
    output = Path('D:/code/rmmo/review_artifacts/bridge_texture_directory_evidence_20261011.json')
    output.write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf8')
    print(json.dumps({'rows':result['rows'],'selected':result['selected_count'],'bridge':result['bridge'],'selected_road_definitions':road_sources},indent=2,ensure_ascii=False))

if __name__=='__main__': main()
