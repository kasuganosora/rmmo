"""Keep 400 mm wall plates inside the 500 mm masonry bearing width."""


def fit_roof_wall_plates(objects):
    """Narrow bearing, then scribe any exposed edge to the evaluated roof skin."""
    import bpy
    from mathutils import Vector
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    roofs=[o.evaluated_get(deps) for o in objects if o.name in ('Main front roof','Main back roof')]
    changed = []
    for o in objects:
        if o.type != 'MESH' or not o.name.startswith('Roof wall plate'): continue
        world = o.matrix_world.copy()
        inverse = world.inverted()
        points = [world @ v.co for v in o.data.vertices]
        lo, hi = min(p.y for p in points), max(p.y for p in points)
        center = (lo+hi)/2
        old_width = hi-lo
        if abs(old_width-.4) < .0001: continue
        assert abs(old_width-.6) < .001, (o.name, old_width)
        zlo,zhi=min(p.z for p in points),max(p.z for p in points)
        bevelled=0
        for vertex, p in zip(o.data.vertices, points):
            p.y = center+(p.y-center)*(.4/old_width)
            tops=[]
            for roof in roofs:
                inv=roof.matrix_world.inverted()
                hit,r,n,i=roof.ray_cast(inv@Vector((p.x,p.y,16)),(inv.to_3x3()@Vector((0,0,-1))).normalized(),distance=20)
                if hit:tops.append((roof.matrix_world@r).z)
            assert tops, (o.name,list(p))
            cap=min(zhi,max(tops)-.04)
            # Preserve at least 100 mm timber at the scribed outer edge. Any
            # lower seat is enclosed by the existing masonry, never a hole.
            new_z=cap if p.z>(zlo+zhi)/2 else min(zlo,cap-.10)
            if abs(new_z-p.z)>.0001:bevelled+=1
            p.z=new_z
            vertex.co = inverse @ p
        o.data.update()
        changed.append({'object': o.name, 'old_width_m': old_width, 'new_width_m': .4,
                        'center_y': center, 'wall_bearing_margin_m': .05, 'scribed_vertices':bevelled})
    # End-gable top faces were coplanar with the rear roof skin. Preserve the
    # horizontal z=8.2 base joint; inset its rear endpoint instead of lowering
    # the entire triangle (which would overlap the storey wall below).
    for o in objects:
        if o.type!='MESH' or not o.name.startswith('End roof gable'):continue
        world=o.matrix_world.copy();inverse=world.inverted();edits=0
        for vertex in o.data.vertices:
            p=world@vertex.co
            if abs(p.y-7)<.001 and abs(p.z-14)<.001:
                p.z-=.02;edits+=1
            elif abs(p.y-14)<.001 and abs(p.z-8.2)<.001:
                p.y-=.02/(5.8/7);edits+=1
            vertex.co=inverse@p
        if edits:
            o.data.update()
            changed.append({'object':o.name,'profile_vertices':edits,'rear_skin_clearance_m':.02,
                            'base_joint_z_unchanged':8.2})
    return {'correction': '600 mm wall plates narrowed to 400 mm; outer edges scribed 40 mm below actual roof skin',
            'changed': changed}


