"""Fix cap-to-shaft shading only on S12 arch and the example installation."""
import bpy,json,shutil,sys,math
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

OUT=common.OUT
def main():
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    selected=[r for r in manifest['assets'] if r['id'] in ['s12_projecting_arch','s12_facade_installation_demo']]
    kept={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in selected}
    source=OUT/'street_assets_master_reviewed.blend';rollback=OUT/'rollback/shaft_normal_v1';rollback.mkdir(parents=True,exist_ok=True)
    for path in [source,OUT/'manifest.json',*[Path(r['path']) for r in selected]]:
        target=rollback/path.name
        if not target.exists():shutil.copy2(path,target)
    bpy.ops.wm.open_mainfile(filepath=str(source));groups={};fixed=[]
    for row in selected:
        groups[row['id']]=list(bpy.data.collections[row['id']].objects)
        for ob in groups[row['id']]:
            if ob.type!='MESH' or not any(ob.name.startswith(s) for s in ['Jointed tapered shaft','Moulded column base','Neck and bell capital']):continue
            me=ob.data;normals=[Vector((0,0,1)) for _ in me.loops]
            # Compute side normals excluding cap faces, preserving profile slope.
            side=[Vector((0,0,0)) for _ in me.vertices]
            for p in me.polygons:
                if len(p.vertices)>4:continue
                for vi in p.vertices:side[vi]+=p.normal
            for p in me.polygons:
                is_cap=len(p.vertices)>4
                p.use_smooth=not is_cap
                for li in p.loop_indices:normals[li]=p.normal if is_cap else side[me.loops[li].vertex_index].normalized()
            me.normals_split_custom_set(normals);me.update();fixed.append(ob.name)
            ob['reference_normal_revision']='20261013_cap_side_split'
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    rows={r['id']:common.export(r,groups[r['id']],source) for r in selected}
    manifest['assets']=[rows.get(r['id'],r) for r in manifest['assets']]
    assert all(common.digest(p)==sha for p,sha in kept.items())
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'column_normals_report.json').write_text(json.dumps({'fixed':fixed,'unchanged_sha':kept,'geometry_positions_unchanged':True,'normal_rule':'Lathe sides exclude ngon cap normals; flat caps retain axial normals'},indent=2),encoding='utf8')
    print('COLUMN_NORMALS_FIXED',len(fixed),flush=True)

if __name__=='__main__':main()
