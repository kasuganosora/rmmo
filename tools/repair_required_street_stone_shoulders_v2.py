"""Rebuild the actual boulder shoulder profile outside the central walk strip.

Uses the pre-crown rollback as a deterministic geometry baseline, retaining
the current mother's other assets. All collisions derive from visible meshes.
"""
import bpy, bmesh, math, json, shutil, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def main():
    mp=common.OUT/'manifest.json'; manifest=json.loads(mp.read_text(encoding='utf-8'))
    rows=[r for r in manifest['assets'] if r['id'].startswith('s12_water_step')]
    source=common.OUT/'street_assets_master_reviewed.blend'
    rollback=common.OUT/'rollback/stone_shoulders_v2';rollback.mkdir(parents=True,exist_ok=True)
    for p in [source,mp,*[Path(r['path']) for r in rows]]:
        if not (rollback/p.name).exists():shutil.copy2(p,rollback/p.name)
    unchanged={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in rows}
    # Snapshot the known passable X crown before the rejected shoulder edits.
    bpy.ops.wm.open_mainfile(filepath=str(common.OUT/'rollback/stone_crown_v1/street_assets_master_reviewed.blend'))
    baseline={o.name:[tuple(v.co) for v in o.data.vertices] for r in rows for o in bpy.data.collections[r['id']].objects if o.type=='MESH'}
    bpy.ops.wm.open_mainfile(filepath=str(source))
    groups={};records=[]
    for row in rows:
        groups[row['id']]=list(bpy.data.collections[row['id']].objects)
        for ob in groups[row['id']]:
            if ob.type!='MESH' or len(ob.data.vertices)!=241:continue
            me=ob.data;old=baseline[ob.name];h=old[240][2]-.003
            letter=next(c for c in 'abcd' if 's12_water_step_'+c in ob.name)
            phase='abcd'.index(letter)*1.53
            for v,co in zip(me.vertices,old):v.co=co
            for i in range(40):
                a=math.tau*i/40;edge=old[80+i]
                # Exact 0.50m-wide centre lane retains prior passable vertices.
                s=max(0.,min(1.,(abs(edge[1])-.25)/.14));s=s*s*(3-2*s)
                if s==0:continue
                fracture=.5+.5*math.sin(3*a+phase)
                wider=1.22+.18*fracture
                # Asymmetric broad belly and low-to-high fracture shoulders.
                for ring,yfactor,z in [(0,1.05+.09*fracture,0.),(1,wider,.06),
                    (2,wider+.04,.24+.02*fracture),(3,wider-.01,.34+.045*fracture),
                    (4,.86+.08*fracture,.465+.04*fracture),(5,.50+.08*fracture,h-.035-.035*(1-fracture))]:
                    v=me.vertices[40*ring+i]
                    v.co.y=old[40*ring+i][1]*(1-s)+edge[1]*yfactor*s
                    v.co.z=old[40*ring+i][2]*(1-s)+z*s
                    # Distinct irregular corners; the untouched central lip
                    # continues to cover every lower X contour in the lane.
                    xfactor=1-.06*s*(.5+.5*math.sin(4*a+phase+.4))
                    v.co.x=old[40*ring+i][0]*xfactor
            me.update()
            bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
            for face in me.polygons:
                rings={v//40 for v in face.vertices if v<240}
                face.use_smooth=not (rings and min(rings)>=2 and max(rings)<=5 and abs(face.center.y)>.30)
            # Side UV remains continuous around the body. The large, low
            # shoulder uses the same field instead of restarting each face.
            uv=me.uv_layers.active
            circ=sum(math.hypot(v.co.x,v.co.y) for v in list(me.vertices)[80:120])/40*math.tau
            for face in me.polygons:
                top=face.normal.z>.6 and face.center.z>h-.09
                angles=[math.atan2(me.vertices[me.loops[li].vertex_index].co.x,-me.vertices[me.loops[li].vertex_index].co.y)/math.tau+.5 for li in face.loop_indices]
                wraps=max(angles)-min(angles)>.5
                for li,a in zip(face.loop_indices,angles):
                    co=me.vertices[me.loops[li].vertex_index].co
                    uv.data[li].uv=(co.x/1.5+.31,co.y/1.5+.27) if top or face.normal.z<-.7 else ((a+(1 if wraps and a<.5 else 0))*circ/1.5,co.z/1.5)
            ob['stone_crown_revision']='Broad irregular exposed shoulders v2; exact central 0.50m X-lane; no proxy collision'
            records.append({'object':ob.name,'section_y':[[k,*list(me.vertices[k*40+10].co)] for k in range(6)],'central_lane_unchanged':all(tuple(me.vertices[k*40+i].co)==tuple(old[k*40+i]) for k in range(6) for i in range(40) if abs(old[80+i][1])<=.25)})
    assert len(records)==8 and all(r['central_lane_unchanged'] for r in records)
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    updates={r['id']:common.export(r,groups[r['id']],source) for r in rows}
    for row in rows:updates[row['id']]['baseline_sha256']=row['baseline_sha256']
    manifest['assets']=[updates.get(r['id'],r) for r in manifest['assets']]
    manifest['stone_reference_revision']='Broad fractured shoulders v2; above .34m waterline, central .50m lane unchanged'
    mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    assert all(common.digest(p)==s for p,s in unchanged.items())
    (common.OUT/'stone_shoulders_v2_report.json').write_text(json.dumps({'changes':records,'rollback':str(rollback),'unchanged_assets':unchanged,'visual':'pending waterline and near','traversal':'pending'},indent=2),encoding='utf-8')
    print('BROAD_SHOULDERS_V2',[(r['id'],r['sha256']) for r in updates.values()],flush=True)

if __name__=='__main__':main()
