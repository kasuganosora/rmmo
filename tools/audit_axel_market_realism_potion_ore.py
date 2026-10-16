"""Load unchanged source master, exercise authoring module, CPU audit, no render."""
import bpy,bmesh,json,hashlib,sys,math
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo');sys.path.insert(0,str(ROOT/'tools'))
import axel_market_realism_potion_ore as module
SOURCE=Path('D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend')
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/potion_ore');OUT.mkdir(parents=True,exist_ok=True)
ART=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/potion_ore');ART.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def identity(o):
    payload={'matrix':[list(r) for r in o.matrix_world],'type':o.type,'materials':[m.name if m else None for m in o.data.materials] if o.type=='MESH' else []}
    if o.type=='MESH':payload.update(vertices=[list(v.co) for v in o.data.vertices],polygons=[list(p.vertices) for p in o.data.polygons],uvs=[[list(uv.uv) for uv in layer.data] for layer in o.data.uv_layers])
    return hashlib.sha256(json.dumps(payload,sort_keys=True).encode()).hexdigest()
def bounds(objects):
    points=[o.matrix_world@Vector(p) for o in objects if o.type=='MESH' for p in o.bound_box]
    return [[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
before_sha=sha(SOURCE);bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
before={o.name:identity(o) for o in bpy.data.objects}
checks=[];results={}
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
for key,variant in [('potion','03_potion_vendor'),('ore','05_ore_vendor')]:
    col=bpy.data.collections[variant];before_bounds=bounds(col.all_objects)
    stable={o.name:identity(o) for o in col.all_objects if o.name.startswith(('Potion display shelf','Shelf feet','Ore sorting bin'))}
    result=module.apply(key,col);new=[o for o in col.all_objects if o.get('market_realism_version')]
    after_bounds=bounds(col.all_objects)
    check(key+' overall bounds unchanged',all(abs(before_bounds[j][i]-after_bounds[j][i])<1e-6 for j in range(2) for i in range(3)),{'before':before_bounds,'after':after_bounds})
    check(key+' original display support untouched',all(identity(bpy.data.objects[n])==h for n,h in stable.items()),{'objects':len(stable)})
    meshes=[];total_tri=0
    for o in new:
        bm=bmesh.new();bm.from_mesh(o.data)
        manifold=all(e.is_manifold for e in bm.edges)
        tiny=sum(1 for f in bm.faces if f.calc_area()<1e-12)
        finite=all(math.isfinite(c) for v in bm.verts for c in v.co)
        bm.free();o.data.calc_loop_triangles();tri=len(o.data.loop_triangles);total_tri+=tri
        check(o.name+' closed finite positive-area',manifold and tiny==0 and finite,{'nonmanifold':not manifold,'tiny_faces':tiny})
        check(o.name+' UV present finite',bool(o.data.uv_layers) and all(math.isfinite(c) for uv in o.data.uv_layers.active.data for c in uv.uv))
        if o.get('rmmo_tinted_glass'):
            raw=o['rmmo_tinted_glass'].to_dict()
            valid=raw['version']==1 and all(len(s['transmittance'])==3 and all(0<v<=1 for v in s['transmittance']) and .02<=s['roughness']<=.6 for s in raw['materials'].values())
            check(o.name+' current optical contract valid',valid and set(raw['materials'])=={m.name for m in o.data.materials})
        meshes.append({'name':o.name,'part':o['market_goods_part'],'specimen':o['market_specimen_id'],'group':o['rmmo_export_group'],'triangles':tri,'materials':[m.name for m in o.data.materials]})
    if key=='potion':
        for part in ['glass_shell','liquid','cork','label']:
            check('16 '+part,sum(o.get('market_goods_part')==part for o in new)==16)
        check('preserve 6 emerald 6 amethyst 4 amber',[(k,sum(b['kind']==k for b in result['bottles'])) for k in ['Emerald','Amethyst','Amber']]==[('Emerald',6),('Amethyst',6),('Amber',4)])
        check('actual 2.2mm sidewall + 4.2mm base + below-neck fill',all(b['wall_m']==.0022 and b['fill_m']<b['height_m']*.70 for b in result['bottles']))
    else:
        check('30 distinct specimens retained',len({o['market_specimen_id'] for o in new})==30)
        check('10 six-sided beryl specimens',sum(o['market_goods_part']=='beryl_hex_prism' for o in new)==10)
        for spec in result['specimens']:
            bb=bounds([o for o in new if o['market_specimen_id']==spec['id']])
            check(spec['id']+' original specimen AABB retained',all(abs(bb[j][i]-spec[['old_bounds_min','old_bounds_max'][j]][i])<1e-6 for j in range(2) for i in range(3)))
    result.update({'new_meshes':meshes,'new_triangles':total_tri,'bounds_before':before_bounds,'bounds_after':after_bounds,'untouched_display_hashes':stable})
    results[key]=result
changed_unowned=[n for n,h in before.items() if n in bpy.data.objects and not bpy.data.objects[n].get('market_realism_version') and identity(bpy.data.objects[n])!=h]
check('all surviving original objects unchanged',not changed_unowned,changed_unowned)
check('source master SHA unchanged',sha(SOURCE)==before_sha,before_sha)
report={'version':1,'source':str(SOURCE),'source_sha256':before_sha,'module_sha256':sha(ROOT/'tools/axel_market_realism_potion_ore.py'),'checks':checks,'passed':all(c['passed'] for c in checks),'check_count':len(checks),'failures':[c for c in checks if not c['passed']],'results':results,'gpu':'not run','final_art_acceptance':'pending root unified baked/native GPU review','formal_import':'not performed'}
(OUT/'cpu_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
if not report['passed']:raise RuntimeError(json.dumps(report['failures'],ensure_ascii=False))
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'potion_ore_authoring.blend'))
(OUT/'authoring_blend_identity.json').write_text(json.dumps({'path':str(ART/'potion_ore_authoring.blend'),'sha256':sha(ART/'potion_ore_authoring.blend'),'bytes':(ART/'potion_ore_authoring.blend').stat().st_size},indent=2),encoding='utf8')
print('CPU_AUDIT',json.dumps({'passed':report['passed'],'checks':len(checks),'triangles':{k:r['new_triangles'] for k,r in results.items()},'report':str(OUT/'cpu_audit.json')}))
