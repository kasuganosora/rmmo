import json,struct,collections,pathlib,math
root=pathlib.Path('review_artifacts/editor_render_hotspot_audit_20261007')
d=json.load(open('D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf',encoding='utf-8'))
records=[r for r in d['nodes'][0]['extras']['rmmo_records'] if r.get('kind')=='asset' and 'house_prefab' not in r]
groups=collections.defaultdict(list)
for r in records:groups[r.get('asset_path')].append(r)
out=[]
for path,rs in sorted(groups.items(),key=lambda x:-len(x[1])):
  with open(path,'rb') as f:
    magic,version,length=struct.unpack('<III',f.read(12)); size,kind=struct.unpack('<II',f.read(8)); g=json.loads(f.read(size))
  meshes=g.get('meshes',[]); nodes=g.get('nodes',[]); materials=g.get('materials',[])
  rows=[]
  for n in nodes:
    if 'mesh' not in n:continue
    mesh=meshes[int(n['mesh'])]
    rows.append({'name':n.get('name'),'extras':n.get('extras',{}),'primitives':len(mesh['primitives']),'triangles':sum(int(g['accessors'][int(p['indices'])]['count'])//3 if 'indices' in p else int(g['accessors'][int(p['attributes']['POSITION'])]['count'])//3 for p in mesh['primitives']),'materials':[int(p.get('material',-1)) for p in mesh['primitives']],'skin':n.get('skin'),'morph':bool(mesh.get('weights'))})
  cells={}
  for cell in [8,16,32]:
    buckets=collections.Counter((math.floor(r['position'][0]/cell),math.floor(r['position'][2]/cell)) for r in rs)
    cells[str(cell)]={'groups':len(buckets),'members_in_multiple':sum(v for v in buckets.values() if v>1),'multi_groups':sum(v>1 for v in buckets.values())}
  out.append({'path':path,'instances':len(rs),'record_keys':sorted(set(k for r in rs for k in r)),'collision':dict(collections.Counter(r.get('collision','missing') for r in rs)),'record_wind':dict(collections.Counter(json.dumps(r.get('wind_response',{}),sort_keys=True) for r in rs)),'mesh_nodes':rows,'materials':[{'name':m.get('name'),'alphaMode':m.get('alphaMode','OPAQUE'),'doubleSided':m.get('doubleSided',False),'extensions':m.get('extensions',{})} for m in materials],'animations':len(g.get('animations',[])),'cell_candidates':cells})
(root/'asset_census.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
for x in out:
 print(x['instances'],pathlib.Path(x['path']).name[:12],len(x['mesh_nodes']),[n['name'] for n in x['mesh_nodes']],[(n['extras'].get('rmmo_wind',{}).get('profile'),n['extras'].get('rmmo_visibility_range')) for n in x['mesh_nodes']],[(m['alphaMode']) for m in x['materials']],x['cell_candidates']['16'])
print('records',len(records),'paths',len(out))
