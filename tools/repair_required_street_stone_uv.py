"""Continuous rock-side unwrap after actual closeup exposed per-face seams."""
import bpy,json,sys,math,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def main():
    manifest=json.loads((common.OUT/'manifest.json').read_text(encoding='utf8'))
    selected=[r for r in manifest['assets'] if r['id'].startswith('s12_water_step')]
    kept={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in selected}
    source=common.OUT/'street_assets_master_reviewed.blend';rollback=common.OUT/'rollback/stone_uv_v1';rollback.mkdir(parents=True,exist_ok=True)
    for path in [source,common.OUT/'manifest.json',*[Path(r['path']) for r in selected]]:
        target=rollback/path.name
        if not target.exists():shutil.copy2(path,target)
    bpy.ops.wm.open_mainfile(filepath=str(source));groups={};records=[]
    for row in selected:
        groups[row['id']]=list(bpy.data.collections[row['id']].objects)
        for ob in groups[row['id']]:
            if ob.type!='MESH' or len(ob.data.vertices)!=241:continue
            me=ob.data;uv=me.uv_layers.active
            circumference=sum(math.hypot(v.co.x,v.co.y) for v in list(me.vertices)[80:120])/40*math.tau
            h=max(v.co.z for v in me.vertices)
            for face in me.polygons:
                top=face.normal.z>.6 and face.center.z>h-.06
                angles=[math.atan2(me.vertices[me.loops[li].vertex_index].co.x,-me.vertices[me.loops[li].vertex_index].co.y)/math.tau+.5 for li in face.loop_indices]
                wraps=max(angles)-min(angles)>.5
                for li,a in zip(face.loop_indices,angles):
                    co=me.vertices[me.loops[li].vertex_index].co
                    if top or face.normal.z<-.7:uv.data[li].uv=(co.x/1.5+.31,co.y/1.5+.27)
                    else:uv.data[li].uv=((a+(1 if wraps and a<.5 else 0))*circumference/1.5,co.z/1.5)
            ob['stone_uv_revision']='continuous metric side unwrap and planar tread 20261013'
            records.append({'object':ob.name,'geometry_unchanged':True,'circumference_m':circumference})
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    rows={r['id']:common.export(r,groups[r['id']],source) for r in selected}
    manifest['assets']=[rows.get(r['id'],r) for r in manifest['assets']]
    assert all(common.digest(p)==sha for p,sha in kept.items())
    (common.OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (common.OUT/'stone_uv_report.json').write_text(json.dumps({'fixed':records,'unchanged_sha':kept},indent=2),encoding='utf8')
    print('STONE_UV_FIXED',len(records),flush=True)

if __name__=='__main__':main()
