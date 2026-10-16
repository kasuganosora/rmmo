"""CPU invariants only; no saving .blend, rendering or production import."""
import bpy,sys,json,hashlib,math
from pathlib import Path
ROOT=Path('D:/code/rmmo');sys.path.insert(0,str(ROOT/'tools'))
import axel_market_realism_wood as wood
source=Path('D:/code/rmmo_runtime/art_sources/town_market_stalls/town_market_stalls.blend')
out=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/wood');out.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def identity(o,uv=False):
    d={'matrix':[list(row) for row in o.matrix_world],'type':o.type}
    if o.type=='MESH':
        d.update(vertices=[list(v.co) for v in o.data.vertices],polygons=[list(p.vertices) for p in o.data.polygons],normals=[list(p.normal) for p in o.data.polygons])
        if uv:d['uv']=[[list(v.uv) for v in u.data] for u in o.data.uv_layers]
    return hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()
def material_identity(m):
    return [(n.name,n.type,n.image.name if n.type=='TEX_IMAGE' and n.image else None) for n in m.node_tree.nodes],[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]
source_sha=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source))
before={o.name:identity(o) for o in bpy.data.objects};nonwood={o.name:identity(o,True) for o in bpy.data.objects if o.type=='MESH' and not any(wood._wood(m) for m in o.data.materials)}
mat=bpy.data.materials[wood.WOOD_NAME];mat_before=material_identity(mat)
images={n.image.name:hashlib.sha256(bytes(n.image.packed_file.data)).hexdigest() for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'}
checks=[];reports={}
def check(name,ok,detail=None):checks.append({'name':name,'passed':bool(ok),'detail':detail})
for key,colname in [('pottery','02_plum_vendor'),('scroll','04_scroll_vendor'),('potion','03_potion_vendor'),('ore','05_ore_vendor')]:
    col=bpy.data.collections[colname];reports[key]=wood.apply(col)
    check(key+' idempotent authoring',reports[key]==wood.apply(col))
    front=[o for o in col.all_objects if o.name.startswith('Counter front boards')]
    hashes=[hashlib.sha256(json.dumps([list(v.uv) for v in o.data.uv_layers[wood.UV_NAME].data]).encode()).hexdigest() for o in front]
    check(key+' 13 front boards now distinct UV sampling',len(hashes)==13 and len(set(hashes))==13)
    for row in reports[key]['objects']:
        o=bpy.data.objects[row['object']]
        check(o.name+' finite valid source UV',all(math.isfinite(c) for uv in o.data.uv_layers[wood.UV_NAME].data for c in uv.uv))
        check(o.name+' original geometry matrix normals unchanged',identity(o)==before[o.name])
check('all original geometry/transform/normals unchanged',all(identity(bpy.data.objects[n])==h for n,h in before.items()))
check('all nonwood UV unchanged',all(identity(bpy.data.objects[n],True)==h for n,h in nonwood.items()))
check('original timber shader unchanged',material_identity(mat)==mat_before)
check('original packed PBR bytes unchanged',images=={n.image.name:hashlib.sha256(bytes(n.image.packed_file.data)).hexdigest() for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'})
target=bpy.data.materials[wood.MATERIAL_NAME]
check('three source PBR images use explicit UV',all(n.inputs['Vector'].is_linked and n.inputs['Vector'].links[0].from_node.uv_map==wood.UV_NAME for n in target.node_tree.nodes if n.type=='TEX_IMAGE'))
check('normal tangent basis uses matching UV',all(n.uv_map==wood.UV_NAME for n in target.node_tree.nodes if n.type=='NORMAL_MAP'))
check('source master file SHA unchanged',sha(source)==source_sha)
report={'module_sha256':sha(ROOT/'tools/axel_market_realism_wood.py'),'passed':all(c['passed'] for c in checks),'check_count':len(checks),'failures':[c for c in checks if not c['passed']],'checks':checks,'results':reports,'source_sha256':source_sha,'source_pbr_packed_sha256':images,'gpu':'not run'}
(out/'cpu_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('WOOD_CPU',json.dumps({'passed':report['passed'],'checks':len(checks),'counts':{k:v['wood_object_count'] for k,v in reports.items()},'failures':report['failures']}))
if not report['passed']:raise RuntimeError('Wood CPU invariant failed')
