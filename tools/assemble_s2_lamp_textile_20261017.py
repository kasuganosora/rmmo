"""Lossless reuse of the existing lamp meshes, replacing only its cloth slot."""
from pathlib import Path
import argparse,copy,hashlib,json,struct
P=argparse.ArgumentParser();P.add_argument('--version',default='v2');A=P.parse_args()
OUT=Path('D:/code/rmmo_runtime/art_sources/s2_hanging_textiles_20261017')/A.version
LAMP=Path('D:/code/rmmo_runtime/packs/default/assets/f308819058f9a51e8fecb41b24ac839073153f48481979af18c73c273199a2c9.glb')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):
    b=Path(p).read_bytes();n=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+n]),b[28+n:]
def write(p,d,b):
    j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4);b+=b'\0'*((-len(b))%4)
    p.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(b))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(b),b'BIN\0')+b)
base,bb=read(LAMP);cloth,cb=read(OUT/'s2_ochre_long_banner.glb')
assert not base.get('skins') and not base.get('animations') and len(base['nodes'])==4
old_slot=[i for i,n in enumerate(base['nodes']) if n.get('extras',{}).get('rmmo_banner_slot')];assert old_slot==[1]
d=copy.deepcopy(base);del d['nodes'][1];del d['meshes'][1]
for n in d['nodes']:
    if n['mesh']>1:n['mesh']-=1
off={k:len(d.get(k,[])) for k in ['nodes','meshes','materials','accessors','bufferViews','textures','images','samplers']}
bb+=b'\0'*((-len(bb))%4);binary_offset=len(bb)
for v in cloth.get('bufferViews',[]):
    v=copy.deepcopy(v);v['byteOffset']=v.get('byteOffset',0)+binary_offset;d.setdefault('bufferViews',[]).append(v)
for v in cloth.get('accessors',[]):
    v=copy.deepcopy(v);v['bufferView']+=off['bufferViews'];assert 'sparse' not in v;d.setdefault('accessors',[]).append(v)
for k in ['samplers','images','textures','materials','meshes','nodes']:
    for item in cloth.get(k,[]):
        x=copy.deepcopy(item)
        if k=='images':x['bufferView']+=off['bufferViews']
        if k=='textures':
            x['source']+=off['images']
            if 'sampler' in x:x['sampler']+=off['samplers']
        if k=='materials':
            def remap(o):
                if isinstance(o,dict):
                    for key,value in o.items():
                        if key.endswith('Texture') and isinstance(value,dict) and 'index' in value:value['index']+=off['textures']
                        else:remap(value)
            remap(x)
        if k=='meshes':
            for p in x['primitives']:
                p['indices']+=off['accessors'];p['material']+=off['materials'];p['attributes']={a:b+off['accessors'] for a,b in p['attributes'].items()}
        if k=='nodes':
            if 'mesh' in x:x['mesh']+=off['meshes']
            if 'children' in x:x['children']=[n+off['nodes'] for n in x['children']]
            if x.get('extras',{}).get('rmmo_wind'):x['extras']['rmmo_banner_slot']=True
        d.setdefault(k,[]).append(x)
for n in cloth['scenes'][cloth.get('scene',0)]['nodes']:d['nodes'][n+off['nodes']]['translation']=[-.61,2.835,.038]
roots=[0,1,2]+[i+off['nodes'] for i in cloth['scenes'][cloth.get('scene',0)]['nodes']]
name='s2_bronze_lamp_long_ochre_banner'
d['scenes']=[{'name':name,'nodes':roots}];d['scene']=0;d['buffers']=[{'byteLength':len(bb)+len(cb)}]
for k in ['extensionsUsed','extensionsRequired']:
    if base.get(k) or cloth.get(k):d[k]=sorted(set(base.get(k,[])+cloth.get(k,[])))
d['asset']['generator']='S2 cloth-only composition; original lamp accessors and binary bytes retained'
target=OUT/(name+'.glb');assert not target.exists();write(target,d,bb+cb)
# All untouched primitive and material descriptors remain byte-for-byte semantic
# copies, and their original bufferViews still address the identical bytes.
proof={'source':LAMP.as_posix(),'source_sha256':sha(LAMP),'retained_meshes':[],'removed_mesh':'BannerCloth','unchanged_original_binary_prefix':target.read_bytes().endswith((bb+cb)+b'\0'*((-len(bb+cb))%4))}
for i,oi in enumerate([0,2,3]):
    assert d['meshes'][i]==base['meshes'][oi]
    proof['retained_meshes'].append(base['meshes'][oi].get('name',str(oi)))
assert d['materials'][:off['materials']]==base['materials']
author=json.loads((OUT/'s2_ochre_long_banner_authoring.json').read_text(encoding='utf-8'))
author.update({'id':name,'path':target.as_posix(),'sha256':sha(target),'bytes':target.stat().st_size,'master':(OUT/(name+'_master.blend')).as_posix(),'master_sha256':None,'anchors':{'ground_origin':[0,0,0],'front_axis':'+Z','banner_mount':[-.61,2.835,.038],'cloth_lowest_about_y':.78,'note':'Use this lamp style instead of the original red-flag lamp; do not overlay two lamps.'},'notes':'Original bronze structure, lantern glass and crystal geometry/material channels reused unchanged. Only textile slot and textile suspension replaced. Inherited lighting behavior is unchanged; this is not a new lamp reconstruction.','lamp_reuse':proof})
(OUT/(name+'_authoring.json')).write_text(json.dumps(author,ensure_ascii=False,indent=2),encoding='utf-8')
print(target,sha(target))
