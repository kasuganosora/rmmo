"""Project-designed, genuinely open and splayed arrow loops for the alarm shaft.

Dimensions are gameplay/art choices, not measurements of anime or a monument.
The shaft's original outer cylinder, transform and semantic identity are retained.
"""
import math
import bpy
import bmesh
from mathutils import Vector

LEVELS = (5.2, 10.0, 14.8, 19.6)


def install_shooting_slits(shaft):
    if shaft.get('shooting_slits_version') == 1:
        return {'count': 16, 'already_installed': True}
    bpy.context.view_layer.update()
    shaft.data = shaft.data.copy()
    centre = shaft.matrix_world.translation.copy()
    inv = shaft.matrix_world.inverted()
    base = min((shaft.matrix_world @ v.co).z for v in shaft.data.vertices)
    collection = shaft.users_collection[0]

    def subtract(cutter, name):
        bpy.ops.object.select_all(action='DESELECT')
        shaft.hide_set(False)
        shaft.select_set(True)
        bpy.context.view_layer.objects.active = shaft
        mod = shaft.modifiers.new(name, 'BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.solver = 'EXACT'
        mod.object = cutter
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)

    # Enclosed inner void: retain a 200 mm base and top closure. This is a wall
    # shell for real openings, not a completed navigable tower interior.
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=2.0, depth=23.6,
        location=(centre.x, centre.y, base + 12))
    subtract(bpy.context.object, 'Inner shaft void')
    layout = []
    for tier, height in enumerate(LEVELS):
        for slot in range(4):
            angle = math.radians(slot * 90 - 45 + (tier % 2) * 45)
            outward = Vector((math.cos(angle), math.sin(angle), 0))
            tangent = Vector((-outward.y, outward.x, 0))
            origin = Vector((centre.x, centre.y, base + height))
            # Inner splay, narrow throat and lightly chamfered exterior mouth.
            sections = [(1.82, .94, 1.80), (2.46, .22, 1.30),
                        (2.56, .32, 1.40), (2.90, .32, 1.40)]
            verts = []
            for radius, width, aperture_height in sections:
                for side, up in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                    verts.append(tuple(origin + outward * radius + tangent * side * width / 2
                                       + Vector((0, 0, up * aperture_height / 2))))
            faces = [(3,2,1,0), (12,13,14,15)]
            for ring in range(3):
                for i in range(4):
                    j = (i + 1) % 4
                    faces.append((ring*4+i, ring*4+j, (ring+1)*4+j, (ring+1)*4+i))
            mesh = bpy.data.meshes.new('Temporary embrasure cutter')
            mesh.from_pydata(verts, [], faces)
            bm = bmesh.new(); bm.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(mesh); bm.free()
            cutter = bpy.data.objects.new('Temporary embrasure cutter', mesh)
            collection.objects.link(cutter)
            subtract(cutter, 'Open shooting slit %d %d' % (tier + 1, slot + 1))
            layout.append({'tier':tier+1, 'azimuth_degrees':math.degrees(angle),
                           'centre_height_m':height})
    shaft.data.update()
    # Keep the circular exterior smooth, but retain crisp internal reveals.
    normal_matrix = shaft.matrix_world.to_3x3().inverted().transposed()
    for polygon in shaft.data.polygons:
        n = (normal_matrix @ polygon.normal).normalized()
        radii = [math.hypot((shaft.matrix_world @ shaft.data.vertices[i].co).x-centre.x,
                            (shaft.matrix_world @ shaft.data.vertices[i].co).y-centre.y)
                 for i in polygon.vertices]
        polygon.use_smooth = abs(n.z) < .01 and (min(radii) > 2.52 or max(radii) < 2.01)
    bm = bmesh.new(); bm.from_mesh(shaft.data)
    non_manifold = sum(not e.is_manifold for e in bm.edges)
    bm.free()
    assert non_manifold == 0, ('non-manifold arrow slit geometry', non_manifold)

    # Probe the actual geometry through each opening and its adjacent solid wall.
    probes = []
    for item in layout:
        angle = math.radians(item['azimuth_degrees'])
        radial = Vector((math.cos(angle),math.sin(angle),0))
        tangent = Vector((-radial.y, radial.x, 0))
        origin = Vector((centre.x,centre.y,base+item['centre_height_m']))
        direction = (inv.to_3x3() @ -radial).normalized()
        clear = not shaft.ray_cast(inv @ (origin+radial*3), direction, distance=1.2)[0]
        side_solid = shaft.ray_cast(inv @ (origin+radial*3+tangent*.45), direction, distance=1.2)[0]
        assert clear and side_solid, ('blocked slit or missing adjacent wall', item)
        probes.append({'tier':item['tier'], 'azimuth_degrees':item['azimuth_degrees'],
                       'open_to_inner_void':clear, 'adjacent_wall_solid':side_solid})
    shaft['shooting_slits_version'] = 1
    shaft['shooting_slit_count'] = 16
    shaft['shooting_slit_levels_m'] = list(LEVELS)
    shaft['project_supplementary_design'] = True
    shaft['interior_traversal_complete'] = False
    return {'count':16, 'levels_m':list(LEVELS), 'layout':layout, 'probes':probes,
            'non_manifold_edges':non_manifold, 'nominal_wall_thickness_m':.55,
            'throat_width_m':.22, 'throat_height_m':1.30,
            'external_mouth_width_m':.32, 'external_mouth_height_m':1.40,
            'inner_splay_width_m':.94, 'inner_splay_height_m':1.80,
            'dimensions_note':'Project design, no actor/camera passage through narrow firing slots',
            'interior_traversal_complete':False}
