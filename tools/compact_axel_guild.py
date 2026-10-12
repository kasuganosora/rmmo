"""Conservative guild cleanup: remove scale figures and exact resource aliases.

The supported graph is explicit; unfamiliar index-bearing extensions are rejected.
All retained accessor/image bytes, hierarchy and resolved materials are checked.
Mother files are immutable. No source texture resizing or geometry decimation.
"""
import argparse, copy, hashlib, importlib.util, json, struct
from pathlib import Path
import optimize_bridge_pennant_glb as ref

EXT={'KHR_materials_clearcoat','KHR_materials_transmission','KHR_materials_emissive_strength','KHR_materials_specular','KHR_materials_ior'}

def write(path,j,data):
    j['buffers']=[{'byteLength':len(data)}]
    a=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();a+=b' '*(-len(a)%4)
    data+=b'\0'*(-len(data)%4)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(struct.pack('<IIIII',0x46546c67,2,28+len(a)+len(data),len(a),0x4e4f534a)+a+struct.pack('<II',len(data),0x004e4942)+data)

def compact(source,target,remove_figures=True):
    source,target=Path(source).resolve(),Path(target).resolve()
    assert source!=target
    original_sha=ref.digest(source)
    src=ref.Glb(source);j=src.j;r=copy.deepcopy(j)
    assert not j.get('animations') and not j.get('skins'),'Use animation-aware tooling for animated resources'
    assert set(j.get('extensionsUsed',[]))<=EXT and not j.get('extensionsRequired')
    assert not j.get('extensions')
    for table in ['nodes','meshes','accessors','bufferViews','images','textures','samplers','scenes']:
        for v in j.get(table,[]):assert not v.get('extensions'),(table,'unsupported reference extension')
    for m in j['meshes']:
        for p in m['primitives']:assert not p.get('extensions') and not p.get('targets')
    for m in j['materials']:assert set(m.get('extensions',{}))<=EXT
    assert all('sparse' not in a and 'bufferView' in a for a in j['accessors'])
    assert all('uri' not in i and 'bufferView' in i for i in j['images'])
    removed={i for i,n in enumerate(j['nodes']) if remove_figures and n.get('extras',{}).get('semantic_group','').startswith('60_')}
    assert all(all(c in removed for c in j['nodes'][i].get('children',[])) for i in removed),'Mixed-purpose figure parent'
    nmap={old:new for new,old in enumerate(i for i in range(len(j['nodes'])) if i not in removed)}
    r['nodes']=[copy.deepcopy(j['nodes'][i]) for i in nmap]
    for n in r['nodes']:
        if 'children' in n:n['children']=[nmap[i] for i in n['children'] if i in nmap]
    for s in r['scenes']:s['nodes']=[nmap[i] for i in s['nodes'] if i in nmap]
    live_mesh=sorted({n['mesh'] for n in r['nodes'] if 'mesh' in n})
    mmap={old:new for new,old in enumerate(live_mesh)}
    r['meshes']=[copy.deepcopy(j['meshes'][i]) for i in live_mesh]
    for n in r['nodes']:
        if 'mesh' in n:n['mesh']=mmap[n['mesh']]
    # Compact image bytes while keeping image, texture and material table indices.
    # This preserves names, all KHR material recipes, samplers and index-like extras.
    # Importers can deduplicate image payloads independently; no shader name changes.
    live_views={a['bufferView'] for a in j['accessors']}|{i['bufferView'] for i in j['images']}
    data=bytearray();views=[];vmap={};seen={}
    for i in sorted(live_views):
        v=copy.deepcopy(j['bufferViews'][i]);raw=src.blob(i)
        recipe={k:v for k,v in v.items() if k not in ('byteOffset','name')}
        key=(json.dumps(recipe,sort_keys=True),hashlib.sha256(raw).hexdigest())
        if key not in seen:
            data+=b'\0'*(-len(data)%4);v['byteOffset']=len(data);data+=raw
            seen[key]=len(views);views.append(v)
        vmap[i]=seen[key]
    for a in r['accessors']:a['bufferView']=vmap[a['bufferView']]
    for i in r['images']:i['bufferView']=vmap[i['bufferView']]
    r['bufferViews']=views
    # Alias only identical images with identical metadata (except display name).
    images=[];imap={};seen={}
    for i,im in enumerate(r['images']):
        key=json.dumps({k:v for k,v in im.items() if k!='name'},sort_keys=True)
        if key not in seen:seen[key]=len(images);images.append(im)
        imap[i]=seen[key]
    r['images']=images
    for t in r['textures']:t['source']=imap[t['source']]
    write(target,r,data)
    dst=ref.Glb(target)
    before=ref.semantic(src);after=ref.semantic(dst)
    assert [before['meshes'][i] for i in live_mesh]==after['meshes'],'Resolved mesh/material/image/accessor mismatch'
    assert dst.j['nodes']==r['nodes'] and dst.j['scenes']==r['scenes']
    assert all(src.blob(i)==dst.blob(vmap[i]) for i in live_views)
    assert original_sha==ref.digest(source)
    report=dict(source=str(source),source_sha256=original_sha,candidate=str(target),candidate_sha256=ref.digest(target),
        source_bytes=source.stat().st_size,candidate_bytes=target.stat().st_size,
        removed_nodes=[j['nodes'][i].get('name') for i in sorted(removed)],
        removed_mesh_nodes=sum('mesh' in j['nodes'][i] for i in removed),
        source_images=len(j['images']),candidate_images=len(r['images']),
        retained_geometry_materials_and_image_bytes_exact=True,retained_hierarchy_exact_after_index_remap=True,
        intentionally_preserved_material_names=True,source_unchanged=True,
        status={'resource':'passed','visual':'pending','pipeline':'pending','integration':'pending'})
    src.close();dst.close()
    target.with_suffix('.audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('target');p.add_argument('--keep-figures',action='store_true')
    a=p.parse_args();compact(a.source,a.target,not a.keep_figures)
