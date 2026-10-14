"""Reference corrections for the current guild master; caller owns saving/export.

U09/U16 show the recruitment board hung on the timber return.  The earlier
freestanding feet were authored support, not visible reference.  Work on mesh
islands because the delivered master joins each prop's original small pieces.
"""
import bpy
import bmesh
import math
from mathutils import Vector


def _islands(bm):
    pending = set(bm.verts)
    while pending:
        first = pending.pop()
        island = {first}
        stack = [first]
        while stack:
            for edge in stack.pop().link_edges:
                for vertex in edge.verts:
                    if vertex in pending:
                        pending.remove(vertex)
                        island.add(vertex)
                        stack.append(vertex)
        yield island


def _box(root, name, center, size, material):
    dx, dy, dz = [v / 2 for v in size]
    cx, cy, cz = center
    verts = [(cx+x, cy+y, cz+z) for x, y, z in
             [(-dx,-dy,-dz), (dx,-dy,-dz), (dx,dy,-dz), (-dx,dy,-dz),
              (-dx,-dy,dz), (dx,-dy,dz), (dx,dy,dz), (-dx,dy,dz)]]
    faces = [(0,3,2,1), (4,5,6,7), (0,1,5,4), (1,2,6,5),
             (2,3,7,6), (3,0,4,7)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        normal = poly.normal
        axis = max(range(3), key=lambda k: abs(normal[k]))
        axes = [k for k in range(3) if k != axis]
        for loop_index in poly.loop_indices:
            v = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (v[axes[0]], v[axes[1]])
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    root.users_collection[0].objects.link(obj)
    obj.parent = root
    obj['independent_prop'] = True
    obj['structural_wall'] = False
    obj['collision_review'] = False
    obj['rmmo_collision'] = 'none'
    obj['semantic_group'] = root.get('semantic_group', '42_Independent_Props')
    obj['reference_status'] = 'Project supplemental wall attachment for U09/U16'
    obj['prop_part'] = name
    obj['replaceable_group'] = 'wall_mount'
    obj['reference_correction'] = 'quest_board_wall_mount_v1'
    bevel = obj.modifiers.new('Small forged edge', 'BEVEL')
    bevel.width = .002
    bevel.segments = 2
    return obj


def _metal():
    name = 'Quest board concealed forged wall mount'
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (.085, .068, .050, 1)
    bsdf.inputs['Metallic'].default_value = .8
    bsdf.inputs['Roughness'].default_value = .48
    mat.diffuse_color = (.085, .068, .050, 1)
    return mat


def _crystal_reference_details():
    """Replace only ring hardware/crown; preserve globe, supports and pedestal."""
    from axel_guild_furnishings import Geometry
    reports = []
    roots = [o for o in bpy.context.scene.objects
             if o.get('asset_id') == 'guild_registration_crystal']
    for root in roots:
        if root.get('reference_ring_revision') == 1:
            reports.append({'root': root.name, 'already_applied': True})
            continue
        children = list(root.children_recursive)
        def material(prefix):
            choices = [m for o in children if o.type == 'MESH' for m in o.data.materials
                       if m and m.name.startswith(prefix)]
            if not choices:
                raise RuntimeError(f'{root.name}: missing current material {prefix}')
            return choices[0]
        mats = {'steel': material('Guild worn pewter iron'),
                'brass': material('Guild aged brass'),
                'dark': material('Guild violet black hard support')}
        removed = []
        keep = []
        for obj in children:
            if (obj.get('replaceable_group') in ('ring_frames', 'ring_hardware', 'gold_ornaments')
                    or obj.get('prop_part') == 'Handwheel_spoke'):
                removed.append(obj.name)
                bpy.data.objects.remove(obj, do_unlink=True)
            elif obj.type == 'MESH':
                keep.append({'name': obj.name, 'vertices': len(obj.data.vertices),
                             'polygons': len(obj.data.polygons)})
        g = Geometry('registration_crystal', root.users_collection[0], mats,
                     'game', root.name + '_reference_hardware')
        temporary_root = g.root
        g.root = root
        bpy.data.objects.remove(temporary_root, do_unlink=True)

        # Gray upper bearing plate: broad, scalloped around six projecting axles.
        # A real annular plate with twelve through holes, not painted dots.
        n = 192
        z, thick = .667, .017
        verts = []
        for zz in (z-thick/2, z+thick/2):
            for outer in (False, True):
                for i in range(n):
                    a = i * math.tau / n
                    radius = .223 if not outer else .272 + .040 * ((1+math.cos(6*a))/2)**6
                    verts.append((radius*math.cos(a), radius*math.sin(a), zz))
        faces = []
        for i in range(n):
            j = (i+1) % n
            faces.extend([(i,j,n+j,n+i), (2*n+i,3*n+i,3*n+j,2*n+j),
                          (i,2*n+i,2*n+j,j), (n+i,n+j,3*n+j,3*n+i)])
        plate = g.mesh('Reference scalloped perforated steel bearing plate',
                       verts, faces, 'steel', group='ring_frames')
        for i in range(12):
            a = (i+.5) * math.tau / 12
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=.008,
                depth=.06, location=(.249*math.cos(a), .249*math.sin(a), z))
            cutter = bpy.context.object
            cutter.name = 'Temporary crystal bearing plate drill'
            cutter.parent = root
            cutter.matrix_parent_inverse.identity()
            # primitive_add location is local now because parent inverse is identity.
            bpy.context.view_layer.update()
            modifier = plate.modifiers.new('True drilled aperture', 'BOOLEAN')
            modifier.operation = 'DIFFERENCE'
            modifier.solver = 'EXACT'
            modifier.object = cutter
            bpy.context.view_layer.objects.active = plate
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            bpy.data.objects.remove(cutter, do_unlink=True)
        bevel = plate.modifiers.new('Machined bearing edges', 'BEVEL')
        bevel.width = .0012
        bevel.segments = 2
        # Keep the lower collar and two brass courses separate, as in U10/U11.
        g.ring('Reference lower steel globe collar', .235, .510, .027, .026,
               'steel', group='ring_frames')
        g.ring('Reference middle brass orbital band', .253, .565, .014, .014,
               'brass', group='ring_frames')
        g.ring('Reference crown base band', .221, .723, .008, .010,
               'brass', group='ring_frames')

        for i in range(6):
            a = i * math.tau / 6
            x, y = .310*math.cos(a), .310*math.sin(a)
            g.lathe(f'Reference outboard axle {i}',
                    [(0,.546),(.011,.546),(.012,.680),(0,.680)],
                    'brass', (x,y,0), n=20, group='ring_hardware')
            g.ring(f'Reference spoke handwheel rim {i}', .037, .620, .005, .006,
                   'brass', (x,y,0), 'ring_hardware')
            g.lathe(f'Reference wheel hub {i}',
                    [(0,.606),(.017,.606),(.017,.631),(0,.631)],
                    'brass', (x,y,0), n=24, group='ring_hardware')
            for j in range(6):
                b = j*math.tau/6
                spoke = g.beam(f'Reference handwheel spoke {i}_{j}',
                    (x+.016*math.cos(b),y+.016*math.sin(b),.620),
                    (x+.034*math.cos(b),y+.034*math.sin(b),.620),
                    .0035,'brass',.0005)
                spoke['replaceable_group'] = 'ring_hardware'
            g.lathe(f'Reference upper axle washer {i}',
                    [(0,.678),(.018,.678),(.018,.684),(0,.684)],
                    'steel', (x,y,0), n=24, group='ring_hardware')
            g.lathe(f'Reference brass screw head {i}',
                    [(0,.684),(.010,.684),(.010,.691),(0,.691)],
                    'brass', (x,y,0), n=16, group='ring_hardware')
            g.box(f'Reference screw slot {i}', (x,y,.6912),
                  (.014,.002,.001),'dark',.0002,'ring_hardware')
            # Tangential load transfer from lower ring to the outboard axle.
            connection = g.beam(f'Reference lower radial arm {i}',
                (.249*math.cos(a),.249*math.sin(a),.565),
                (x,y,.565), .014, 'brass', .001)
            connection['replaceable_group'] = 'ring_hardware'

        def cubic(a, b, c, d, steps=10):
            result = []
            for i in range(steps):
                t = i/steps
                result.append(tuple((1-t)**3*a[k] + 3*(1-t)**2*t*b[k] +
                                    3*(1-t)*t*t*c[k] + t**3*d[k] for k in (0,1)))
            return result
        # Concave rising wings and rolled lower ends: U10's characteristic
        # flared gold fins, replacing straight tiny triangles.
        segments = [
            ((-.072,.008),(-.046,.008),(-.022,.018),(0,.085)),
            ((0,.085),(.011,.040),(.025,.015),(.063,.009)),
            ((.063,.009),(.094,.006),(.065,-.013),(.042,-.001)),
            ((.042,-.001),(.026,.008),(.016,.003),(0,.000)),
            ((0,.000),(-.015,-.001),(-.032,.006),(-.052,-.003)),
            ((-.052,-.003),(-.077,-.014),(-.091,.008),(-.072,.008))]
        outline = [point for segment in segments for point in cubic(*segment)]
        for i in range(4):
            a = math.pi/4 + i*math.pi/2
            obj = g.extrude(f'Reference flared curved gold crown {i}',
                [(x,.721+h) for x,h in outline], -.227, -.217,
                'brass', .0015, 'gold_ornaments')
            obj.rotation_euler.z = a
            # Shallow raised central ridge catches light on the curved plate.
            ridge = g.tube(f'Reference gold fin ridge {i}',
                [(0,-.230,.725),(-.002,-.230,.744),(0,-.227,.779),(0,-.225,.803)],
                .0017, 'brass', group='gold_ornaments')
            ridge.rotation_euler.z = a
        for obj in g.parts:
            obj['semantic_group'] = root.get('semantic_group', '42_Independent_Props')
            obj['whitebox_only'] = False
            obj['reference_status'] = 'U10/U11 silhouette; hidden construction and dimensions project supplementation'
            obj['reference_correction'] = 'registration_crystal_ring_v1'
            obj['collision_review'] = False
            obj['rmmo_collision'] = 'none'
        root['reference_ring_revision'] = 1
        root['ring_plate_through_holes'] = 12
        root['reference_hardware_detail'] = 'wide scalloped steel plate; 6 outboard spoke wheels; 4 curved gold fins'
        reports.append({'root': root.name, 'removed_objects': removed,
                        'preserved_objects': keep,
                        'added_objects': [o.name for o in g.parts],
                        'through_hole_count': 12,
                        'source_materials': {k:v.name for k,v in mats.items()},
                        'sphere_supports_base_touch_point_unchanged': True})
    return reports


