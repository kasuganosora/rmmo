"""Visible S12 rock shoulders above water, keeping the central X approach.

Only true visible vertices are changed; production collision uses that same
mesh. There is no proxy bridge, added cap, or invisible walking surface.
"""
import bpy, json, math, shutil, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def main():
    manifest_path=common.OUT/'manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    selected=[r for r in manifest['assets'] if r['id'].startswith('s12_water_step')]
    unchanged={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in selected}
    source=common.OUT/'street_assets_master_reviewed.blend'
    rollback=common.OUT/'rollback/stone_crown_v1';rollback.mkdir(parents=True,exist_ok=True)
    for p in [source,manifest_path,*[Path(r['path']) for r in selected]]:
        if not (rollback/p.name).exists():shutil.copy2(p,rollback/p.name)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    groups={};records=[]
    for row in selected:
        groups[row['id']]=list(bpy.data.collections[row['id']].objects)
        for ob in groups[row['id']]:
            if ob.type!='MESH' or len(ob.data.vertices)!=241:continue
            me=ob.data;h=me.vertices[240].co.z-.003
            letter=next(c for c in 'abcd' if 's12_water_step_'+c in ob.name)
            phase=(ord(letter)-ord('a'))*1.31
            changed=0
            for i in range(40):
                a=math.tau*i/40
                # Preserve exact broad entry/exit lips at both X ends. The
                # large sloped shoulders appear towards Y and the corners.
                shoulder=max(0.,min(1.,(abs(math.sin(a))-.44)/.42))
                shoulder=shoulder*shoulder*(3-2*shoulder)
                if shoulder==0:continue
                edge=me.vertices[80+i].co.copy()
                fracture=.5+.5*math.sin(5*a+phase)
                for ring,depth,y_scale in [(3,.255-.05*fracture,.95-.025*fracture),
                                          (4,.125-.045*fracture,.81+.035*fracture),
                                          (5,.030+.020*fracture,.64+.065*fracture)]:
                    v=me.vertices[ring*40+i]
                    v.co.y=v.co.y*(1-shoulder)+edge.y*y_scale*shoulder
                    v.co.z=v.co.z*(1-shoulder)+(h-depth)*shoulder
                    v.co.x*=1-shoulder*.035*fracture
                    changed+=1
            me.update()
            # Broad fracture planes stay readable. High-frequency chipped
            # detail remains the PBR map and existing small arris bevel.
            for face in me.polygons:
                rings={vi//40 for vi in face.vertices if vi<240}
                side=abs(face.center.y)>.30
                if side and rings and min(rings)>=3 and max(rings)<=5:face.use_smooth=False
            uv=me.uv_layers.active
            circumference=sum(math.hypot(v.co.x,v.co.y) for v in list(me.vertices)[80:120])/40*math.tau
            for face in me.polygons:
                top=face.normal.z>.6 and face.center.z>h-.06
                angles=[math.atan2(me.vertices[me.loops[li].vertex_index].co.x,-me.vertices[me.loops[li].vertex_index].co.y)/math.tau+.5 for li in face.loop_indices]
                wraps=max(angles)-min(angles)>.5
                for li,a in zip(face.loop_indices,angles):
                    co=me.vertices[me.loops[li].vertex_index].co
                    if top or face.normal.z<-.7:uv.data[li].uv=(co.x/1.5+.31,co.y/1.5+.27)
                    else:uv.data[li].uv=((a+(1 if wraps and a<.5 else 0))*circumference/1.5,co.z/1.5)
            ob['stone_crown_revision']='S12 exposed fractured Y shoulders above 0.34m water; original X entry/exit preserved'
            records.append({'object':ob.name,'upper_vertices_changed':changed,'height':h,'waterline':.34,'original_x_approach_sectors_preserved':True})
    assert len(records)==8
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    replacements={r['id']:common.export(r,groups[r['id']],source) for r in selected}
    # Keep the original model provenance instead of replacing it with the
    # immediately preceding review candidate's hash.
    for row in selected:replacements[row['id']]['baseline_sha256']=row['baseline_sha256']
    manifest['assets']=[replacements.get(r['id'],r) for r in manifest['assets']]
    manifest['stone_reference_revision']='S12 visible fractured shoulder above .34m water; exact original X entry/exit lips and real collision'
    assert all(common.digest(p)==s for p,s in unchanged.items())
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (common.OUT/'stone_crown_report.json').write_text(json.dumps({'changes':records,'unchanged_assets':unchanged,'rollback':str(rollback),'visual':'pending same-camera native images','traversal':'pending production capsule'},indent=2),encoding='utf-8')
    print('STONE_CROWNS_REPAIRED',[(r['id'],r['sha256']) for r in replacements.values()],flush=True)

if __name__=='__main__':main()
