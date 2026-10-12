"""Conservative lossless compaction of two fixed town GLBs; no scene edits.

Uses the reference bridge-pennant parser/graph resolver. Only unreachable resource
tables and byte-identical image/view aliases are removed. Every node, mesh,
accessor byte, material recipe, extras field and extension declaration is checked.
"""
from pathlib import Path
from collections import Counter
import copy, hashlib, importlib.util, io, json, struct
from PIL import Image

ROOT=Path('D:/code/rmmo')
OUT=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/architecture')
spec=importlib.util.spec_from_file_location('pennant_lossless',ROOT/'tools/optimize_bridge_pennant_glb.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
TABLES={'materials','textures','images','samplers','accessors','bufferViews','buffers'}
RECOGNIZED_TOP={'asset','scene','scenes','nodes','meshes','animations','skins','cameras','extensionsUsed','extensionsRequired','extras'}|TABLES
def sha_json(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def guard_graph(j):
    assert not set(j)-RECOGNIZED_TOP,'Unknown top-level reference graph'
    assert not j.get('animations') and not j.get('skins'),'Animation/skin dependency graph not supported by this asset-specific tool'
    assert not j.get('extensionsRequired'),'Required extension rejected'
    assert set(j.get('extensionsUsed') or []) <= {'KHR_materials_specular'},'Unknown extension declaration'
    def walk(x):
        if isinstance(x,dict):
            assert not x.get('extensions'),'Active extension references are not supported'
            for k,v in x.items():
                if k!='extras':walk(v)
        elif isinstance(x,list):
            for v in x:walk(v)
    walk(j)
    assert all('uri' not in im and 'bufferView' in im for im in j.get('images',[]))
    assert all('sparse' not in a and 'bufferView' in a for a in j.get('accessors',[]))
def graph(glb):
    # Existing resolver checks every primitive/morph accessor, material/sampler,
    # exact referenced image/view bytes, nodes, scenes and root extras.
    resolved=ref.semantic(glb)
    untouched={k:v for k,v in glb.j.items() if k not in TABLES|{'meshes'}}
    return {'resolved':resolved,'untouched_top_fields':untouched}
def usage(j):
    mats=set();acc=set()
    for m in j['meshes']:
        for p in m['primitives']:
            assert p.get('mode',4)==4
            acc.update(p['attributes'].values())
            if 'indices' in p:acc.add(p['indices'])
            if 'material' in p:mats.add(p['material'])
            for target in p.get('targets',[]):acc.update(target.values())
    tex={s['index'] for i in mats for s in ref.texture_slots(j['materials'][i])}
    ims={j['textures'][i]['source'] for i in tex}
    sam={j['textures'][i]['sampler'] for i in tex if 'sampler' in j['textures'][i]}
    return {'materials':mats,'accessors':acc,'textures':tex,'images':ims,'samplers':sam}
def stats(glb):
    j=glb.j;use=usage(j);images=[]
    for i,im in enumerate(j.get('images',[])):
        raw=glb.blob(im['bufferView']);dim=Image.open(io.BytesIO(raw)).size
        images.append({'index':i,'name':im.get('name'),'referenced':i in use['images'],'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'dimensions':list(dim)})
    tris=[]
    for m in j['meshes']:
        tris.append(sum(j['accessors'][p['indices']]['count']//3 if 'indices' in p else j['accessors'][p['attributes']['POSITION']]['count']//3 for p in m['primitives']))
    geom={j['accessors'][i]['bufferView'] for i in use['accessors']}
    imageviews={j['images'][i]['bufferView'] for i in use['images']}
    all_live=geom|imageviews
    return {'tables':{k:len(j.get(k,[])) for k in ['nodes','meshes','materials','textures','images','samplers','accessors','bufferViews','animations','skins']},
            'used_tables':{k:len(v) for k,v in use.items()},'unique_mesh_triangles':sum(tris),
            'instance_triangles':sum(tris[n['mesh']] for n in j['nodes'] if 'mesh' in n),
            'mesh_surfaces':sum(len(m['primitives']) for m in j['meshes']),
            'all_image_bytes':sum(i['bytes'] for i in images),'referenced_image_bytes':sum(i['bytes'] for i in images if i['referenced']),
            'unreferenced_image_bytes':sum(i['bytes'] for i in images if not i['referenced']),
            'unreferenced_view_bytes':sum(v['byteLength'] for i,v in enumerate(j['bufferViews']) if i not in all_live),
            'live_geometry_view_bytes':sum(j['bufferViews'][i]['byteLength'] for i in geom),
            'node_extras_keys':dict(Counter(k for n in j['nodes'] for k in n.get('extras',{}))),
            'images':images}
def compact(row,label):
    source=Path(row['path']);source_sha=ref.digest(source);assert source_sha==row['source_sha256']
    src=ref.Glb(source);j=src.j;guard_graph(j);used=usage(j);r=copy.deepcopy(j);maps={}
    for key in ['materials','accessors','samplers']:
        maps[key]={old:new for new,old in enumerate(sorted(used[key]))};r[key]=[copy.deepcopy(j[key][i]) for i in sorted(used[key])]
    maps['images']={};r['images']=[];seen={};aliases={}
    for i in sorted(used['images']):
        im=copy.deepcopy(j['images'][i]);recipe=copy.deepcopy(im);recipe.pop('name',None);v=recipe.pop('bufferView');raw=src.blob(v)
        # Include buffer-view recipe as well as bytes to avoid changing importer hints.
        vr=copy.deepcopy(j['bufferViews'][v]);vr.pop('buffer');vr.pop('byteOffset',None)
        key=(sha_json(recipe),sha_json(vr),hashlib.sha256(raw).hexdigest())
        if key not in seen:seen[key]=len(r['images']);r['images'].append(im)
        maps['images'][i]=seen[key];aliases.setdefault(str(seen[key]),[]).append({'index':i,'name':im.get('name')})
    maps['textures']={};r['textures']=[];seen={}
    for i in sorted(used['textures']):
        t=copy.deepcopy(j['textures'][i]);t['source']=maps['images'][t['source']]
        if 'sampler' in t:t['sampler']=maps['samplers'][t['sampler']]
        key=sha_json(t)
        if key not in seen:seen[key]=len(r['textures']);r['textures'].append(t)
        maps['textures'][i]=seen[key]
    for m in r['meshes']:
        for p in m['primitives']:
            p['attributes']={k:maps['accessors'][v] for k,v in p['attributes'].items()}
            if 'indices' in p:p['indices']=maps['accessors'][p['indices']]
            if 'material' in p:p['material']=maps['materials'][p['material']]
            for target in p.get('targets',[]):
                for k,v in target.items():target[k]=maps['accessors'][v]
    for m in r['materials']:
        for slot in ref.texture_slots(m):slot['index']=maps['textures'][slot['index']]
    keep=sorted({a['bufferView'] for a in r['accessors']}|{i['bufferView'] for i in r['images']})
    maps['bufferViews']={};r['bufferViews']=[];data=bytearray();seen={}
    for i in keep:
        v=copy.deepcopy(j['bufferViews'][i]);raw=src.blob(i);recipe=copy.deepcopy(v);recipe.pop('byteOffset',None)
        key=(sha_json(recipe),hashlib.sha256(raw).hexdigest())
        if key not in seen:
            data.extend(b'\0'*((-len(data))%4));v['byteOffset']=len(data);data.extend(raw);seen[key]=len(r['bufferViews']);r['bufferViews'].append(v)
        maps['bufferViews'][i]=seen[key]
    for a in r['accessors']:a['bufferView']=maps['bufferViews'][a['bufferView']]
    for im in r['images']:im['bufferView']=maps['bufferViews'][im['bufferView']]
    r['buffers']=[{'byteLength':len(data)}]
    encoded=json.dumps(r,separators=(',',':'),ensure_ascii=False).encode();encoded+=b' '*((-len(encoded))%4);data+=b'\0'*((-len(data))%4)
    target=OUT/(label+'_lossless.glb');assert source.resolve()!=target.resolve()
    with target.open('wb') as f:
        f.write(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(data)));f.write(struct.pack('<II',len(encoded),0x4e4f534a));f.write(encoded);f.write(struct.pack('<II',len(data),0x004e4942));f.write(data)
    dst=ref.Glb(target);before=graph(src);after=graph(dst);assert before==after
    # Direct byte comparisons supplement hashes used by the canonical resolver.
    assert all(src.blob(old)==dst.blob(new) for old,new in maps['bufferViews'].items())
    assert all(src.blob(j['images'][old]['bufferView'])==dst.blob(r['images'][new]['bufferView']) for old,new in maps['images'].items())
    assert j['nodes']==r['nodes'] and j.get('animations')==r.get('animations') and j.get('skins')==r.get('skins')
    assert ref.digest(source)==source_sha
    report={'label':label,'source':str(source),'source_sha256':source_sha,'candidate':str(target),'candidate_sha256':ref.digest(target),
            'source_bytes':source.stat().st_size,'candidate_bytes':target.stat().st_size,'saved_bytes':source.stat().st_size-target.stat().st_size,
            'source_stats':stats(src),'candidate_stats':stats(dst),'nodes_transforms_extras_exact':True,'meshes_resolved_exact':True,
            'all_referenced_accessor_and_image_bytes_equal':True,'direct_view_byte_comparisons_passed':True,'source_unchanged':True,
            'animations_skins_exact':True,'extensions_declarations_exact':j.get('extensionsUsed')==r.get('extensionsUsed'),
            'active_extension_objects':0,'resolved_graph_sha256':sha_json(before),'remap':maps,'image_aliases':aliases,
            'method':'Unreferenced dependency removal and byte-identical image/texture/buffer-view aliases only; no geometry, material parameters, texture resolution or image encoding changes.',
            'gpu_validation':'pending parent-run sequential comparison','published':False,
            'scope_note':'9ba5457e is an oak asset despite Courtyard/Street group names; 42028074 is StreetSpire.'}
    (OUT/(label+'_audit.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    src.close();dst.close()
    summary={k:v for k,v in report.items() if k not in ['source_stats','candidate_stats','remap','image_aliases']}
    summary['source_tables']=report['source_stats']['tables'];summary['candidate_tables']=report['candidate_stats']['tables']
    print(json.dumps(summary,ensure_ascii=False,indent=2));return summary
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=json.loads((ROOT/'review_artifacts/town_large_asset_art_handoff_20261011.json').read_text(encoding='utf8'))['rows'];reports=[]
    for prefix,label in [('9ba5457e','oak_9ba5457e'),('42028074','street_spire_42028074')]:
        row=next(r for r in rows if Path(r['path']).name.startswith(prefix));reports.append(compact(row,label))
    (OUT/'architecture_lossless_summary.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf8')
if __name__=='__main__':main()
