"""Lossless dependency compaction of the fixed bridge pennant GLB.

No Blender roundtrip: referenced accessor bytes, encoded images, node names,
transforms, material parameters, sampler recipes and extras remain exact.
Reject unfamiliar extension/animation graphs rather than guess at references.
"""
import copy
import hashlib
import json
import mmap
import struct
from pathlib import Path

SOURCE=Path('D:/code/rmmo_runtime/cache/world3d/bridge_street_finish_20261006/assets/ca443721d86d712acc2627f25fd4cdc1755584d7057ae008b770627d4db969e1.glb')
OUT=Path('D:/code/rmmo_runtime/art_sources/bridge_long_pennant_optimization_20261009')
EXPECTED_SOURCE_SHA='ca443721d86d712acc2627f25fd4cdc1755584d7057ae008b770627d4db969e1'


def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


class Glb:
    def __init__(self,path):
        self.f=path.open('rb');self.raw=mmap.mmap(self.f.fileno(),0,access=mmap.ACCESS_READ)
        magic,version,size=struct.unpack_from('<III',self.raw)
        assert (magic,version,size)==(0x46546c67,2,len(self.raw))
        n,t=struct.unpack_from('<II',self.raw,12);assert t==0x4e4f534a
        self.j=json.loads(self.raw[20:20+n]);self.start=28+n
        length,t=struct.unpack_from('<II',self.raw,20+n)
        assert t==0x004e4942 and self.start+length==size
        assert len(self.j['buffers'])==1 and 'uri' not in self.j['buffers'][0]
    def blob(self,index):
        v=self.j['bufferViews'][index];assert v['buffer']==0
        start=self.start+v.get('byteOffset',0)
        return self.raw[start:start+v['byteLength']]
    def close(self):self.raw.close();self.f.close()


def texture_slots(item):
    if isinstance(item,dict):
        for k,v in item.items():
            if k.endswith('Texture') and isinstance(v,dict) and 'index' in v:yield v
            else:yield from texture_slots(v)
    elif isinstance(item,list):
        for v in item:yield from texture_slots(v)


def semantic(glb):
    """Canonical resolved rendering graph, independent of table numbering."""
    j=glb.j
    from functools import lru_cache
    @lru_cache(maxsize=None)
    def view(i):
        v=copy.deepcopy(j['bufferViews'][i]);v.pop('buffer');v.pop('byteOffset',None)
        return {'recipe':v,'bytes_sha256':hashlib.sha256(glb.blob(i)).hexdigest()}
    @lru_cache(maxsize=None)
    def accessor(i):
        a=copy.deepcopy(j['accessors'][i]);a['bufferView']=view(a['bufferView']);return a
    @lru_cache(maxsize=None)
    def image(i):
        a=copy.deepcopy(j['images'][i]);a.pop('name',None)
        a['bufferView']=view(a['bufferView']);return a
    @lru_cache(maxsize=None)
    def texture(i):
        t=copy.deepcopy(j['textures'][i]);t['source']=image(t['source'])
        if 'sampler' in t:t['sampler']=j['samplers'][t['sampler']]
        return t
    @lru_cache(maxsize=None)
    def material(i):
        m=copy.deepcopy(j['materials'][i])
        for slot in texture_slots(m):slot['index']=texture(slot['index'])
        return m
    meshes=copy.deepcopy(j['meshes'])
    for mesh in meshes:
        for p in mesh['primitives']:
            p['attributes']={k:accessor(i) for k,i in p['attributes'].items()}
            if 'indices' in p:p['indices']=accessor(p['indices'])
            if 'material' in p:p['material']=material(p['material'])
            for target in p.get('targets',[]):
                for k,i in target.items():target[k]=accessor(i)
    return {'asset':j['asset'],'nodes':j['nodes'],'scene':j.get('scene'),
            'scenes':j['scenes'],'meshes':meshes,'extras':j.get('extras')}