if __name__ == '__main__':
    import bpy
    import hashlib
    import json
    from pathlib import Path
    from mathutils import Vector
    base = Path('D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v12')
    out = Path('D:/code/rmmo/review_artifacts/axel_guild_materials_20261011')
    bpy.ops.wm.open_mainfile(filepath=str(base/'axel_guild_whitebox.blend'))
    def fingerprint(o):
        return repr((o.parent.name if o.parent else None, [list(r) for r in o.matrix_world],
                     [list(v.co) for v in o.data.vertices] if o.type=='MESH' else [],
                     [list(p.vertices) for p in o.data.polygons] if o.type=='MESH' else []))
    before = {o.name:fingerprint(o) for o in bpy.data.objects}
    report = fit_roof_wall_plates(bpy.data.objects)
    allowed = {row['object'] for row in report['changed']}
    unexpected = [o.name for o in bpy.data.objects if o.name not in allowed and fingerprint(o)!=before[o.name]]
    assert not unexpected, unexpected
    assert len(allowed) == 9
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    roofs = [o.evaluated_get(deps) for o in bpy.data.objects if o.name in ('Main front roof','Main back roof')]
    samples = []
    for row in report['changed']:
        if not row['object'].startswith('Roof wall plate'):continue
        o = bpy.data.objects[row['object']]
        points = [o.matrix_world@v.co for v in o.data.vertices]
        xmin,xmax = min(p.x for p in points),max(p.x for p in points)
        ymin,ymax = min(p.y for p in points),max(p.y for p in points)
        plate=o.evaluated_get(deps)
        pinv=plate.matrix_world.inverted()
        for ix in range(11):
            for y in [ymin, ymax]:
                x = xmin+(xmax-xmin)*ix/10
                tops=[]
                for roof in roofs:
                    inv=roof.matrix_world.inverted()
                    hit,p,normal,index=roof.ray_cast(inv@Vector((x,y,16)),(inv.to_3x3()@Vector((0,0,-1))).normalized(),distance=20)
                    if hit: tops.append((roof.matrix_world@p).z)
                assert tops, ('Uncovered plate', o.name,x,y)
                hit,p,n,i=plate.ray_cast(pinv@Vector((x,y,16)),(pinv.to_3x3()@Vector((0,0,-1))).normalized(),distance=20)
                # Move sub-micron inward at mesh edges to avoid boundary ambiguity.
                if not hit:
                    xx=min(xmax-.00001,max(xmin+.00001,x));yy=min(ymax-.00001,max(ymin+.00001,y))
                    hit,p,n,i=plate.ray_cast(pinv@Vector((xx,yy,16)),(pinv.to_3x3()@Vector((0,0,-1))).normalized(),distance=20)
                assert hit, ('Plate sample missed',o.name,x,y)
                gap=max(tops)-(plate.matrix_world@p).z
                samples.append({'plate':o.name,'x':x,'y':y,'tile_surface_clearance_m':gap})
    report.update({'passed': all(r['tile_surface_clearance_m'] > .03 for r in samples) and not unexpected,
                   'roof_cover_samples': len(samples), 'samples': samples,
                   'minimum_tile_surface_clearance_m': min(r['tile_surface_clearance_m'] for r in samples),
                   'unexpected_changes': unexpected,
                   'source_sha256': hashlib.sha256((base/'axel_guild_whitebox.blend').read_bytes()).hexdigest(),
                   'source_preserved': True, 'wall_bodies_roofs_floors_ceiling_stairs_doors_unchanged': True,
                   'end_gable_base_joints_unchanged':True,'end_gable_profile_clearance_m':.02})
    rear_roof=next(r for r in roofs if r.name=='Main back roof')
    rinv=rear_roof.matrix_world.inverted()
    gable_samples=[]
    for o in bpy.data.objects:
        if o.type!='MESH' or not o.name.startswith('End roof gable'):continue
        points=[o.matrix_world@v.co for v in o.data.vertices]
        ymax=max(p.y for p in points);peak=max(p.z for p in points)
        for x in [min(p.x for p in points),max(p.x for p in points)]:
            for i in range(11):
                t=i/10;y=7+(ymax-7)*t;z=peak+(8.2-peak)*t
                hit,p,n,index=rear_roof.ray_cast(rinv@Vector((x,y,16)),(rinv.to_3x3()@Vector((0,0,-1))).normalized(),distance=20)
                assert hit
                gable_samples.append((rear_roof.matrix_world@p).z-z)
    assert len(gable_samples)==44 and min(gable_samples)>.018
    report['gable_profile_samples']=44
    report['minimum_gable_skin_clearance_m']=min(gable_samples)
    assert report['passed'], report
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'axel_guild_whitebox_v13.blend'), compress=True)
    (out/'roof_wall_joinery_review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('ROOF_WALL_PLATE_FIT', len(allowed), 'objects;', len(samples), 'samples;', report['passed'], flush=True)
