import json,collections,pathlib
root=pathlib.Path('review_artifacts/editor_render_hotspot_audit_20261007')
d=json.load(open('D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf',encoding='utf-8')); records={r['uuid']:r for r in d['nodes'][0]['extras']['rmmo_records']};t=collections.defaultdict(lambda:collections.Counter()); samples=collections.defaultdict(list)
def category(r):
 if 'house_prefab' in r:
  if 'building' in r:return 'frozen_building_fixture' if 'fixture' in r else 'frozen_building_'+r['building'].get('role','?')
  return 'frozen_'+ ('fortification' if 'fortification' in r else 'bridge')
 if r.get('kind')=='asset':return 'imported_asset'
 for k in ['channel_mesh','terrain_mesh','road_mesh','rock_bank','building','fortification']:
  if k in r:return k
 return 'other'
def visit(idx,record=None):
 n=d['nodes'][int(idx)];r=records.get(n.get('extras',{}).get('uuid'),records.get(n.get('extras',{}).get('uuid','').split('__')[0],records.get(n.get('name'),record)))
 if 'mesh' in n:
  c=category(r) if r else 'unmatched';counter=t[c];mesh=d['meshes'][int(n['mesh'])]; ps=mesh['primitives']; counter['mesh_nodes']+=1;counter['surfaces']+=len(ps)
  for p in ps:
   mat=d['materials'][int(p['material'])] if 'material' in p else {};counter['alpha_'+mat.get('alphaMode','OPAQUE')]+=1
  if len(samples[c])<3:samples[c].append({'name':n.get('name'),'surfaces':len(ps),'record':r['uuid'] if r else ''})
 for child in n.get('children',[]):visit(child,r)
visit(0)
out={'note':'Export JSON geometry census, not runtime visibility/draws. Before generated shared batches, wind overrides, shadows and screen culling. Mesh references counted per node, not unique resources.','groups':{k:dict(v) for k,v in sorted(t.items(),key=lambda kv:-kv[1]['surfaces'])},'samples':dict(samples)}
(root/'export_geometry_census.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(out['groups'],indent=2))
