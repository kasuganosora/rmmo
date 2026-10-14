"""Fit the installation fixture's real wall opening to the supported arch."""
import bpy,bmesh,json,math,shutil,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def main():
    manifest_path=common.OUT/'manifest.json';manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    row=next(r for r in manifest['assets'] if r['id']=='s12_facade_installation_demo')
    unchanged={r['path']:common.digest(r['path']) for r in manifest['assets'] if r is not row}
    source=common.OUT/'street_assets_master_reviewed.blend'
    rollback=common.OUT/'rollback/demo_opening_v1';rollback.mkdir(parents=True,exist_ok=True)
    for p in [source,manifest_path,Path(row['path'])]:
        if not (rollback/p.name).exists():shutil.copy2(p,rollback/p.name)
    bpy.ops.wm.open_mainfile(filepath=str(source));col=bpy.data.collections[row['id']]
    upper=next(o for o in col.objects if o.name.startswith('Example lintel and upper wall'))
    lo=min(v.co.z for v in upper.data.vertices)
    for v in upper.data.vertices:
        if abs(v.co.z-lo)<1e-5:v.co.z=5.30
    upper.data.update();common.assign_uv(upper)
    r=1.14;spring=3.67;outline=[(-1.5,0),(-r,0),(-r,spring)]
    outline += [(-r*math.cos(math.pi*i/48),spring+r*math.sin(math.pi*i/48)) for i in range(1,49)]
    outline += [(r,0),(1.5,0),(1.5,5.30),(-1.5,5.30)]
    n=len(outline);verts=[(x,y,z) for y in [0.,.6] for x,z in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new('True curved wall opening infill');me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new('True curved wall opening infill',me);col.objects.link(ob)
    me.materials.append(upper.data.materials[0]);common.assign_uv(ob)
    for key,value in upper.items():ob[key]=value
    ob['rmmo_collision']='block';ob['reference_revision']='S12 exact curved masonry opening; no rectangular sky gaps'
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    updated=common.export(row,list(col.objects),source);updated['baseline_sha256']=row['baseline_sha256']
    updated['installation']['real_opening_width']=2.28;updated['installation']['real_opening_height']=4.81
    manifest['assets']=[updated if r['id']==row['id'] else r for r in manifest['assets']]
    assert all(common.digest(p)==s for p,s in unchanged.items())
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (common.OUT/'demo_opening_report.json').write_text(json.dumps({'sha256':updated['sha256'],'inner_radius':1.14,'spring':3.67,'top_clearance':4.81,'wall_thickness':.6,'unchanged_assets':unchanged,'scope':'Installation test wall only; original independent arch and relief unchanged'},indent=2),encoding='utf-8')
    print('DEMO_OPENING_REPAIRED',updated['sha256'],flush=True)

if __name__=='__main__':main()
