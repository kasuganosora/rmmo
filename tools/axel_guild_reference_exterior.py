"""U01/U19/U20 exterior details and U23 real dormer openings.

Call apply() on a COPY of the repair_v2 building mother, or apply_tower() on
the optimized tower mother. These functions never save or overwrite a file.
All dimensions hidden in the references are project supplementary design.
"""
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

REV = '20261013'


def _material(fragment):
    return next(m for m in bpy.data.materials if fragment.lower() in m.name.lower())


def _mesh(name, verts, faces, material, parent, collision=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.materials.append(material)
    data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data);bm.free();data.update()
    # New details using existing textured wood/iron require real UVs too.
    uv=data.uv_layers.new(name='ReferenceDetailMetres')
    for poly in data.polygons:
        axis=max(range(3),key=lambda k:abs(poly.normal[k]))
        projection=[k for k in range(3) if k!=axis]
        for li in poly.loop_indices:
            co=data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv=(co[projection[0]]/.8,co[projection[1]]/.8)
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob['semantic_group'] = parent.get('semantic_group', '12_Facade_Detail')
    ob['collision_review'] = collision
    ob['rmmo_collision'] = 'block' if collision else 'none'
    ob['whitebox_only'] = False
    ob['reference_revision'] = REV
    ob['reference_source'] = 'U01 U19 U20; hidden joinery is project design'
    ob['delivery_stage'] = 'textured_repair_v2'
    return ob


def _tube(name, points, radius, mat, parent, collision=False, sides=8):
    points = [Vector(p) for p in points]
    vertices = []
    for i, p in enumerate(points):
        tangent = points[min(i+1,len(points)-1)]-points[max(i-1,0)]
        tangent.normalize()
        normal = tangent.cross(Vector((0,1,0)))
        if normal.length < .01:
            normal = tangent.cross(Vector((0,0,1)))
        normal.normalize()
        other = tangent.cross(normal).normalized()
        vertices.extend(p+radius*(normal*math.cos(a)+other*math.sin(a))
                        for a in [math.tau*j/sides for j in range(sides)])
    faces = [tuple(reversed(range(sides))), tuple(range((len(points)-1)*sides,len(points)*sides))]
    for j in range(len(points)-1):
        for k in range(sides):
            faces.append((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k))
    ob = _mesh(name, vertices, faces, mat, parent, collision)
    for p in ob.data.polygons:
        p.use_smooth = len(p.vertices)==4
    return ob


def _plate(name, contour, y, depth, material, parent):
    n=len(contour)
    vertices=[(x, yy, z) for yy in [y-depth/2,y+depth/2] for x,z in contour]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces.extend((j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n))
    return _mesh(name,vertices,faces,material,parent)


