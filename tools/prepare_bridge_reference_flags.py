"""Recompose existing verified flag meshes into one suspended span.

Keep original UVs, PBR images, top-pinned wind metadata and golden post ribbons.
Only derived copies are written; shared immutable assets are not edited.
"""
import copy,io,json,struct
from pathlib import Path
from PIL import Image
BASE=Path('D:/code/rmmo_runtime');OUT=BASE/'art_sources/bridge_reference_scene_20261006';OUT.mkdir(parents=True,exist_ok=True)
items=json.loads((BASE/'review_artifacts/town_props_20261006/published.json').read_text(encoding='utf8'))['items']
def read(key):
    e=next(x['entry'] for x in items if x['id']==key);p=Path(e['prefab_path'])
    r=json.loads(p.read_text(encoding='utf8'))['records'][0];raw=(p.parent.parent/r['asset_path']).read_bytes()
    size=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+size]),bytearray(raw[28+size:])
def save(doc,binary,name):
    doc['buffers'][0]['byteLength']=len(binary);binary.extend(b'\0'*(-len(binary)%4))
    text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*(-len(text)%4)
    (OUT/name).write_bytes(struct.pack('<III',0x46546c67,2,28+len(text)+len(binary))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(binary),0x004e4942)+binary)
d,b=read('town_festival_posts_bunting')
flags=[n for n in d['nodes'] if n.get('name','').startswith('Hanging')]
cord=copy.deepcopy(next(n for n in d['nodes'] if n.get('name')=='Structure'))
cord['scale']=[11.30/2.88841366767883,1.45,1]
cord['translation'][1]=2.35-2.890155553817749*1.45
cord['extras']={'rmmo_collision':'none'}
nodes=[cord]
for i in range(9):
    n=copy.deepcopy(flags[i%len(flags)]);n['name']='Bridge_Long_Pennant_%02d'%i
    a=d['accessors'][d['meshes'][n['mesh']]['primitives'][0]['attributes']['POSITION']]
    x=(i-4)*1.18;y=2.33-.25*(1-(x/5.65)**2)
    n['scale']=[1.55,1.60,1.60];n['translation']=[x,y-a['max'][1]*1.60,-.00427365]
    nodes.append(n)
d['nodes']=nodes;d['scenes']=[{'nodes':list(range(len(nodes)))}];d['scene']=0
save(d,b,'bridge_single_span_nine_flags.glb')
for name,tone in [('green',(0.12,.66,.18)),('rose',(.72,.20,.48))]:
    d,b=read('town_festival_posts_POST_natural')
    node=next(n for n in d['nodes'] if n['name']=='PostBody')
    materials={p['material'] for p in d['meshes'][node['mesh']]['primitives']}
    for mi in materials:
        mat=d['materials'][mi];p=mat['pbrMetallicRoughness'];old=d['textures'][p['baseColorTexture']['index']];im=d['images'][old['source']];v=d['bufferViews'][im['bufferView']]
        image=Image.open(io.BytesIO(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])).convert('RGB')
        # Technical albedo recoloring: preserve per-pixel wood variation, no light baked in.
        import numpy as np
        a=np.asarray(image,dtype=np.float32)/255;lum=a@np.array([.2126,.7152,.0722]);mean=max(.03,float(lum.mean()))
        a=np.clip((lum/mean)[...,None]*np.array(tone),0,1);imout=Image.fromarray((a*255).astype('uint8'),'RGB');buf=io.BytesIO();imout.save(buf,format='PNG');blob=buf.getvalue()
        b.extend(b'\0'*(-len(b)%4));offset=len(b);b.extend(blob);vi=len(d['bufferViews']);d['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(blob)})
        ii=len(d['images']);d['images'].append({'bufferView':vi,'mimeType':'image/png','name':'Tinted_wood_'+name});ti=len(d['textures']);texture=copy.deepcopy(old);texture['source']=ii;d['textures'].append(texture);p['baseColorTexture']['index']=ti
        p['baseColorFactor']=[1,1,1,1];mat['name']='Painted '+name+' timber; original wood normal and roughness'
    save(d,b,'festival_post_'+name+'.glb')
print('REFERENCE_FLAGS_PREPARED',OUT)
