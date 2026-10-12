"""Read-only audit of current-town authored dependencies; outputs stay alongside this script."""
import collections, hashlib, io, json, math, statistics, struct
from pathlib import Path
from PIL import Image

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
inventory=json.loads((OUT/'inventory_map_definitions.json').read_text(encoding='utf-8'))
handoff=json.loads((ROOT/'review_artifacts/town_large_asset_art_handoff_20261011.json').read_text(encoding='utf-8'))
critical=json.loads((ROOT/'review_artifacts/editor_residency_critical_20261011.json').read_text(encoding='utf-8'))
records=inventory['records']
norm=lambda p:p.replace('\\','/').lower()
refs=collections.defaultdict(list)
for r in records:
    for p in {x['path'] for x in r['paths']}: refs[norm(p)].append(r['uuid'])
images_global=collections.defaultdict(list)

def glb_audit(path):
    p=Path(path);data=p.read_bytes();n=struct.unpack_from('<I',data,12)[0]
    j=json.loads(data[20:20+n]);bin_offset=n+28;views=j.get('bufferViews',[])
    nodes=j.get('nodes',[]);scenes=j.get('scenes',[]);seen=set()
    def visit(i):
        if i in seen:return
        seen.add(i)
        for c in nodes[i].get('children',[]):visit(c)
    if scenes:
        for i in scenes[j.get('scene',0)].get('nodes',[]):visit(i)
    else: seen.update(range(len(nodes)))
    active_meshes={nodes[i]['mesh'] for i in seen if 'mesh' in nodes[i]}
    active_materials={q['material'] for mi in active_meshes for q in j['meshes'][mi]['primitives'] if 'material' in q}
    texture_ids=set()
    def find_tex(o):
        if isinstance(o,dict):
            for k,v in o.items():
                if k.endswith('Texture') and isinstance(v,dict) and 'index' in v:texture_ids.add(v['index'])
                find_tex(v)
        elif isinstance(o,list):
            for v in o:find_tex(v)
    for mi in active_materials:find_tex(j['materials'][mi])
    used_images=set()
    for ti in texture_ids:
        t=j['textures'][ti]
        if 'source' in t:used_images.add(t['source'])
        for v in t.get('extensions',{}).values():
            if 'source' in v:used_images.add(v['source'])
    imgs=[];groups=collections.defaultdict(list)
    for i,img in enumerate(j.get('images',[])):
        row={'index':i,'name':img.get('name',''),'used_by_default_scene_material':i in used_images}
        if 'bufferView' in img:
            v=views[img['bufferView']];b=data[bin_offset+v.get('byteOffset',0):bin_offset+v.get('byteOffset',0)+v['byteLength']]
            row.update(bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
            try:
                im=Image.open(io.BytesIO(b));row.update(width=im.width,height=im.height,mode=im.mode,format=im.format)
            except Exception as ex: row['image_header_error']=str(ex)
            groups[row['sha256']].append(i)
            images_global[row['sha256']].append({'path':str(p).replace('\\','/'),'image':i,'bytes':len(b),'used':i in used_images})
        else:row['uri']=img.get('uri')
        imgs.append(row)
    unused=sum(x.get('bytes',0) for x in imgs if not x['used_by_default_scene_material'])
    dupe=sum(sum(imgs[i].get('bytes',0) for i in indices[1:]) for indices in groups.values())
    # Non-overlapping savings: discard unused images, then dedup remaining referenced payloads.
    used_groups=collections.defaultdict(list)
    for x in imgs:
        if x['used_by_default_scene_material'] and 'sha256' in x:used_groups[x['sha256']].append(x['index'])
    used_dupe=sum(sum(imgs[i]['bytes'] for i in indices[1:]) for indices in used_groups.values())
    return {'current_sha256':hashlib.sha256(data).hexdigest(),'current_file_bytes':len(data),'images':imgs,'images_total_bytes':sum(x.get('bytes',0) for x in imgs),'unused_image_count':len(imgs)-len(used_images),'unused_image_bytes':unused,'duplicate_payload_bytes_including_unused':dupe,'referenced_duplicate_payload_bytes':used_dupe,'disjoint_image_prune_dedup_potential_bytes':unused+used_dupe,'duplicate_payload_groups':[x for x in groups.values() if len(x)>1],'default_scene_nodes':len(seen),'all_nodes':len(nodes),'default_scene_materials':sorted(active_materials),'all_material_count':len(j.get('materials',[])),'gltf_extensions_used':j.get('extensionsUsed',[])}

rows=[]
for source in handoff['rows']:
    row=dict(source);path=row['path'];row['instance_uuids']=refs[norm(path)];row['instance_count']=len(row['instance_uuids'])
    samples=[]
    for run in critical:
        if str(run.get('label','')).lower() not in ['b1','b2']:continue
        samples.extend(x for x in run['models'] if norm(x['path'])==norm(path))
    row['measured_wait_samples_ms']=[x['actual_wait_ms'] for x in samples if x.get('actual_wait_ms') is not None]
    row['measured_wait_mean_ms']=statistics.mean(row['measured_wait_samples_ms']) if row['measured_wait_samples_ms'] else None
    row['gltf_audit']=glb_audit(path)
    row['source_sha_matches_handoff']=row['gltf_audit']['current_sha256']==row['source_sha256']
    print(Path(path).name[:16],row['instance_count'],'unused MiB',round(row['gltf_audit']['unused_image_bytes']/2**20,2),'dupe MiB',round(row['gltf_audit']['referenced_duplicate_payload_bytes']/2**20,2),flush=True)
    rows.append(row)

hand_paths={norm(r['path']) for r in rows}
extra_models=[];texture_paths={}
for key,ids in refs.items():
    p=Path(key)
    if p.suffix=='.glb' and key not in hand_paths:
        extra_models.append({'path':key,'instances':len(ids),'uuids':ids,'exists':p.exists(),'bytes':p.stat().st_size if p.exists() else 0})
    elif p.suffix in ['.png','.jpg','.jpeg','.webp']:
        row={'path':key,'instances':len(ids),'exists':p.exists()}
        if p.exists():
            data=p.read_bytes();row.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
            try:
                im=Image.open(io.BytesIO(data));row.update(width=im.width,height=im.height,mode=im.mode)
            except Exception as ex:row['header_error']=str(ex)
        texture_paths[key]=row

cross=[v for v in images_global.values() if len({x['path'] for x in v})>1]
definition_usage=collections.Counter(r['uri'] for r in records)
defs=[dict(d,instances=definition_usage[d['uri']]) for d in inventory['definitions']]
external_dupes=collections.defaultdict(list)
for v in texture_paths.values():
    if 'sha256' in v:external_dupes[v['sha256']].append(v['path'])
output={'map_path':inventory['map'],'map_sha256':hashlib.sha256(Path(inventory['map']).read_bytes()).hexdigest(),'scope':'Read-only current authored map references; exact GLB compressed image equality and default-scene reachability. Potential pruning is not delivered savings, and extras or editor alternate-scene needs require review. Instance count affects draw/interaction, not N-fold shared source memory. Conservative full_peak_estimate is neither RSS nor VRAM.','rows':rows,'additional_current_model_paths':extra_models,'external_texture_paths':sorted(texture_paths.values(),key=lambda x:x.get('bytes',0),reverse=True),'external_texture_exact_duplicates':[v for v in external_dupes.values() if len(v)>1],'cross_glb_image_exact_duplicate_groups':cross,'definitions_by_file_bytes':sorted(defs,key=lambda x:x['file_bytes'],reverse=True),'totals':{'native_models':len(rows),'native_instances':sum(r['instance_count'] for r in rows),'native_source_bytes':sum(r['source_bytes'] for r in rows),'native_unused_embedded_image_bytes':sum(r['gltf_audit']['unused_image_bytes'] for r in rows),'native_disjoint_image_prune_dedup_potential_bytes':sum(r['gltf_audit']['disjoint_image_prune_dedup_potential_bytes'] for r in rows),'external_texture_paths':len(texture_paths),'external_texture_source_bytes':sum(x.get('bytes',0) for x in texture_paths.values()),'current_definition_file_bytes':sum(x['file_bytes'] for x in defs),'current_definition_raw_bytes':sum(x['raw_bytes'] for x in defs)}}
(OUT/'inventory_report.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(output['totals'],indent=2))
