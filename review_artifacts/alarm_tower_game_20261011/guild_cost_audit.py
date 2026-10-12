"""Read-only GLB payload audit; no runtime or GPU claims."""
from pathlib import Path
from collections import Counter, defaultdict
import hashlib, io, json, struct
from PIL import Image

ROOT = Path('D:/code/rmmo')
SOURCE = ROOT/'review_artifacts/axel_guild_materials_20261011/axel_guild_materials_v4.glb'
b = SOURCE.read_bytes()
size = struct.unpack_from('<I', b, 12)[0]
j = json.loads(b[20:20+size]); binary = b[28+size:]
nodes, meshes, access = j['nodes'], j['meshes'], j['accessors']
parents = {c: i for i,n in enumerate(nodes) for c in n.get('children', [])}
def ancestry(i):
    while True:
        yield i
        if i not in parents: break
        i = parents[i]
def triangles(m):
    return sum(access[p['indices']]['count']//3 if 'indices' in p else access[p['attributes']['POSITION']]['count']//3 for p in m['primitives'] if p.get('mode',4)==4)
mc = [triangles(m) for m in meshes]
def collect(indices):
    ids = [nodes[i]['mesh'] for i in indices if 'mesh' in nodes[i]]
    return dict(mesh_nodes=len(ids), unique_meshes=len(set(ids)), instanced_triangles=sum(mc[m] for m in ids), unique_mesh_triangles=sum(mc[m] for m in set(ids)), surfaces=sum(len(meshes[m]['primitives']) for m in ids))
groups=defaultdict(list);families=defaultdict(list);mat_tri=Counter();mat_surfaces=Counter()
for i,n in enumerate(nodes):
    if 'mesh' not in n: continue
    groups[n.get('extras',{}).get('semantic_group','missing')].append(i)
    family=next((nodes[p].get('extras',{}).get('asset_id') for p in ancestry(i) if nodes[p].get('extras',{}).get('asset_id')), 'architecture_or_ungrouped')
    families[family].append(i)
    for p in meshes[n['mesh']]['primitives']:
        mat=p.get('material',-1)
        mat_surfaces[mat]+=1
        mat_tri[mat]+=access[p['indices']]['count']//3 if 'indices' in p else access[p['attributes']['POSITION']]['count']//3
images=[]
for i,im in enumerate(j.get('images',[])):
    v=j['bufferViews'][im['bufferView']]; data=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
    p=Image.open(io.BytesIO(data));w,h=p.size
    images.append(dict(index=i,name=im.get('name'),width=w,height=h,mode=p.mode,encoded_bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),rgba8_mips_bytes=w*h*4*4/3))
unique_images={im['sha256']:im for im in images}
mat_signatures=defaultdict(list)
for i,m in enumerate(j['materials']):
    norm={k:v for k,v in m.items() if k not in ('name','extras')}
    mat_signatures[json.dumps(norm,sort_keys=True)].append(i)
lod_nodes=[i for i,n in enumerate(nodes) if any('lod' in k.lower() or 'visibility_range' in k for k in n.get('extras',{})) or 'MSFT_lod' in n.get('extensions',{})]
report=dict(source=str(SOURCE),scope='Source GLB static payload audit only; not measured runtime draw calls, FPS or VRAM.',source_sha256=hashlib.sha256(b).hexdigest(),file_bytes=len(b),total_nodes=len(nodes),totals=collect(range(len(nodes))),materials=len(j['materials']),material_structural_signatures=len(mat_signatures),image_records=len(images),unique_image_payloads=len(unique_images),image_encoded_bytes=sum(x['encoded_bytes'] for x in images),unique_image_encoded_bytes=sum(x['encoded_bytes'] for x in unique_images.values()),images_rgba8_mips_bytes_estimate=sum(x['rgba8_mips_bytes'] for x in images),unique_images_rgba8_mips_bytes_estimate=sum(x['rgba8_mips_bytes'] for x in unique_images.values()),images=images,groups={k:collect(v) for k,v in sorted(groups.items())},families={k:collect(v) for k,v in sorted(families.items(),key=lambda kv:-collect(kv[1])['instanced_triangles'])},top_mesh_nodes=sorted([dict(index=i,name=n.get('name'),triangles=mc[n['mesh']],mesh=n['mesh'],group=n.get('extras',{}).get('semantic_group')) for i,n in enumerate(nodes) if 'mesh' in n], key=lambda x:-x['triangles'])[:50],material_triangles=[dict(index=i,name=j['materials'][i].get('name'),triangles=count,surfaces=mat_surfaces[i]) for i,count in mat_tri.most_common()],duplicate_materials=[[j['materials'][i].get('name') for i in ids] for ids in mat_signatures.values() if len(ids)>1],lod_nodes=lod_nodes,animations=len(j.get('animations',[])),extensions_used=j.get('extensionsUsed',[]),extras_keys=dict(Counter(k for n in nodes for k in n.get('extras',{}))),rmmo_extra_nodes=sum(any(k.startswith('rmmo_') for k in n.get('extras',{})) for n in nodes),scale_figure_nodes=len(groups.get('60_Scale_Figures',[])))
out=Path(__file__).with_name('guild_cost_audit.json');out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k not in ('images','extras_keys','top_mesh_nodes','material_triangles','duplicate_materials')},ensure_ascii=False,indent=2))
print('top mesh nodes:',json.dumps(report['top_mesh_nodes'][:12],ensure_ascii=False))
print('duplicate materials:',json.dumps(report['duplicate_materials'],ensure_ascii=False))