def _chair_front_rope_legs():
    """U15 visibly turns the front legs; unseen rear construction stays intact."""
    from axel_guild_furnishings import Geometry
    reports = []
    for root in [o for o in bpy.context.scene.objects if o.get('asset_id') == 'guild_guest_chair']:
        if root.get('reference_front_leg_revision') == 1:
            reports.append({'root': root.name, 'already_applied': True})
            continue
        inv = root.matrix_world.inverted()
        removed = []
        wood = None
        for obj in list(root.children_recursive):
            if obj.type != 'MESH':
                continue
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            transform = inv @ obj.matrix_world
            discard = set()
            for island in _islands(bm):
                coords = [transform @ v.co for v in island]
                lo = Vector(tuple(min(v[k] for v in coords) for k in range(3)))
                hi = Vector(tuple(max(v[k] for v in coords) for k in range(3)))
                center = (lo + hi) * .5
                if (lo.z < .06 and .43 < hi.z < .51 and hi.z-lo.z > .40
                        and -.30 < lo.y < -.20 and hi.y < -.17
                        and .18 < abs(center.x) < .30 and hi.x-lo.x < .10):
                    discard.update(island)
                    one_face = next(iter(next(iter(island)).link_faces))
                    wood = obj.data.materials[one_face.material_index]
                    removed.append({'object': obj.name, 'vertices': len(island),
                                    'local_min': list(lo), 'local_max': list(hi)})
            if discard:
                obj.data = obj.data.copy()
                bmesh.ops.delete(bm, geom=list(discard), context='VERTS')
                bm.to_mesh(obj.data)
                obj.data.update()
            bm.free()
        if len(removed) != 2 or wood is None:
            raise RuntimeError(f'{root.name}: expected two front legs, found {len(removed)}')
        g = Geometry('registration_crystal', root.users_collection[0], {'wood': wood},
                     'game', root.name + '_reference_front_legs')
        temporary_root = g.root
        g.root = root
        bpy.data.objects.remove(temporary_root, do_unlink=True)
        # The original builder finishes the prop by shifting its lowest point
        # to zero. Derive that small offset from the actual retained master.
        offset_z = (removed[0]['local_min'][2]+removed[0]['local_max'][2])*.5 - (.035+.48)*.5
        for side in (-1, 1):
            foot = Vector((side*.23*1.12, -.22*1.12, .035+offset_z))
            top = Vector((side*.23, -.22, .48+offset_z))
            direction = (top-foot).normalized()
            axis = direction.cross(Vector((0,1,0))).normalized()
            other = direction.cross(axis).normalized()
            radial, axial = 16, 40
            vertices = []
            for j in range(axial+1):
                t = j/axial
                center = foot.lerp(top, t)
                # Smooth collars join the carved shaft to seat and floor.
                envelope = min(1.0, max(0.0,(t-.08)/.08), max(0.0,(.91-t)/.08))
                for k in range(radial):
                    a = k*math.tau/radial
                    radius = .023 + .003*envelope*math.cos(3*(a-2*math.tau*t))
                    radius *= .96 + .04*t
                    vertices.append(tuple(center+radius*(axis*math.cos(a)+other*math.sin(a))))
            faces = []
            for j in range(axial):
                for k in range(radial):
                    q = (k+1)%radial
                    faces.append((j*radial+k,j*radial+q,(j+1)*radial+q,(j+1)*radial+k))
            faces.extend([tuple(reversed(range(radial))),
                          tuple(axial*radial+k for k in range(radial))])
            obj = g.mesh('U15 rope turned front leg '+('left' if side<0 else 'right'),
                         vertices, faces, 'wood', group='static', smooth=True)
            obj.data.polygons[-1].use_smooth = False
            obj.data.polygons[-2].use_smooth = False
            obj['semantic_group'] = root.get('semantic_group','32_Furniture_L1')
            obj['whitebox_only'] = False
            obj['reference_status'] = 'U15 front-leg rope turning; metric section is project supplementation'
            obj['reference_correction'] = 'guest_chair_front_rope_legs_v1'
            obj['collision_review'] = True
            obj['rmmo_collision'] = 'block'
        root['reference_front_leg_revision'] = 1
        reports.append({'root':root.name,'removed_front_legs':removed,
                        'added_front_legs':[o.name for o in g.parts],
                        'seat_height_root_transform_rear_legs_unchanged':True,
                        'radial_segments':16,'axial_segments':40})
    return reports


