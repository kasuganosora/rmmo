"""Restore acquired branch UVs only; preserve corrected trunk/fruit/leaf data."""
import bpy,json,sys,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def main():
    original=common.BASE/'redfruit_master.blend'
    source=common.OUT/'redfruit_master_reviewed.blend'
    manifest=json.loads((common.OUT/'manifest.json').read_text(encoding='utf8'))
    row=next(r for r in manifest['assets'] if r['id']=='s10_redfruit_broadleaf')
    unchanged={r['path']:common.digest(r['path']) for r in manifest['assets'] if r!=row}
    rollback=common.OUT/'rollback/tree_branch_uv_v1';rollback.mkdir(parents=True,exist_ok=True)
    for path in [source,Path(row['path']),common.OUT/'manifest.json']:
        target=rollback/path.name
        if not target.exists():shutil.copy2(path,target)
    bpy.ops.wm.open_mainfile(filepath=str(original));saved={}
    for ob in bpy.data.objects:
        if ob.type!='MESH' or 'Canopy' not in ob.name:continue
        uv=ob.data.uv_layers['UVMap'];slots={i for i,m in enumerate(ob.data.materials) if 'bark' in m.name.lower()}
        saved[ob.name]={'vertices':len(ob.data.vertices),'loops':len(ob.data.loops),'uv':{li:tuple(uv.data[li].uv) for p in ob.data.polygons if p.material_index in slots for li in p.loop_indices}}
    assert len(saved)==3
    bpy.ops.wm.open_mainfile(filepath=str(source));counts={}
    for name,record in saved.items():
        ob=bpy.data.objects[name];assert len(ob.data.vertices)==record['vertices'] and len(ob.data.loops)==record['loops']
        uv=ob.data.uv_layers['UVMap']
        for li,value in record['uv'].items():uv.data[li].uv=value
        counts[name]=len(record['uv']);ob['branch_uv_revision']='Original acquired branch unwrap retained, 20261013'
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    new=common.export(row,[o for o in bpy.data.objects if o.type=='MESH'],source,tree=True)
    manifest['assets']=[new if r['id']==row['id'] else r for r in manifest['assets']]
    assert all(common.digest(p)==sha for p,sha in unchanged.items())
    (common.OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (common.OUT/'tree_branch_uv_report.json').write_text(json.dumps({'branch_corners_restored':counts,'unchanged_sha':unchanged,'preserved':'fruit skin/roughness/corrected fruit UV, main trunk UV, leaf UV/geometry/alpha, wind and all three LODs','sha256':new['sha256']},ensure_ascii=False,indent=2),encoding='utf8')
    print('BRANCH_UV_RESTORED',counts,new['sha256'],flush=True)

if __name__=='__main__':main()
