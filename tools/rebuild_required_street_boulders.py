"""Ordered convex crowns and broad irregular shoulders; no bevelled top fans."""
import bpy,bmesh,math,json,shutil,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

def mesh_for(letter):
    n=48;idx='abcd'.index(letter);phase=idx*1.57
    width=[1.02,.90,1.12,.98][idx]
    # The upper X lip overhangs the narrower submerged ends; downward step
    # probes cannot catch an outward belly before reaching the visible tread.
    profiles=[(0.,.51,.56),(.06,.58,.65),(.245,.600,.69),(.35,.600,.685),
              (.445,.600,.60),(.515,.600,.505),(.566,.600,.445),(.594,.600,.40)]
    points=[]
    def contour(a,rx,ry):
        ca,sa=math.cos(a),math.sin(a)
        # Same positive radial multiplier for X/Y preserves cyclic ordering.
        edge=1+(.055*math.sin(3*a+phase)+.025*math.sin(5*a-phase))*abs(sa)**1.5
        x=rx*math.copysign(abs(ca)**(2/3.5),ca)*edge
        y=ry*width*math.copysign(abs(sa)**(2/3.5),sa)*edge
        return x,y
    for ring,(z,rx,ry) in enumerate(profiles):
        for i in range(n):
            a=math.tau*i/n;x,y=contour(a,rx,ry)
            # Low shoulder chips vary only a few millimetres at the crown.
            ripple=(.009 if ring<6 else .003)*math.sin(3*a+phase)*abs(math.sin(a))
            points.append((x,y,max(0,z+ripple)))
    outer=points[-n:]
    for factor,z in [(.72,.598),(.38,.600)]:
        points.extend((x*factor,y*factor,z+.0015*math.sin(math.tau*i/n+phase)) for i,(x,y,_) in enumerate(outer))
    nr=10;center=len(points);points.append((0,0,.6015))
    faces=[tuple(reversed(range(n)))]
    for k in range(nr-1):
        for i in range(n):
            j=(i+1)%n;faces.append((k*n+i,k*n+j,(k+1)*n+j,(k+1)*n+i))
    faces.extend(((nr-1)*n+i,(nr-1)*n+(i+1)%n,center) for i in range(n))
    me=bpy.data.meshes.new('S12 natural boulder '+letter+' ordered shoulder');me.from_pydata(points,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
    assert all(p.normal.z>0 for p in me.polygons if all(me.vertices[v].co.z>.57 for v in p.vertices))
    assert all(p.area>1e-9 for p in me.polygons)
    # No radial top edges are bevelled. The explicitly sampled shoulder
    # carries smooth normals, with a flat underside and soft shallow crown.
    for p in me.polygons:p.use_smooth=p.normal.z>-.9
    uv=me.uv_layers.new(name='ContinuousStoneUV')
    circumference=sum(math.hypot(x,y) for x,y,z in points[2*n:3*n])/n*math.tau
    for p in me.polygons:
        # Planar top/shoulder projection makes the visible crown continuous;
        # bottom and submerged side keep a continuous angular field.
        top=p.center.z>.33 and p.normal.z>.12
        angles=[math.atan2(me.vertices[me.loops[li].vertex_index].co.x,-me.vertices[me.loops[li].vertex_index].co.y)/math.tau+.5 for li in p.loop_indices]
        wraps=max(angles)-min(angles)>.5
        for li,a in zip(p.loop_indices,angles):
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(co.x/1.5+.31,co.y/1.5+.27) if top or p.normal.z<-.7 else ((a+(1 if wraps and a<.5 else 0))*circumference/1.5,co.z/1.5)
    return me

def main():
    mp=common.OUT/'manifest.json';manifest=json.loads(mp.read_text(encoding='utf-8'));source=common.OUT/'street_assets_master_reviewed.blend'
    rows=[r for r in manifest['assets'] if r['id'].startswith('s12_water_step')]
    unchanged={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in rows}
    rollback=common.OUT/'rollback/ordered_boulders_v3';rollback.mkdir(parents=True,exist_ok=True)
    for p in [mp,source,*[Path(r['path']) for r in rows]]:
        if not (rollback/p.name).exists():shutil.copy2(p,rollback/p.name)
    bpy.ops.wm.open_mainfile(filepath=str(source));groups={};records=[]
    for row in rows:
        groups[row['id']]=list(bpy.data.collections[row['id']].objects)
        for ob in groups[row['id']]:
            if ob.type!='MESH':continue
            letter=next(c for c in 'abcd' if 's12_water_step_'+c in ob.name)
            materials=list(ob.data.materials);me=mesh_for(letter)
            for mat in materials:me.materials.append(mat)
            for mod in list(ob.modifiers):ob.modifiers.remove(mod)
            ob.data=me;ob['stone_crown_revision']='Ordered natural boulder v3; hand-built shoulders and inner crown; no top fan bevel'
            records.append({'object':ob.name,'vertices':len(me.vertices),'source_top_faces_downward':sum(p.normal.z<0 for p in me.polygons if p.center.z>.57),'modifiers':len(ob.modifiers)})
    assert len(records)==8
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    updates={r['id']:common.export(r,groups[r['id']],source) for r in rows}
    for r in rows:updates[r['id']]['baseline_sha256']=r['baseline_sha256']
    manifest['assets']=[updates.get(r['id'],r) for r in manifest['assets']];manifest['stone_reference_revision']='Ordered boulders v3, broad soft shoulders and shallow inner crown'
    assert all(common.digest(p)==s for p,s in unchanged.items())
    mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (common.OUT/'ordered_boulders_v3_report.json').write_text(json.dumps({'objects':records,'rollback':str(rollback),'unchanged_assets':unchanged,'visual':'pending','export_topology':'pending','traversal':'pending'},indent=2),encoding='utf-8')
    print('ORDERED_BOULDERS',[(r['id'],r['sha256']) for r in updates.values()],flush=True)

if __name__=='__main__':main()
