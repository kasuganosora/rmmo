import bpy,bmesh,json,hashlib,sys,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,'D:/code/rmmo/tools')
import axel_market_realism_pottery_scroll as mod
out=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll')
master=Path('D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bounds(objs):
 pts=[o.matrix_world@Vector(p) for o in objs for p in o.bound_box]
 return [[min(v[k] for v in pts) for k in range(3)],[max(v[k] for v in pts) for k in range(3)]]
def signature(o):
 return hashlib.sha256(repr((o.name,o.type,tuple(v for row in o.matrix_world for v in row),[m.name for m in o.data.materials] if o.type in ('MESH','CURVE') else [],[(tuple(v.co)) for v in o.data.vertices] if o.type=='MESH' else [])).encode()).hexdigest()
report={'source':str(master),'source_sha256':sha(master),'module_sha256':sha(Path(mod.__file__)),'gpu_started':False,'checks':[],'assets':[]}
def check(v,label):report['checks'].append({'ok':bool(v),'label':label})
for key,cn in [('pottery','02_plum_vendor'),('scroll','04_scroll_vendor')]:
 col=bpy.data.collections[cn];contents=list(col.children)[0]
 outside=[o for o in col.all_objects if o not in set(contents.all_objects)]
 before={o.name:signature(o) for o in outside};bb=bounds(list(col.all_objects))
 result=mod.apply(key,col);after={o.name:signature(o) for o in outside}
 check(before==after,key+' structure/cloth/display slots unchanged')
 aa=bounds(list(col.all_objects));check(all(abs(bb[i][j]-aa[i][j])<1e-6 for i in range(2) for j in range(3)),key+' whole stall AABB unchanged')
 stats=[];triangles=0
 for o in contents.all_objects:
  ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();mesh.calc_loop_triangles()
  triangles+=len(mesh.loop_triangles)
  zero=sum(t.area<1e-12 for t in mesh.loop_triangles)
  bm=bmesh.new();bm.from_mesh(mesh);nonman=sum(not e.is_manifold for e in bm.edges);volume=bm.calc_volume(signed=True);bm.free()
  uv=mesh.uv_layers.active;uvok=uv is not None and all(math.isfinite(v) for loop in uv.data for v in loop.uv)
  check(zero==0,o.name+' no zero area triangles');check(nonman==0,o.name+' watertight shell');check(uvok,o.name+' finite UV')
  check(volume>0,o.name+' outward closed volume')
  check(bounds([o])[0][2]>=1.009-0.00005,o.name+' no penetration below counter surface')
  stats.append({'name':o.name,'type':o.type,'triangles':len(mesh.loop_triangles),'zero_area':zero,'nonmanifold_edges':nonman,'signed_volume_m3':volume,'finite_uv':uvok,'bounds':bounds([o]),'materials':[m.name for m in mesh.materials]})
  ev.to_mesh_clear()
 result['whole_stall_bounds_before']=bb;result['whole_stall_bounds_after']=aa;result['triangles']=triangles;result['object_stats']=stats
 report['assets'].append(result)
check(sha(master)==report['source_sha256'],'original master on disk unchanged')
report['passed']=all(c['ok'] for c in report['checks']);report['failed_checks']=[c for c in report['checks'] if not c['ok']]
(out/'cpu_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('CPU_REVIEW',report['passed'],len(report['checks']),[(a['asset_key'],a['triangles']) for a in report['assets']]);print(report['failed_checks'])
# Save only an explicitly separate CPU inspection copy, never the source master.
bpy.ops.wm.save_as_mainfile(filepath=str(out/'goods_cpu_inspection.blend'))
