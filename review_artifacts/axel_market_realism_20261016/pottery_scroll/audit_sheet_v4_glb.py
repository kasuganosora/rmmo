import json,struct,hashlib
from pathlib import Path
base=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016')
def sha(b):return hashlib.sha256(b).hexdigest()
def load(path):
    data=path.read_bytes();jl,jt=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+jl]);bl,bt=struct.unpack_from('<II',data,20+jl)
    return doc,data[28+jl:28+jl+bl]
def accessor(doc,data,idx):
    a=doc['accessors'][idx];v=doc['bufferViews'][a['bufferView']];sz={5121:1,5123:2,5125:4,5126:4}[a['componentType']]*{'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',sz)
    return b''.join(data[off+i*stride:off+i*stride+sz] for i in range(a['count']))
def paper(doc):
    node=next(n for n in doc['nodes'] if n.get('name')=='PaperSheet')
    return node,doc['meshes'][node['mesh']]['primitives'][0]
paths=[base/'v3/scroll/delta.glb',base/'v4_scroll_sheet/delta.glb']
old,ob=load(paths[0]);new,nb=load(paths[1]);on,op=paper(old);nn,np=paper(new)
checks=[]
def check(label,ok):checks.append({'label':label,'passed':ok})
check('only one PaperSheet mesh exported',len(new['meshes'])==1 and len(new['nodes'])==1)
for name in ['POSITION','NORMAL','TANGENT','TEXCOORD_0']:
    check(name+' accessor exactly unchanged',accessor(old,ob,op['attributes'][name])==accessor(new,nb,np['attributes'][name]))
check('index data exactly unchanged',accessor(old,ob,op['indices'])==accessor(new,nb,np['indices']))
check('node transform unchanged',all(on.get(k)==nn.get(k) for k in ['matrix','translation','rotation','scale']))
check('only UV0 exported',set(np['attributes'])=={'POSITION','NORMAL','TANGENT','TEXCOORD_0'})
mat=new['materials'][np['material']];oldmat=old['materials'][op['material']]
for label,tex in [('base',mat['pbrMetallicRoughness']['baseColorTexture']),('orm',mat['pbrMetallicRoughness']['metallicRoughnessTexture']),('normal',mat['normalTexture'])]:
    check(label+' uses UV0',tex.get('texCoord',0)==0)
    image=new['images'][new['textures'][tex['index']]['source']];view=new['bufferViews'][image['bufferView']];data=nb[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
    png=base/'v4_scroll_sheet'/('PaperSheet_'+{'base':'DIFFUSE','orm':'ORM','normal':'NORMAL'}[label]+'.png')
    check(label+' embedded pixels file identity',data==png.read_bytes())
for name in ['PaperSheet_NORMAL.png','PaperSheet_ORM.png','PaperSheet_ROUGHNESS.png','PaperSheet_METALLIC.png']:
    check(name+' source file unchanged',(base/'v3/scroll'/name).read_bytes()==(base/'v4_scroll_sheet'/name).read_bytes())
check('source metallic remains nonmetal',mat.get('pbrMetallicRoughness',{}).get('metallicFactor',1)==oldmat.get('pbrMetallicRoughness',{}).get('metallicFactor',1))
report={'version':1,'source_sha256':sha(paths[0].read_bytes()),'delta_sha256':sha(paths[1].read_bytes()),'checks':checks,'passed':all(x['passed'] for x in checks),'visual_accepted':False,'gpu_executed':False}
(base/'v4_scroll_sheet/geometry_and_texture_identity.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
if not report['passed']:raise SystemExit(1)