def apply():
    """Correct current master in memory, returning explicit mutation evidence.

    Board front, placement, paper slots, inscription and brass stay unchanged.
    Mount length matches the current board-to-return gap; dimensions are project
    supplementation and are not represented as animation measurements.
    """
    report = {'reference_ids': ['U09', 'U16'], 'quest_boards': []}
    roots = [o for o in bpy.context.scene.objects
             if o.get('asset_id') in ('guild_quest_board_filled', 'guild_quest_board_blank')]
    for root in roots:
        if root.get('reference_mount_revision') == 1:
            report['quest_boards'].append({'root': root.name, 'already_applied': True})
            continue
        world_before = [list(row) for row in root.matrix_world]
        inv = root.matrix_world.inverted()
        removed = []
        retained_vertices = 0
        for obj in list(root.children_recursive):
            if obj.type != 'MESH':
                continue
            # Single-user copy avoids touching a standalone or another instance.
            obj.data = obj.data.copy()
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            transform = inv @ obj.matrix_world
            discard = set()
            for island in _islands(bm):
                coords = [transform @ v.co for v in island]
                lo = Vector(tuple(min(v[k] for v in coords) for k in range(3)))
                hi = Vector(tuple(max(v[k] for v in coords) for k in range(3)))
                middle = (lo + hi) * .5
                # Only the three original foot/post/brace islands at each side.
                # A board/frame/paper island extends higher or has no low feet.
                if (hi.z < 1.72 and lo.z < .74 and
                        1.15 < abs(middle.x) < 1.65 and hi.x-lo.x < .34 and
                        lo.y > -.23 and hi.y < .39):
                    discard.update(island)
                    removed.append({'object': obj.name, 'vertex_count': len(island),
                                    'local_min': list(lo), 'local_max': list(hi)})
            bmesh.ops.delete(bm, geom=list(discard), context='VERTS')
            retained_vertices += len(bm.verts)
            bm.to_mesh(obj.data)
            bm.free()
            obj.data.update()
            if not obj.data.vertices:
                bpy.data.objects.remove(obj, do_unlink=True)
        # Each side has a post, a foot and a diagonal. Fail rather than silently
        # leaving an unsupported or partially corrected variant in the export.
        if len(removed) != 6:
            raise RuntimeError(f'{root.name}: expected six support islands, found {len(removed)}')
        mat = _metal()
        added = []
        for z in (1.05, 2.95):
            added.append(_box(root, f'Quest rear hanging rail {z:.2f}',
                              (0, .088, z), (2.98, .045, .08), mat).name)
            for side, x in (('left', -1.43), ('right', 1.43)):
                added.append(_box(root, f'Quest board backplate {side} {z:.2f}',
                                  (x, .087, z), (.13, .050, .16), mat).name)
                added.append(_box(root, f'Quest wall bridging arm {side} {z:.2f}',
                                  (x, .226, z), (.070, .28, .05), mat).name)
                added.append(_box(root, f'Quest wall fixed plate {side} {z:.2f}',
                                  (x, .36, z), (.15, .03, .21), mat).name)
        root['rear_support_is_authored'] = False
        root['mounting_mode'] = 'wall_hung'
        root['reference_mount_revision'] = 1
        root['mounting_reference'] = 'U09/U16; concealed fixing is project supplemental design'
        root['wall_mount_back_depth_m'] = .375
        root['mounting_anchor_points_local'] = [-1.43,.36,1.05, 1.43,.36,1.05,
                                               -1.43,.36,2.95, 1.43,.36,2.95]
        bpy.context.view_layer.update()
        assert world_before == [list(row) for row in root.matrix_world]
        report['quest_boards'].append({'root': root.name, 'removed_support_islands': removed,
                                     'retained_vertex_count': retained_vertices,
                                     'added_mount_parts': added, 'placement_unchanged': True,
                                     'mounting_mode': 'wall_hung'})
    if not roots:
        raise RuntimeError('No guild quest board root found in current master')
    report['registration_crystals'] = _crystal_reference_details()
    report['guest_chairs'] = _chair_front_rope_legs()
    return report
