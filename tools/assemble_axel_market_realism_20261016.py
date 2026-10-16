"""Assemble revised PBR stall parts; prove the support triangle geometry retained."""
from pathlib import Path
import argparse, copy, hashlib, json, struct, itertools
import numpy as np
from optimize_bridge_pennant_glb import Glb, digest, texture_slots, semantic
from optimize_axel_market_payload_20261016 import geometry, image_stats, stats, array, node_matrix

ART=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016')
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_market_optimization_20261016/delivery.json')

def canonical(x):return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def write(path,x):path.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def support_triangles(g):
    node=next(n for n in g.j['nodes'] if n.get('name')=='Structure');matrix=node_matrix(node)
    result=[]
    for p in g.j['meshes'][node['mesh']]['primitives']:
        pos=array(g,p['attributes']['POSITION']);idx=array(g,p['indices']).ravel()
        world=pos@matrix[:3,:3].T+matrix[:3,3];result.append(world[idx].reshape(-1,3,3))
    return np.concatenate(result)

def support_check(src,dst):
    a,b=support_triangles(src),support_triangles(dst)
    assert a.shape==b.shape,('Support triangle count changed',a.shape,b.shape)
    buckets={};centres=b.mean(axis=1);used=set();errors=[]
    for i,key in enumerate(np.floor(centres/.0001).astype(int)):buckets.setdefault(tuple(key),[]).append(i)
    for tri in a:
        key=np.floor(tri.mean(axis=0)/.0001).astype(int);choices=[]
        for delta in itertools.product((-1,0,1),repeat=3):choices.extend(buckets.get(tuple(key+delta),[]))
        ranked=[]
        for i in choices:
            if i not in used:ranked.append((min(float(np.max(np.abs(tri-np.roll(b[i],shift,axis=0)))) for shift in range(3)),i))
        assert ranked,'Support triangle disappeared'
        error,index=min(ranked);assert error<.00001,('Support shape/winding changed',error)
        used.add(index);errors.append(error)
    return {'triangles':len(a),'max_world_triangle_corner_error_m':max(errors),'same_oriented_triangle_surfaces':True,'material_uv_intentionally_changed':True}

