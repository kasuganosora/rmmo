import json,struct,hashlib
from pathlib import Path
base=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016')
def load(path):
    data=path.read_bytes();n,t=struct.unpack_from('<II',data,12);return json.loads(data[20:20+n]),data[28+n:]
def hashes(doc,bin):
    result=[]
    for image in doc['images']:
        v=doc['bufferViews'][image['bufferView']];data=bin[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        result.append(hashlib.sha256(data).hexdigest())
    return result
def material(doc,bin):
    node=next(n for n in doc['nodes'] if n.get('name')=='CanopyTrim');p=doc['meshes'][node['mesh']]['primitives'][0]
    m=doc['materials'][p['material']];hs=hashes(doc,bin)
    def clean(value):
        if isinstance(value,dict):
            if 'index' in value:
                tex=doc['textures'][value['index']]
                return {**{k:clean(v) for k,v in value.items() if k!='index'},'image_sha256':hs[tex['source']],'sampler':doc.get('samplers',[{}])[tex.get('sampler',0)]}
            return {k:clean(v) for k,v in value.items()}
        if isinstance(value,list):return [clean(x) for x in value]
        return value
    return node,p,clean(m)
reports=[]
for asset in ['pottery','scroll','potion','ore']:
    old,ob=load(base/'v3'/asset/'delta.glb');new,nb=load(base/'v4_canopy_trim'/asset/'delta.glb')
    on,op,om=material(old,ob);nn,np,nm=material(new,nb)
    checks={'one_mesh':len(new['meshes'])==1,'one_node':len(new['nodes'])==1,'one_CanopyTrim':nn['name']=='CanopyTrim',
            'all_material_factors_textures_samplers_identical':om==nm,'same_transform':all(on.get(k)==nn.get(k) for k in ['translation','rotation','scale','matrix']),
            'only_uv0':set(np['attributes'])=={'POSITION','NORMAL','TANGENT','TEXCOORD_0'},'same_index_count':old['accessors'][op['indices']]['count']==new['accessors'][np['indices']]['count']}
    row={'asset':asset,'checks':checks,'passed':all(checks.values()),'delta_sha256':hashlib.sha256((base/'v4_canopy_trim'/asset/'delta.glb').read_bytes()).hexdigest()}
    reports.append(row)
    if not row['passed']:print(json.dumps({'old':om,'new':nm},indent=2))
out={'passed':all(r['passed'] for r in reports),'reports':reports,'gpu_executed':False,'visual_accepted':False}
(base/'v4_canopy_trim/export_identity.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out,indent=2))
if not out['passed']:raise SystemExit(1)
