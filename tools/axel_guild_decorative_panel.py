"""Independent arched guild ornament, in metres; front = Blender -Y.

U03/U05 establish the silhouette and front motifs. Metric size, coated wood /
metal interpretation and the discreet rear fixings are authored proposals.
This module creates geometry only, so the whitebox uses the exact same asset.
"""
import math
import bpy
import bmesh

ASSET_ID = 'guild_statue_decorative_panel'
WIDTH = 1.08
HEIGHT = 3.30
BODY_DEPTH = .06
FRAME_DEPTH = .10
RING_CENTRES = (.60, 1.68, 2.76)


def build_panel(collection, materials, name=ASSET_ID, quality='game'):
    arc_steps = 32 if quality == 'game' else 64
    ring_steps = 64 if quality == 'game' else 128
    root = bpy.data.objects.new(name, None)
    collection.objects.link(root)
    root['asset_id'] = ASSET_ID
    root['asset_version'] = 1
    root['independent_prop'] = True
    root['structural_wall'] = False
    root['front_axis'] = '-Y'
    root['dimensions_are_proposed'] = True
    root['body_depth_m'] = BODY_DEPTH
    root['frame_depth_m'] = FRAME_DEPTH
    root['height_m'] = HEIGHT
    root['reference_ids'] = 'U03,U05'
    objects = []

    def mesh(label, vertices, faces, mat, collision=False, bevel=0):
        data = bpy.data.meshes.new(label)
        data.from_pydata(vertices, [], faces)
        data.update()
        bm = bmesh.new(); bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(data); bm.free()
        uv = data.uv_layers.new(name='SurfaceUV')
        for p in data.polygons:
            for index in p.loop_indices:
                co = data.vertices[data.loops[index].vertex_index].co
                # Front and back have full-height wood grain; edges get planar UVs.
                uv.data[index].uv = ((co.x / WIDTH + .5, co.z / HEIGHT)
                                     if abs(p.normal.y) > .5 else (co.y * 3, co.z / HEIGHT))
        obj = bpy.data.objects.new(name + '_' + label, data)
        collection.objects.link(obj); obj.parent = root
        data.materials.append(materials[mat])
        obj['collision_review'] = collision
        obj['prop_part'] = label
        obj['independent_prop'] = True
        obj['structural_wall'] = False
        if bevel:
            modifier = obj.modifiers.new('Small physical edge bevel', 'BEVEL')
            modifier.width = bevel
            modifier.segments = 1 if quality == 'game' else 3
            modifier = obj.modifiers.new('Weighted surface normals', 'WEIGHTED_NORMAL')
            modifier.keep_sharp = True
        objects.append(obj)
        return obj

    def outline(inset=0):
        rx = WIDTH / 2 - inset
        bottom = .045 + inset
        shoulder = HEIGHT - .27
        rz = .27 - inset
        return [(-rx, bottom), (rx, bottom)] + [
            (rx * math.cos(i * math.pi / arc_steps),
             shoulder + rz * math.sin(i * math.pi / arc_steps))
            for i in range(arc_steps + 1)]

    def extrude(label, shape, front, back, mat, collision=False, bevel=0):
        n = len(shape)
        return mesh(label, [(x, y, z) for y in [front, back] for x, z in shape],
                    [tuple(reversed(range(n))), tuple(range(n, 2*n))] +
                    [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)],
                    mat, collision, bevel)

    def strip(label, outer, inner, front, back, mat, bevel=0):
        n = len(outer)
        vertices = [(x, y, z) for y in [front, back] for shape in [outer, inner] for x,z in shape]
        faces = []
        for i in range(n):
            j = (i+1) % n
            faces += [(i,j,n+j,n+i), (2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j), (n+i,n+j,3*n+j,3*n+i)]
        obj = mesh(label, vertices, faces, mat, bevel=bevel)
        # Smooth only curved side walls, keeping the large faces perfectly flat.
        for p in obj.data.polygons:
            p.use_smooth = abs(p.normal.y) < .1
        return obj

    extrude('Painted_board', outline(.009), -.03, .03, 'board', True, .002)
    strip('Pale_metal_border', outline(), outline(.032), -.05, .05, 'trim', .002)
    for number, z in enumerate(RING_CENTRES, 1):
        curves = [[(r*math.cos(i*math.tau/ring_steps), z+r*math.sin(i*math.tau/ring_steps))
                   for i in range(ring_steps)] for r in [.40,.307]]
        strip(f'Rose_ring_{number}', curves[0], curves[1], -.045, -.03, 'rose', .002)

    def relief(label, shape, mat):
        n = len(shape)
        cx = sum(x for x,z in shape)/n; cz = sum(z for x,z in shape)/n
        vertices = [(x,-.032,z) for x,z in shape] + [(cx,-.049,cz)]
        mesh(label, vertices, [tuple(reversed(range(n)))] +
             [(i,(i+1)%n,n) for i in range(n)], mat)

    for number, z in enumerate([1.14,2.22], 1):
        for side, x in [('L',-.235),('R',.235)]:
            relief(f'Diamond_{number}_{side}',[(x-.055,z),(x,z+.075),(x+.055,z),(x,z-.075)],'gold')
        relief(f'Triangle_{number}_upper',[(-.04,z+.125),(.04,z+.125),(0,z+.06)],'gold')
        relief(f'Triangle_{number}_lower',[(-.04,z-.125),(0,z-.06),(.04,z-.125)],'gold')
        circle = [(.028*math.cos(i*math.tau/24),z+.028*math.sin(i*math.tau/24)) for i in range(24)]
        extrude(f'Rose_stud_{number}',circle,-.044,-.03,'rose',bevel=.001)

    # Reference does not expose the back or floor connection. Small bolted feet
    # are a construction proposal; no invented broad masonry plinth.
    for number, z in enumerate([.3,1.68,2.93],1):
        extrude(f'Rear_reinforcement_{number}',[(-.46,z-.025),(.46,z-.025),(.46,z+.025),(-.46,z+.025)],
                .03,.047,'board',bevel=.001)
    for side, x in [('L',-.36),('R',.36)]:
        extrude('Floor_anchor_'+side,[(x-.085,0),(x+.085,0),(x+.085,.045),(x-.085,.045)],
                -.055,.205,'trim',True,.002)
        extrude('Rear_anchor_'+side,[(x-.022,.04),(x+.022,.04),(x+.022,.25),(x-.022,.25)],
                .03,.065,'trim',bevel=.002)
    if quality == 'game':
        # Editable master keeps all 22 components; game version shares four
        # material batches. Each whole panel remains independently replaceable.
        by_material = {}
        for obj in objects:
            bpy.context.view_layer.objects.active = obj
            for modifier in list(obj.modifiers):
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            by_material.setdefault(obj.data.materials[0].name, []).append(obj)
        merged = []
        for key, parts in by_material.items():
            bpy.ops.object.select_all(action='DESELECT')
            labels = [obj['prop_part'] for obj in parts]
            has_collision = any(obj['collision_review'] for obj in parts)
            for obj in parts: obj.select_set(True)
            bpy.context.view_layer.objects.active = parts[0]
            bpy.ops.object.join()
            obj = bpy.context.object
            obj.name = name + '_' + key.replace(' ', '_')
            obj['component_names'] = ','.join(labels)
            obj['collision_review'] = has_collision
            merged.append(obj)
        bpy.ops.object.select_all(action='DESELECT')
        objects = merged
    return root, objects