def assemble(row,out):
    source=Path(row['new_glb']);assert digest(source)==row['candidate_sha256']
    src=Glb(source);delta=Glb(out/row['asset']/'delta.glb')
    doc={'asset':{'version':'2.0','generator':'RMMO market near-material revision 20261016'},'scene':0,'scenes':[{'nodes':[]}],
         'nodes':[],'meshes':[],'materials':[],'textures':[],'images':[],'samplers':[],'accessors':[],'bufferViews':[]}
    binary=bytearray();seen={k:{} for k in ['bufferViews','images','textures','samplers']}
    revised_structure=any(n.get('name')=='Structure' for n in delta.j['nodes'])
    for g,selection in [(src,lambda n:n.get('name')=='Structure' and not revised_structure),(delta,lambda n:'mesh' in n)]:
        j=g.j;assert not j.get('skins') and not j.get('animations') and len(j['buffers'])==1
        maps={k:{} for k in ['bufferViews','images','textures','samplers','accessors','materials','meshes']}
        def take(key,idx):
            if idx in maps[key]:return maps[key][idx]
            item=copy.deepcopy(j[key][idx])
            if key=='bufferViews':
                assert item.get('buffer',0)==0
                raw=g.blob(idx);recipe=copy.deepcopy(item);recipe.pop('byteOffset',None)
                sig=(canonical(recipe),hashlib.sha256(raw).hexdigest())
                if sig in seen[key]:maps[key][idx]=seen[key][sig];return maps[key][idx]
                binary.extend(b'\0'*(-len(binary)%4));item['byteOffset']=len(binary);binary.extend(raw)
            elif key=='accessors':
                assert not item.get('sparse');item['bufferView']=take('bufferViews',item['bufferView'])
            elif key=='images':
                assert 'uri' not in item;item['bufferView']=take('bufferViews',item['bufferView'])
                sig=canonical(item)
            elif key=='samplers':sig=canonical(item)
            elif key=='textures':
                assert not item.get('extensions');item['source']=take('images',item['source'])
                if 'sampler' in item:item['sampler']=take('samplers',item['sampler'])
                sig=canonical(item)
            elif key=='materials':
                for slot in texture_slots(item):slot['index']=take('textures',slot['index'])
                # Current thin-glass optics is explicitly authored on nodes.
                # Blender transmission is not a portable fallback in this engine.
                ex=item.get('extensions',{})
                if 'KHR_materials_transmission' in ex:
                    ex.pop('KHR_materials_transmission');item['alphaMode']='BLEND'
                    item.setdefault('pbrMetallicRoughness',{}).setdefault('baseColorFactor',[1,1,1,1])[3]=.055
                if not ex:item.pop('extensions',None)
            elif key=='meshes':
                for prim in item['primitives']:
                    assert prim.get('mode',4)==4 and not prim.get('targets')
                    prim['attributes']={k:take('accessors',v) for k,v in prim['attributes'].items()}
                    if 'indices' in prim:prim['indices']=take('accessors',prim['indices'])
                    if 'material' in prim:prim['material']=take('materials',prim['material'])
            if key in seen and sig in seen[key]:maps[key][idx]=seen[key][sig];return maps[key][idx]
            result=len(doc[key]);doc[key].append(item);maps[key][idx]=result
            if key in seen:seen[key][sig]=result
            return result
        for old in j['nodes']:
            if not selection(old):continue
            assert not old.get('children'),'Delta must use evaluated flat mesh roots'
            node=copy.deepcopy(old);node['mesh']=take('meshes',node['mesh'])
            doc['scenes'][0]['nodes'].append(len(doc['nodes']));doc['nodes'].append(node)
    assert any(n.get('name')=='Structure' for n in doc['nodes'])
    for material in doc['materials']:
        assert all(slot.get('texCoord',0)==0 for slot in texture_slots(material)),('Only runtime UV0 atlases accepted',material['name'])
    for node in doc['nodes']:
        spec=node.get('extras',{}).get('rmmo_tinted_glass')
        if spec:
            names={doc['materials'][p['material']]['name'] for p in doc['meshes'][node['mesh']]['primitives']}
            assert names==set(spec['materials']),('Optical material identity changed',names,spec)
    extensions=set()
    def visit(x):
        if isinstance(x,dict):
            extensions.update(x.get('extensions',{}))
            for v in x.values():visit(v)
        elif isinstance(x,list):
            for v in x:visit(v)
    visit(doc)
    if extensions:doc['extensionsUsed']=sorted(extensions)
    doc['buffers']=[{'byteLength':len(binary)}]
    encoded=canonical(doc).encode('utf-8');encoded+=b' '*(-len(encoded)%4);binary+=b'\0'*(-len(binary)%4)
    target=out/(row['asset']+'.glb');assert not target.exists(),'Versioned candidates are immutable'
    target.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
    dst=Glb(target);a=geometry(src);b=geometry(dst)
    b['collision_evidence']='Support oriented triangles preserved within recorded tolerance; goods and cloth intentionally changed. Actual native collision/editor-semantic verification required.'
    support=support_check(src,dst)
    # Small float32 DCC export noise is recorded, never concealed in catalogue data.
    bounds_error=max(np.max(np.abs(np.array(a[k])-np.array(b[k]))) for k in ['bounds_min','bounds_max'])
    assert bounds_error<.001,('Authoring changed placement envelope',bounds_error)
    failures=[]
    for mesh in dst.j['meshes']:
        for prim in mesh['primitives']:
            pos=array(dst,prim['attributes']['POSITION']);ind=array(dst,prim['indices']).ravel()
            tri=pos[ind].reshape(-1,3,3);area=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)
            if int((area<1e-12).sum()):failures.append({'mesh':mesh['name'],'degenerate':int((area<1e-12).sum())})
    images=image_stats(dst)
    report={'asset':row['asset'],'source':str(source),'source_sha256':digest(source),'candidate':str(target),
      'candidate_sha256':digest(target),'structure':support,'bounds_error_m':float(bounds_error),
      'bounds_before':{'min':a['bounds_min'],'max':a['bounds_max']},'bounds_after':{'min':b['bounds_min'],'max':b['bounds_max']},
      'stats':stats(dst,images,b),'images':images,'geometry':b,'degenerate_findings':failures,
      'scope':'Intentional near-view realism revision; no unchanged-visual claim. Native/GPU/catalog validation required.'}
    write(out/(row['asset']+'_source_audit.json'),report)
    src.close();delta.close();dst.close()
    assert not failures,failures
    return {k:report[k] for k in ['asset','candidate','candidate_sha256','source','source_sha256']}

def main():
    p=argparse.ArgumentParser();p.add_argument('--version',default='v1');p.add_argument('--asset',action='append');args=p.parse_args()
    out=ART/args.version;assert out.resolve().is_relative_to(ART.resolve())
    rows=json.loads(BASE.read_text(encoding='utf-8'))['mapping'];result=[]
    for r in rows:
        if not args.asset or r['asset'] in args.asset:result.append(assemble(r,out))
    manifest=out/'candidates.json';old=json.loads(manifest.read_text(encoding='utf-8')) if manifest.exists() else {'version':1,'assets':[]}
    old['assets']=[r for r in old['assets'] if r['asset'] not in {r['asset'] for r in result}]+result
    write(manifest,old);print(json.dumps(result))
if __name__=='__main__':main()