def run():
    OUT.mkdir(parents=True,exist_ok=True)
    sha=digest(SOURCE)
    assert sha==EXPECTED_SOURCE_SHA,'Fixed benchmark source changed; do not replace its candidate'
    src=Glb(SOURCE);j=src.j
    assert not j.get('extensionsUsed') and not j.get('extensionsRequired')
    def guard(x):
        if isinstance(x,dict):
            assert not x.get('extensions'), 'Unexpected extension reference graph'
            for v in x.values():guard(v)
        elif isinstance(x,list):
            for v in x:guard(v)
    guard(j)
    assert not j.get('animations') and not j.get('skins')
    used_m=set();used_a=set()
    for m in j['meshes']:
        for p in m['primitives']:
            used_a.update(p['attributes'].values())
            if 'indices' in p:used_a.add(p['indices'])
            if 'material' in p:used_m.add(p['material'])
            for t in p.get('targets',[]):used_a.update(t.values())
    used_t={slot['index'] for i in used_m for slot in texture_slots(j['materials'][i])}
    used_i={j['textures'][i]['source'] for i in used_t}
    used_s={j['textures'][i]['sampler'] for i in used_t if 'sampler' in j['textures'][i]}
    assert all('sparse' not in j['accessors'][i] for i in used_a)
    r=copy.deepcopy(j); maps={}
    for key,used in [('materials',used_m),('accessors',used_a),('samplers',used_s)]:
        maps[key]={old:new for new,old in enumerate(sorted(used))}
        r[key]=[copy.deepcopy(j[key][i]) for i in sorted(used)]
    maps['images']={};r['images']=[];seen={};image_aliases={}
    for i in sorted(used_i):
        im=copy.deepcopy(j['images'][i]);meta=copy.deepcopy(im);meta.pop('name',None);v=meta.pop('bufferView')
        raw=src.blob(v);key=(json.dumps(meta,sort_keys=True),hashlib.sha256(raw).hexdigest())
        if key not in seen:
            seen[key]=len(r['images']);r['images'].append(im)
        new=seen[key];maps['images'][i]=new;image_aliases.setdefault(str(new),[]).append({'old_index':i,'name':im.get('name')})
    maps['textures']={};r['textures']=[];seen={}
    for i in sorted(used_t):
        t=copy.deepcopy(j['textures'][i]);t['source']=maps['images'][t['source']]
        if 'sampler' in t:t['sampler']=maps['samplers'][t['sampler']]
        key=json.dumps(t,sort_keys=True)
        if key not in seen:seen[key]=len(r['textures']);r['textures'].append(t)
        maps['textures'][i]=seen[key]
    for m in r['meshes']:
        for p in m['primitives']:
            p['attributes']={k:maps['accessors'][i] for k,i in p['attributes'].items()}
            if 'indices' in p:p['indices']=maps['accessors'][p['indices']]
            if 'material' in p:p['material']=maps['materials'][p['material']]
            for t in p.get('targets',[]):
                for k,i in t.items():t[k]=maps['accessors'][i]
    for m in r['materials']:
        for slot in texture_slots(m):slot['index']=maps['textures'][slot['index']]
    # Repack only surviving image/accessor views; remove orphan history bytes.
    kept_v=sorted({a['bufferView'] for a in r['accessors']}|{im['bufferView'] for im in r['images']})
    r['bufferViews']=[];maps['bufferViews']={};binary=bytearray();seen={}
    for i in kept_v:
        v=copy.deepcopy(j['bufferViews'][i]);raw=src.blob(i)
        recipe=copy.deepcopy(v);recipe.pop('byteOffset',None)
        key=(json.dumps(recipe,sort_keys=True),hashlib.sha256(raw).hexdigest())
        if key not in seen:
            binary.extend(b'\x00'*((-len(binary))%4));v['byteOffset']=len(binary);binary.extend(raw)
            seen[key]=len(r['bufferViews']);r['bufferViews'].append(v)
        maps['bufferViews'][i]=seen[key]
    for a in r['accessors']:a['bufferView']=maps['bufferViews'][a['bufferView']]
    for im in r['images']:im['bufferView']=maps['bufferViews'][im['bufferView']]
    r['buffers']=[{'byteLength':len(binary)}]
    encoded=json.dumps(r,separators=(',',':'),ensure_ascii=False).encode('utf8');encoded+=b' '*((-len(encoded))%4)
    binary.extend(b'\x00'*((-len(binary))%4))
    output=OUT/'bridge_long_pennants_lossless.glb'
    assert output.resolve()!=SOURCE.resolve()
    with output.open('wb') as f:
        f.write(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary)))
        f.write(struct.pack('<II',len(encoded),0x4e4f534a));f.write(encoded)
        f.write(struct.pack('<II',len(binary),0x004e4942));f.write(binary)
    dest=Glb(output);before=semantic(src);after=semantic(dest)
    assert before==after,'Resolved render graph changed'
    assert digest(SOURCE)==sha,'Source mutated during operation'
    report={'source':str(SOURCE),'source_sha256':sha,'output':str(output),'output_sha256':digest(output),
        'source_bytes':SOURCE.stat().st_size,'output_bytes':output.stat().st_size,
        'saved_bytes':SOURCE.stat().st_size-output.stat().st_size,
        'source_tables':{k:len(j[k]) for k in maps},'output_tables':{k:len(r[k]) for k in maps},
        'exact_resolved_render_graph_equal':True,'all_referenced_accessor_and_image_bytes_equal':True,
        'nodes_transforms_wind_and_collision_extras_equal':j['nodes']==r['nodes'],
        'no_reencoding_no_resize_no_decimation':True,'source_unchanged':True,
        'image_aliases':image_aliases,'remap':maps,
        'published':False,'gpu_comparison':'pending; avoid overlapping production load benchmark'}
    (OUT/'lossless_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'source_master_reference.json').write_text(json.dumps({'path':str(SOURCE),'sha256':sha,'preserved_in_place':True},indent=2),encoding='utf8')
    (OUT/'resolved_render_graph_sha256.txt').write_text(hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest())
    src.close();dest.close()
    print(json.dumps({k:v for k,v in report.items() if k not in ['remap','image_aliases']},indent=2))


if __name__=='__main__':run()