def _door_details():
    iron = _material('Guild PBR | forged iron')
    wood = _material('Guild PBR | door oak')
    brass = bpy.data.materials.get('Guild reference aged door bronze')
    if brass is None:
        brass = bpy.data.materials.new('Guild reference aged door bronze')
        brass.use_nodes=True
        p=next(n for n in brass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        p.inputs['Base Color'].default_value=(.31,.205,.07,1)
        p.inputs['Metallic'].default_value=.8
        p.inputs['Roughness'].default_value=.42
    made=[]
    for side,sign in [('left',1),('right',-1)]:
        root=bpy.data.objects['Main door hinge '+side]
        # Leaf, actual hinge straps and handle retain their original transform.
        for ob in list(root.children):
            if ob.name.startswith('Main door diagonal board') or ob.get('reference_revision')==REV:
                bpy.data.objects.remove(ob,do_unlink=True)
        for face,y in [('outer',-.096),('inner',.076)]:
            # Continuous mirrored herringbone seams, clipped to each door leaf.
            # They are raised narrow oak battens instead of a new opaque leaf.
            for section,(lo,hi) in enumerate([(.22,1.56),(1.75,3.07)]):
                for k in range(5):
                    z=lo-.46+k*.33
                    for xa,xb,slope in [(.18,.785,.82),(.785,1.39,-.82)]:
                        za=z+(xa-.18)*.82 if xa<.7 else z+.605*.82
                        zb=za+(xb-xa)*slope
                        a,b=Vector((xa,za)),Vector((xb,zb))
                        if max(a.y,b.y)<lo or min(a.y,b.y)>hi:continue
                        if a.y<lo:a=a.lerp(b,(lo-a.y)/(b.y-a.y))
                        if b.y<lo:b=b.lerp(a,(lo-b.y)/(a.y-b.y))
                        if a.y>hi:a=a.lerp(b,(hi-a.y)/(b.y-a.y))
                        if b.y>hi:b=b.lerp(a,(hi-b.y)/(a.y-b.y))
                        made.append(_tube('Door reference chevron '+face,[(sign*a.x,y,a.y),(sign*b.x,y,b.y)],.014,wood,root,sides=6))
            # U20: diamond-ended forged horizontal bands and curved strapwork.
            for z,mat in [(2.48,brass),(1.30,iron),(.34,brass)]:
                made.append(_tube('Door reference strap '+face,[(sign*.10,y,z),(sign*1.45,y,z)],.025,mat,root,sides=6))
                for x in [.60,1.43]:
                    c=[(sign*(x-.13),z),(sign*x,z+.105),(sign*(x+.13),z),(sign*x,z-.105)]
                    made.append(_plate('Door reference diamond '+face,c,y,.020,mat,root))
                for direction in [-1,1]:
                    pts=[]
                    for j in range(25):
                        a=math.pi*j/24
                        arc_height=.12 if z<.5 else .27
                        pts.append((sign*(.76+.52*math.cos(a)),y,z+direction*arc_height*math.sin(a)))
                    made.append(_tube('Door reference curved iron '+face,pts,.015,iron,root,sides=6))
            # Small visible fasteners sit on the straps and travel with the door.
            for x in [.15,.40,1.06,1.30]:
                for z in [1.30,2.48]:
                    made.append(_tube('Door strap rivet '+face,[(sign*x,y-.012,z),(sign*x,y+.012,z)],.023,iron,root,sides=8))
        root['reference_revision']=REV
    return len(made)


def _balcony_and_finial():
    iron=_material('Guild PBR | forged iron')
    parent=bpy.data.objects['12_Facade_Detail']
    # This parent is an identity semantic grouping in the accepted mother.
    assert all(abs(parent.matrix_world[i][j]-(1 if i==j else 0))<1e-6 for i in range(4) for j in range(4))
    old=[o for o in bpy.data.objects if o.name.startswith(('Facade platform rail','Facade side rail','Central finial'))]
    for o in old:bpy.data.objects.remove(o,do_unlink=True)
    made=[]
    floor=4.48
    runs=[((13.2,-2.25),(18.8,-2.25),4),((13.2,-2.25),(13.2,-.15),2),((18.8,-2.25),(18.8,-.15),2)]
    for index,(a,b,sections) in enumerate(runs):
        va,vb=Vector((a[0],a[1],0)),Vector((b[0],b[1],0))
        length=(vb-va).length
        for z,r in [(floor+1.05,.030),(floor+.08,.018)]:
            made.append(_tube('Reference balcony continuous rail',[va+Vector((0,0,z)),vb+Vector((0,0,z))],r,iron,parent,True))
        count=math.ceil(length/.20)
        for j in range(count+1):
            p=va.lerp(vb,j/count)
            made.append(_tube('Reference balcony iron baluster',[p+Vector((0,0,floor+.08)),p+Vector((0,0,floor+1.05))],.017,iron,parent,True))
        for section in range(sections):
            pts=[]
            for j in range(25):
                t=(section+j/24)/sections;p=va.lerp(vb,t)
                # Shallow raised bow follows the clearly visible curved lower rail.
                pts.append(p+Vector((0,0,floor+.08+.20*math.sin(math.pi*j/24))))
            made.append(_tube('Reference balcony bowed lower band',pts,.019,iron,parent))
    for x in [13.2,18.8]:
        for y in [-2.25,-.15]:
            made.append(_tube('Reference balcony corner post',[(x,y,floor),(x,y,floor+1.20)],.032,iron,parent,True))
            made.append(_plate('Reference balcony pointed post',[(x-.065,floor+1.14),(x,floor+1.34),(x+.065,floor+1.14),(x,floor+1.05)],y,.045,iron,parent))
    # U01 silhouette: central diamond and forked curls, replacing the bare rod.
    x,y,z=16,-.48,13.70
    made.append(_tube('Reference central finial stem',[(x,y,z),(x,y,z+1.01)],.026,iron,parent))
    diamond=[(x,y,z+.51),(x+.15,y,z+.72),(x,y,z+.94),(x-.15,y,z+.72),(x,y,z+.51)]
    made.append(_tube('Reference central finial diamond',diamond,.024,iron,parent))
    for sign in [-1,1]:
        pts=[(x,y,z+.35),(x+sign*.18,y,z+.45),(x+sign*.32,y,z+.44),(x+sign*.42,y,z+.57),(x+sign*.46,y,z+.64)]
        made.append(_tube('Reference central finial fork scroll',pts,.022,iron,parent))
    return {'removed_original_parts':len(old),'new_metal_details':len(made),'balcony_plan_unchanged':True}


def repair_window_reveals(offset=.012):
    """Stone surrounds project into the opening instead of sharing wall faces.

    The accepted mother has exact coplanar wall/sill and wall/jamb reveals.
    Their competing materials change with batching. A 12mm stone lip on each
    short cross-section end resolves it without moving windows or changing UVs.
    """
    changed=[]
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH' or not ob.name.startswith(('Stone window sill','Stone window jamb')):
            continue
        if ob.get('window_reveal_revision')=='20261013_lip12mm':
            continue
        assert not ob.modifiers, (ob.name,'unexpected unapplied modifier')
        world=[ob.matrix_world@v.co for v in ob.data.vertices]
        lo=Vector(tuple(min(v[k] for v in world) for k in range(3)))
        hi=Vector(tuple(max(v[k] for v in world) for k in range(3)))
        axis=2 if ob.name.startswith('Stone window sill') else min((0,1),key=lambda k:hi[k]-lo[k])
        assert .09 < hi[axis]-lo[axis] < .25, (ob.name,list(hi-lo),axis)
        center=(lo[axis]+hi[axis])/2;inverse=ob.matrix_world.inverted()
        ob.data=ob.data.copy()
        for v,p in zip(ob.data.vertices,world):
            p[axis]+=offset if p[axis]>center else -offset
            v.co=inverse@p
        ob.data.update()
        ob['window_reveal_revision']='20261013_lip12mm'
        ob['project_design']='Stone opening surrounds overlap wall reveals by 12mm; prevents coplanar material conflict.'
        changed.append({'name':ob.name,'blender_axis':axis,'world_center':center,'offset_m':offset,'before_min':list(lo),'before_max':list(hi)})
    bpy.context.view_layer.update()
    return {'parts':changed,'part_count':len(changed),'project_supplement':'12mm proud stone opening lip; unchanged pane/fixture/collision roles'}


def apply():
    assert not any(o.name.startswith('Reference central finial stem') for o in bpy.data.objects), 'Already applied'
    result={'door_detail_meshes':_door_details(),'balcony_finial':_balcony_and_finial(),'window_reveals':repair_window_reveals(),
            'reference_sources':['U01','U19','U20'],'version':REV,
            'unseen_details':'Exact joinery, radii, fasteners and dimensions are project supplementary design.'}
    bpy.context.view_layer.update()
    return result


def apply_tower():
    """Extend the existing 8 opening cuts through all 3 retained roof LODs.

    The old r=2.25 cutter stops inside the tapered inner shell at z=6.2–6.4,
    leaving a red-brick triangle across the upper window. New cutters extend
    inward to r=1.7, without touching the lip, cheeks or any other components.
    """
    roofs=[o for o in bpy.data.objects if o.type=='MESH' and o.get('source_part')=='guild_alarm_conical_roof' and 'lod_level' in o]
    assert len(roofs)==3, f'Expected 3 optimized roof LODs, found {len(roofs)}'
    bpy.context.view_layer.update()
    results=[]
    for roof in roofs:
        roof.hide_set(False);roof.hide_render=False
        roof.data=roof.data.copy()
        original_tags={k:repr(v.to_dict() if hasattr(v,'to_dict') else v) for k,v in roof.items()}
        original_materials=[m.name if m else '' for m in roof.data.materials]
        before=sum(len(p.vertices)-2 for p in roof.data.polygons)
        # Open dormer cheeks and closed mouldings are separate islands inside
        # the optimized mesh. A boolean on that entire disconnected mixture
        # creates spurious front caps. Operate on the closed cone island only.
        adjacency=[set() for _ in roof.data.vertices]
        for edge in roof.data.edges:
            a,b=edge.vertices;adjacency[a].add(b);adjacency[b].add(a)
        seed=next(v.index for v in roof.data.vertices if abs(v.co.z-4.62)<.001 and math.hypot(v.co.x,v.co.y)>3.65)
        shell_indices=set();todo=[seed]
        while todo:
            index=todo.pop()
            if index in shell_indices:continue
            shell_indices.add(index);todo.extend(adjacency[index]-shell_indices)
        shell_data=roof.data.copy()
        bm=bmesh.new();bm.from_mesh(shell_data);bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in shell_indices],context='VERTS')
        bm.to_mesh(shell_data);bm.free()
        shell=bpy.data.objects.new('Isolated conical roof shell repair',shell_data)
        bpy.context.scene.collection.objects.link(shell);shell.matrix_world=roof.matrix_world.copy()
        bm=bmesh.new();bm.from_mesh(roof.data);bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index in shell_indices],context='VERTS')
        bm.to_mesh(roof.data);bm.free()
        for i in range(8):
            a=math.tau*i/8;c,s=math.cos(a),math.sin(a)
            # Match the existing opening contour; depth is the sole alteration.
            tri=[(-.36,5.60),(.36,5.60),(0,6.42)]
            verts=[(r*c-t*s,r*s+t*c,z) for r in [1.70,3.45] for t,z in tri]
            data=bpy.data.meshes.new('Temporary extended dormer cutter')
            data.from_pydata(verts,[],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
            cutter=bpy.data.objects.new('Temporary extended dormer cutter',data)
            bpy.context.scene.collection.objects.link(cutter)
            cutter.matrix_world=roof.matrix_world.copy()
            bpy.context.view_layer.update()
            bpy.ops.object.select_all(action='DESELECT');shell.select_set(True);bpy.context.view_layer.objects.active=shell
            mod=shell.modifiers.new('Complete dormer depth','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cutter,do_unlink=True)
            if data.users==0:bpy.data.meshes.remove(data)
        bpy.ops.object.select_all(action='DESELECT');roof.select_set(True);shell.select_set(True);bpy.context.view_layer.objects.active=roof
        bpy.ops.object.join()
        # Keep repaired 5 cm bound margin when input is the earlier game mother.
        ranges=roof.get('rmmo_visibility_range')
        if ranges and ranges['bounds'][4]<33.42-1e-5:ranges['bounds'][4]=33.42
        assert original_materials==[m.name if m else '' for m in roof.data.materials]
        for key,value in original_tags.items():
            if key=='rmmo_visibility_range':continue
            current=roof[key]
            assert value==repr(current.to_dict() if hasattr(current,'to_dict') else current),key
        bpy.context.view_layer.update()
        ray_count=0
        for i in range(8):
            a=math.tau*i/8;c,s=math.cos(a),math.sin(a)
            for z in [5.8,6.0,6.2,6.35]:
                clear=not roof.ray_cast((4*c,4*s,z),(-c,-s,0),distance=3.8)[0]
                assert clear,(roof.name,'still blocked triangle',i,z)
                ray_count+=1
        roof['reference_revision']=REV
        results.append({'object':roof.name,'lod':int(roof['lod_level']),'triangles_before':before,'triangles_after':sum(len(p.vertices)-2 for p in roof.data.polygons),'openings':8,'clear_opening_rays':ray_count})
    # All tower parts must share the already delivered conservative AABB.
    for ob in bpy.data.objects:
        ranges=ob.get('rmmo_visibility_range')
        if ranges and len(ranges['bounds'])==6 and ranges['bounds'][4]<33.42-1e-5:ranges['bounds'][4]=33.42
    bpy.context.view_layer.update()
    return {'roofs':results,'reference':'U23','fix':'Existing triangle cuts now penetrate complete tapered shell depth','version':REV}
