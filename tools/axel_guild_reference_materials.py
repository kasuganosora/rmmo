"""Portable interior surface corrections; caller owns master/export/review.

All procedural nodes live in a temporary CPU bake scene.  The delivered nodes
are image/PBR nodes understood by glTF, not Blender-only Noise/Bump shaders.
The approved Fab knight and black-iron magic lantern materials are untouched.
"""
import json
import math
import random
import shutil
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2] / 'rmmo_runtime'
OUT = ROOT / 'art_sources/axel_guild/repair_v3/materials'
LIB = ROOT / 'packs/default/assets/materials'
REVISION = '20261013'


def _pbr(m):
    return next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def _image(path, color=False):
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    image.pack()
    return image


def _material(name, color=(1, 1, 1), roughness=.75, metallic=0, alpha=1):
    m = bpy.data.materials.new('Guild reference 20261013 | ' + name)
    m.use_nodes = True
    m['reference_material_revision'] = REVISION
    m.diffuse_color = (*color, alpha)
    p = _pbr(m)
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Alpha'].default_value = alpha
    return m


def _texture(m, image, socket, strength=1):
    nt = m.node_tree
    p = _pbr(m)
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    tex.extension = 'REPEAT'
    if socket == 'Normal':
        normal = nt.nodes.new('ShaderNodeNormalMap')
        normal.inputs['Strength'].default_value = strength
        nt.links.new(tex.outputs['Color'], normal.inputs['Color'])
        nt.links.new(normal.outputs['Normal'], p.inputs[socket])
    else:
        nt.links.new(tex.outputs['Color'], p.inputs[socket])
    return tex


def _multiply_color(m, image, color):
    nt = m.node_tree
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    mul = nt.nodes.new('ShaderNodeMixRGB')
    mul.blend_type = 'MULTIPLY'
    mul.inputs[0].default_value = 1
    mul.inputs[2].default_value = (*color, 1)
    nt.links.new(tex.outputs['Color'], mul.inputs[1])
    nt.links.new(mul.outputs[0], _pbr(m).inputs['Base Color'])


def _asset_id(obj):
    while obj:
        if obj.get('asset_id'):
            return obj['asset_id']
        obj = obj.parent
    return None


def _uv_project(obj, indices, tile):
    """Object-space metre projection, used only on newly textured surfaces."""
    obj.data = obj.data.copy()
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name='UVMap')
    # Rotation is omitted: grain remains attached to the movable source prop.
    scale = obj.matrix_world.to_scale()
    for face in obj.data.polygons:
        if face.material_index not in indices:
            continue
        axis = max(range(3), key=lambda k: abs(face.normal[k]))
        axes = [k for k in range(3) if k != axis]
        for loop in face.loop_indices:
            co = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv.data[loop].uv = (co[axes[0]] * scale[axes[0]] / tile,
                                co[axes[1]] * scale[axes[1]] / tile)


class _Bake:
    """A tiny CPU-only scene, fully discarded after making portable maps."""
    def __enter__(self):
        self.original_scene = bpy.context.window.scene
        self.scene = bpy.data.scenes.new('Reference material CPU bake')
        bpy.context.window.scene = self.scene
        self.scene.render.engine = 'CYCLES'
        self.scene.cycles.device = 'CPU'
        self.scene.cycles.samples = 1
        self.scene.render.threads_mode = 'FIXED'
        self.scene.render.threads = 8
        self.scene.render.bake.margin = 4
        mesh = bpy.data.meshes.new('Reference material bake plane')
        mesh.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
        mesh.update()
        uv = mesh.uv_layers.new(name='UVMap')
        for loop in mesh.loops:
            uv.data[loop.index].uv = mesh.vertices[loop.vertex_index].co[:2]
        self.plane = bpy.data.objects.new('Reference material bake plane', mesh)
        self.scene.collection.objects.link(self.plane)
        self.plane.select_set(True)
        self.scene.view_layers[0].objects.active = self.plane
        self.material = bpy.data.materials.new('Temporary procedural surface to bake')
        self.material.use_nodes = True
        mesh.materials.append(self.material)
        return self

    def nodes(self):
        nt = self.material.node_tree
        nt.nodes.clear()
        uv = nt.nodes.new('ShaderNodeTexCoord')
        return nt, uv.outputs['UV']

    def save(self, key, socket, is_color=False, normal=False, size=1024):
        path = OUT / (key + '.png')
        nt = self.material.node_tree
        output = nt.nodes.new('ShaderNodeOutputMaterial')
        if normal:
            p = nt.nodes.new('ShaderNodeBsdfPrincipled')
            nt.links.new(socket, p.inputs['Normal'])
            nt.links.new(p.outputs[0], output.inputs['Surface'])
        else:
            emission = nt.nodes.new('ShaderNodeEmission')
            nt.links.new(socket, emission.inputs['Color'])
            nt.links.new(emission.outputs[0], output.inputs['Surface'])
        image = bpy.data.images.new(key, width=size, height=size, alpha=False)
        image.colorspace_settings.name = 'sRGB' if is_color else 'Non-Color'
        target = nt.nodes.new('ShaderNodeTexImage')
        target.image = image
        nt.nodes.active = target
        bpy.ops.object.bake(type='NORMAL' if normal else 'EMIT', use_clear=True)
        image.filepath_raw = str(path)
        image.file_format = 'PNG'
        image.save()
        image.pack()
        nt.nodes.remove(target)
        nt.nodes.remove(output)
        return image

    def __exit__(self, *args):
        bpy.context.window.scene = self.original_scene
        mesh = self.plane.data
        bpy.data.objects.remove(self.plane, do_unlink=True)
        bpy.data.meshes.remove(mesh)
        bpy.data.materials.remove(self.material)
        bpy.data.scenes.remove(self.scene)


def _noise(nt, uv, scale, detail=3):
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.inputs['Scale'].default_value = scale
    n.inputs['Detail'].default_value = detail
    n.inputs['Roughness'].default_value = .65
    nt.links.new(uv, n.inputs['Vector'])
    return n.outputs['Fac']


def _ramp(nt, value, low, high, start=0, end=1):
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = start
    ramp.color_ramp.elements[0].color = (*low, 1)
    ramp.color_ramp.elements[1].position = end
    ramp.color_ramp.elements[1].color = (*high, 1)
    nt.links.new(value, ramp.inputs[0])
    return ramp.outputs['Color']


def _bump(nt, height, distance):
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Distance'].default_value = distance
    bump.inputs['Strength'].default_value = 1
    nt.links.new(height, bump.inputs['Height'])
    return bump.outputs['Normal']


def _maps():
    """Cache generated CPU bakes, never replace source/owned image data."""
    definitions = {'cloth_rough_v1': False, 'cloth_normal_v1': False,
                   'bone_color_v2': True, 'bone_rough_v2': False,
                   'bone_normal_v1': False, 'metal_rough_v1': False,
                   'crystal_mist_v1': True}
    linen_source = LIB / 'details/linen_curtain/linen_v2.png'
    dest = OUT / 'linen_existing_full_resolution.png'
    if not dest.exists():
        shutil.copyfile(linen_source, dest)
    linen = _image(dest, True)
    missing = [name for name in definitions if not (OUT / (name + '.png')).exists()]
    if missing:
        with _Bake() as bake:
            for name in missing:
                nt, uv = bake.nodes()
                if name.startswith('cloth'):
                    tex = nt.nodes.new('ShaderNodeTexImage')
                    tex.image = linen
                    nt.links.new(uv, tex.inputs['Vector'])
                    if 'rough' in name:
                        socket = _ramp(nt, tex.outputs['Color'], (.83,) * 3, (.97,) * 3)
                    else:
                        # Plane represents 25cm: 0.8mm relief / .25m tile.
                        socket = _bump(nt, tex.outputs['Color'], .0032)
                elif name.startswith('bone'):
                    broad = _noise(nt, uv, 5, 3)
                    if 'color' in name:
                        socket = _ramp(nt, broad, (.46, .42, .34), (.55, .51, .425), .18, .82)
                    elif 'rough' in name:
                        socket = _ramp(nt, _noise(nt, uv, 45), (.58,) * 3, (.77,) * 3)
                    else:
                        socket = _bump(nt, _noise(nt, uv, 210, 2), .0012)
                elif name.startswith('metal'):
                    socket = _ramp(nt, _noise(nt, uv, 120, 2), (.235,) * 3, (.36,) * 3)
                elif name.startswith('crystal'):
                    socket = _ramp(nt, _noise(nt, uv, 7, 5),
                                   (.002, .055, .078), (.018, .28, .29), .15, .85)
                else:
                    raise ValueError(name)
                bake.save(name, socket, definitions[name], 'normal' in name,
                          size=512 if name.startswith('metal') else 1024)
    result = {name: _image(OUT / (name + '.png'), color)
              for name, color in definitions.items()}
    result['linen'] = linen
    result['bone_color_v1'] = result['bone_color_v2']
    result['bone_rough_v1'] = result['bone_rough_v2']
    for key, filename in [('color', 'guild_cut_limestone_mineral_color.png'),
                           ('rough', 'guild_cut_limestone_roughness.png'),
                           ('normal', 'guild_cut_limestone_micro_normal.png')]:
        result['cut_stone_' + key + '_v1'] = _image(OUT / filename, key == 'color')
    return result


def _metal(source, name, color, maps, strength):
    m = _material(name, color, metallic=1)
    _texture(m, maps['metal_rough_v1'], 'Roughness')
    # Physical micro-roughness is enough at sub-millimetre scale. No coarse
    # scratch normal that would turn the small metal ring into hammered stone.
    _pbr(m).inputs['Coat Weight'].default_value = strength
    m['finish'] = 'subtle handling wear; neutral specular metal; no paint'
    return m


def _crystal_interior_stars(material):
    """Actual tiny 3D inclusions; one shared mesh/material, never a decal."""
    results = []
    for root in [o for o in bpy.context.scene.objects
                 if o.get('asset_id') == 'guild_registration_crystal']:
        old = [o for o in root.children_recursive if o.get('crystal_internal_starfield')]
        for o in old:
            bpy.data.objects.remove(o, do_unlink=True)
        candidates = [o for o in root.children_recursive if o.type == 'MESH'
                      and max(o.dimensions) > .3 and max(o.dimensions) < .44
                      and any(m and 'cyan crystal transparent shell' in m.name for m in o.data.materials)]
        if len(candidates) != 1:
            raise RuntimeError('Expected one 0.42m registration sphere: ' + root.name)
        globe = candidates[0]
        transform = root.matrix_world.inverted() @ globe.matrix_world
        points = [transform @ v.co for v in globe.data.vertices]
        lo = Vector(tuple(min(v[k] for v in points) for k in range(3)))
        hi = Vector(tuple(max(v[k] for v in points) for k in range(3)))
        center = (lo + hi) / 2
        radius = min(hi-lo) / 2
        rng = random.Random(10132026)
        verts, faces = [], []
        # Tetrahedra have no camera-facing dependence, unlike billboard stars.
        corners = [Vector(v).normalized() for v in [(1,1,1),(-1,-1,1),(-1,1,-1),(1,-1,-1)]]
        for i in range(1600):
            direction = Vector((rng.gauss(0,1), rng.gauss(0,1), rng.gauss(0,1))).normalized()
            distance = (rng.random() ** (.44 if i < 550 else 1/3)) * radius * .91
            pos = center + direction * distance
            # 0.7-2.2mm grain; a few brighter 3mm inclusions, not large glitter.
            grain_radius = rng.uniform(.00035, .0011) if i % 41 else .0015
            index = len(verts)
            verts.extend([tuple(pos + corner * grain_radius) for corner in corners])
            faces.extend([tuple(index+j for j in face) for face in [(0,2,1),(0,1,3),(0,3,2),(1,2,3)]])
        mesh = bpy.data.meshes.new('Crystal 1600 physical internal dust stars')
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        # Emissive solid colour needs no sampled UVs, but keep a valid UV layer
        # for the common static-prop export/resource-validation contract.
        mesh.uv_layers.new(name='UVMap')
        mesh.materials.append(material)
        obj = bpy.data.objects.new('Crystal internal blue-white starfield', mesh)
        root.users_collection[0].objects.link(obj)
        obj.parent = root
        obj['crystal_internal_starfield'] = True
        obj['rmmo_collision'] = 'none'
        obj['collision_review'] = False
        obj['independent_prop'] = True
        obj['structural_wall'] = False
        obj['semantic_group'] = root.get('semantic_group', '42_Independent_Props')
        obj['reference_status'] = 'U11 visible fine luminous inclusions; physical distribution is project supplemental design'
        results.append({'root': root.name, 'object': obj.name, 'stars':1600,
                        'triangles':6400, 'materials':1, 'radius_m':radius,
                        'center_local_m':list(center), 'collision':'none'})
    return results


def _bone_surface_geometry(bone):
    """Remove schematic head corners and the old 'pin'/'spine' classifier bug.

    Control points come from the existing approved envelope, not new anatomy.
    Original jaw parent, teeth, suspension anchors and steel armature survive.
    """
    result = []
    prefixes = ('Skull cheek arch', 'Orbital brow ridge', 'Skull posterior crest',
                'Open lower mandible', 'Mandibular symphysis', 'Neural arch')
    for root in [o for o in bpy.context.scene.objects
                 if o.get('asset_id') == 'guild_hanging_skeleton']:
        if root.get('reference_bone_geometry_revision') == REVISION:
            continue
        for obj in list(root.children_recursive):
            if obj.type != 'MESH':
                continue
            before = len(obj.data.polygons)
            reason = None
            if obj.name.startswith('Neural spine'):
                obj.data = obj.data.copy()
                obj.data.materials.clear()
                obj.data.materials.append(bone)
                _uv_project(obj, [0], .65)
                reason = 'Neural spine is bone; previous substring pin incorrectly selected forged iron.'
            elif obj.name.startswith(prefixes):
                old = obj.data
                sides = 12
                if len(old.vertices) % sides:
                    raise RuntimeError('Unexpected bone curve ring layout: ' + obj.name)
                controls, radii = [], []
                for start in range(0, len(old.vertices), sides):
                    ring = [v.co.copy() for v in old.vertices[start:start+sides]]
                    center = sum(ring, Vector()) / sides
                    controls.append(center)
                    radii.append(sum((v-center).length for v in ring) / sides)
                points, widths = [], []
                count = 4 if obj.name.startswith('Neural arch') else 8
                for i in range(len(controls)-1):
                    p1, p2 = controls[i:i+2]
                    p0 = controls[i-1] if i else 2*p1-p2
                    p3 = controls[i+2] if i+2 < len(controls) else 2*p2-p1
                    for j in range(count):
                        t = j / count
                        points.append(.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t*t + (-p0+3*p1-3*p2+p3)*t*t*t))
                        widths.append(radii[i]*(1-t)+radii[i+1]*t)
                points.append(controls[-1]); widths.append(radii[-1])
                verts, faces, normal = [], [], None
                sides = 12 if obj.name.startswith('Neural arch') else 16
                for i, point in enumerate(points):
                    tangent = (points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
                    if normal is None:
                        guide = Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((1,0,0))
                        normal = tangent.cross(guide).normalized()
                    else:
                        normal = (normal-tangent*normal.dot(tangent)).normalized()
                    other = tangent.cross(normal).normalized()
                    verts.extend([tuple(point + widths[i] * (normal*math.cos(math.tau*j/sides)+other*math.sin(math.tau*j/sides))) for j in range(sides)])
                for i in range(len(points)-1):
                    for j in range(sides):
                        a=i*sides+j; b=i*sides+(j+1)%sides
                        faces.append((a,b,b+sides,a+sides))
                faces.extend([tuple(reversed(range(sides))),tuple(range(len(verts)-sides,len(verts)))])
                mesh = bpy.data.meshes.new(obj.name + ' continuous bone arc')
                mesh.from_pydata(verts, [], faces); mesh.update()
                mesh.materials.append(bone)
                obj.data = mesh
                for face in mesh.polygons:
                    face.use_smooth = len(face.vertices) == 4
                _uv_project(obj, [0], .65)
                reason = 'Existing anatomical control points resampled as continuous curved bone; parent and endpoints retained.'
            elif obj.name == 'Skull nasal bridge':
                # An arched thin nasal roof replaces the original eight-vertex
                # wedge. Elliptical sections avoid flat board-like broad faces.
                verts, faces = [], []
                rings, sides = 17, 24
                for i in range(rings):
                    t = i/(rings-1)
                    y = -2.15-.85*t
                    width = .36*(1-t)+.24*t
                    center_z = .20*(1-t)-.025*t
                    height = .07*(1-t)+.055*t
                    for j in range(sides):
                        angle = math.tau*j/sides
                        verts.append((width*math.cos(angle), y,
                                      center_z+height*math.sin(angle)+.025*math.sin(math.pi*t)))
                for i in range(rings-1):
                    for j in range(sides):
                        a=i*sides+j;b=i*sides+(j+1)%sides
                        faces.append((a,b,b+sides,a+sides))
                faces.extend([tuple(reversed(range(sides))),tuple(range(len(verts)-sides,len(verts)))])
                mesh = bpy.data.meshes.new('Skull continuous arched nasal roof')
                mesh.from_pydata(verts, [], faces); mesh.update(); mesh.materials.append(bone)
                obj.data = mesh
                for face in mesh.polygons:face.use_smooth=len(face.vertices)==4
                _uv_project(obj, [0], .65)
                reason = 'Replace planar wedge with thin arched nasal bone, preserving original snout envelope.'
            elif obj.name == 'Skull rear cranium':
                obj.data = obj.data.copy()
                bpy.context.view_layer.objects.active = obj
                mod = obj.modifiers.new('Continuous cranium around open eye sockets', 'SUBSURF')
                mod.levels = 1; mod.render_levels = 1
                bpy.ops.object.modifier_apply(modifier=mod.name)
                for face in obj.data.polygons:face.use_smooth=True
                _uv_project(obj, [0], .65)
                reason = 'Single subdivision of original socketed cranium to remove faceted silhouette.'
            if reason:
                bm = bmesh.new(); bm.from_mesh(obj.data)
                bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
                non_manifold = sum(not edge.is_manifold for edge in bm.edges)
                bm.to_mesh(obj.data); bm.free()
                if non_manifold:
                    raise RuntimeError(f'{obj.name}: non-manifold bone repair ({non_manifold})')
                obj['reference_bone_correction'] = reason
                result.append({'object':obj.name, 'reason':reason, 'faces_before':before,
                               'faces_after':len(obj.data.polygons), 'non_manifold_edges':non_manifold})
        root['reference_bone_geometry_revision'] = REVISION
    return result


def _vessel_meridians():
    """Smooth only authored vessel profiles; never subdivide rims or fittings.

    Forty-eight radial sides were already sufficient. The visible facets came
    from long straight meridian segments. Shape-preserving cubic interpolation
    supplies continuous curvature between those controls without overshoot.
    Mouth/spout, flat foot, cork, handles, materials and object pivots survive.
    """
    from mathutils.bvhtree import BVHTree

    ids = {'guild_bottle_tall', 'guild_bottle_round', 'guild_bottle_squat',
           'guild_serving_jug', 'guild_wash_ewer'}
    result = []

    def parts(mesh):
        adjacency = [[] for _ in mesh.vertices]
        for edge in mesh.edges:
            a, b = edge.vertices
            adjacency[a].append(b); adjacency[b].append(a)
        left = set(range(len(adjacency))); components = []
        while left:
            stack = [left.pop()]; component = []
            while stack:
                v = stack.pop(); component.append(v)
                for n in adjacency[v]:
                    if n in left:
                        left.remove(n); stack.append(n)
            components.append(sorted(component))
        return components

    def derivative(values, times):
        slopes = [(values[i+1]-values[i])/(times[i+1]-times[i])
                  for i in range(len(values)-1)]
        output = [slopes[0]]
        for i in range(1, len(values)-1):
            if slopes[i-1] * slopes[i] <= 0:
                output.append(0.)
            else:
                left, right = times[i]-times[i-1], times[i+1]-times[i]
                w1, w2 = 2*right+left, right+2*left
                output.append((w1+w2)/(w1/slopes[i-1]+w2/slopes[i]))
        return output + [slopes[-1]]

    for obj in list(bpy.context.scene.objects):
        aid = _asset_id(obj)
        if obj.type != 'MESH' or aid not in ids or obj.get('reference_vessel_revision'):
            continue
        old = obj.data
        components = parts(old)
        body = max(components, key=len)
        # The body starts and ends on the lathe axis. Excludes bottle labels.
        if (old.vertices[body[0]].co.xy.length > 1e-6 or
                old.vertices[body[-1]].co.xy.length > 1e-6):
            continue
        rings, cursor = [], 0
        while cursor < len(body):
            v = old.vertices[body[cursor]].co
            n = 1 if v.xy.length < 1e-6 else 48
            if cursor+n > len(body):
                raise RuntimeError('Unexpected vessel ring layout: ' + obj.name)
            rings.append([old.vertices[k].co.copy() for k in body[cursor:cursor+n]])
            cursor += n
        times = [0.]
        for a, b in zip(rings, rings[1:]):
            times.append(times[-1]+max((a[0]-b[0]).length, 1e-7))
        # Expand axis controls only for interpolation; emitted axis remains one vertex.
        expanded = [ring if len(ring) == 48 else ring*48 for ring in rings]
        derivatives = [[derivative([ring[j][axis] for ring in expanded], times)
                        for axis in range(3)] for j in range(48)]
        zmin = min(v.co.z for v in old.vertices)
        zmax = max(v.co.z for v in old.vertices)
        height = zmax-zmin
        refined = []
        for i, ring in enumerate(rings[:-1]):
            refined.append(ring)
            nxt = rings[i+1]
            mean_a = sum(p.z for p in ring)/len(ring)
            mean_b = sum(p.z for p in nxt)/len(nxt)
            # All top lip/spout controls and the flat bottom are copied verbatim.
            if (len(ring) != 48 or len(nxt) != 48 or
                    min(mean_a, mean_b) <= zmin+height*.025 or
                    max(mean_a, mean_b) >= zmin+height*.77):
                continue
            distance = times[i+1]-times[i]
            def point_at(j, t):
                h00, h10 = 2*t**3-3*t*t+1, t**3-2*t*t+t
                h01, h11 = -2*t**3+3*t*t, t**3-t*t
                point = []
                for axis in range(3):
                    a, b = ring[j][axis], nxt[j][axis]
                    value = (h00*a+h10*distance*derivatives[j][axis][i] +
                             h01*b+h11*distance*derivatives[j][axis][i+1])
                    point.append(max(min(a,b), min(max(a,b), value)))
                return Vector(point)
            # Cylinder walls need no extra rings. Refine only curved intervals
            # with >0.12mm meridian deviation; cost follows visible curvature.
            deviation = max((point_at(j,t)-ring[j].lerp(nxt[j],t)).length
                            for j in (0,12,24,36) for t in (.25,.5,.75))
            count = max(1, min(12, math.ceil(math.sqrt(deviation/.00012))))
            for step in range(1, count):
                refined.append([point_at(j, step/count) for j in range(48)])
        refined.append(rings[-1])
        body_set = set(body)
        keep = [v.index for v in old.vertices if v.index not in body_set]
        remap = {k:i for i,k in enumerate(keep)}
        verts = [tuple(old.vertices[k].co) for k in keep]
        faces, material_indices, smooth, preserved_uv = [], [], [], []
        olduv = old.uv_layers.active
        for face in old.polygons:
            if face.vertices[0] in body_set:
                continue
            faces.append(tuple(remap[k] for k in face.vertices))
            material_indices.append(face.material_index); smooth.append(face.use_smooth)
            preserved_uv.append([tuple(olduv.data[k].uv) for k in face.loop_indices] if olduv else None)
        first_body_face = len(faces)
        body_mat = next(f.material_index for f in old.polygons if f.vertices[0] in body_set)
        indexes = []
        for ring in refined:
            indexes.append(list(range(len(verts),len(verts)+len(ring))))
            verts.extend(tuple(p) for p in ring)
        for a, b in zip(indexes, indexes[1:]+indexes[:1]):
            if len(a) == len(b) == 1:
                continue
            for j in range(48):
                k = (j+1)%48
                face = ((a[0],b[k],b[j]) if len(a)==1 else
                        (a[j],a[k],b[0]) if len(b)==1 else (a[j],a[k],b[k],b[j]))
                faces.append(face); material_indices.append(body_mat); smooth.append(True)
                preserved_uv.append(None)
        mesh = bpy.data.meshes.new(obj.name + ' continuous vessel meridian')
        mesh.from_pydata(verts, [], faces); mesh.update()
        for material in old.materials:
            mesh.materials.append(material)
        uv = mesh.uv_layers.new(name=olduv.name if olduv else 'UVMap')
        for face in mesh.polygons:
            face.material_index = material_indices[face.index]
            face.use_smooth = smooth[face.index] if face.index < first_body_face else abs(face.normal.z) < .98
            existing = preserved_uv[face.index]
            angles = [math.atan2(mesh.vertices[k].co.y, mesh.vertices[k].co.x)/math.tau for k in face.vertices]
            if max(angles)-min(angles) > .5:
                angles = [a+1 if a<0 else a for a in angles]
            for j, loop in enumerate(face.loop_indices):
                co = mesh.vertices[mesh.loops[loop].vertex_index].co
                uv.data[loop].uv = existing[j] if existing else (angles[j], (co.z-zmin)/height)
        bm = bmesh.new(); bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bad = sum(not edge.is_manifold for edge in bm.edges)
        bm.to_mesh(mesh); bm.free()
        if bad:
            raise RuntimeError(f'Non-manifold vessel repair: {obj.name}, {bad}')
        before = sum(max(0,len(f.vertices)-2) for f in old.polygons)
        obj.data = mesh
        obj['reference_vessel_revision'] = REVISION
        # Keep the paper label at the surface, including its original thickness.
        labels_updated = []
        if aid.startswith('guild_bottle'):
            bvh = BVHTree.FromPolygons([v.co for v in mesh.vertices],
                                      [list(f.vertices) for f in mesh.polygons[first_body_face:]])
            for sibling in list(bpy.context.scene.objects):
                if sibling.type != 'MESH' or sibling == obj or sibling.parent != obj.parent:
                    continue
                if len(sibling.data.vertices) != 182:
                    continue
                sibling.data = sibling.data.copy()
                for vertex in sibling.data.vertices:
                    direction = Vector((vertex.co.x, vertex.co.y, 0)).normalized()
                    hit, _, _, _ = bvh.ray_cast(direction*.5+Vector((0,0,vertex.co.z)), -direction, .5)
                    if hit is None:
                        raise RuntimeError('Label projection missed vessel: ' + sibling.name)
                    radius = hit.xy.length + (.0004 if vertex.index < 91 else .0009)
                    vertex.co.x, vertex.co.y = direction.x*radius, direction.y*radius
                labels_updated.append(sibling.name)
        result.append({'asset_id':aid, 'object':obj.name, 'triangles_before':before,
                       'triangles_after':sum(len(f.vertices)-2 for f in mesh.polygons),
                       'radial_sides':48, 'original_rings':len(rings), 'refined_rings':len(refined),
                       'non_manifold_edges':bad, 'labels_conformed':labels_updated,
                       'preserved':'All source profile controls, flat base, upper 23% mouth/spout, handles, cork, hierarchy and collision extras'})
    return result


def apply():
    """Apply after geometry repairs; preserve placement, collision and pivots."""
    OUT.mkdir(parents=True, exist_ok=True)
    maps = _maps()
    report = {'changed_asset_ids': [], 'material_names': [], 'changes': [],
              'texture_directory': str(OUT), 'revision': REVISION,
              'source_policy': 'Existing owned 2K PBR preserved; new procedural surfaces CPU baked.'}
    materials = {}
    materials['linen'] = _material('ivory woven bed linen', roughness=.9)
    _multiply_color(materials['linen'], maps['linen'], (1, .99, .96))
    materials['red_cloth'] = _material('oxblood woven upholstery', roughness=.9)
    _multiply_color(materials['red_cloth'], maps['linen'], (.265, .026, .020))
    for key in ('linen', 'red_cloth'):
        _texture(materials[key], maps['cloth_rough_v1'], 'Roughness')
        _texture(materials[key], maps['cloth_normal_v1'], 'Normal', .5)
        # Current game/native contract has no KHR_materials_sheen support.
        # Preserve the woven roughness/normal response through core PBR.
        _pbr(materials[key]).inputs['Sheen Weight'].default_value = 0
        _pbr(materials[key]).inputs['Sheen Roughness'].default_value = .85
        materials[key]['tile_size_m'] = .25
    materials['bone'] = _material('aged cortical bone', roughness=.82)
    for field, socket in [('color', 'Base Color'), ('rough', 'Roughness'), ('normal', 'Normal')]:
        _texture(materials['bone'], maps['bone_' + field + '_v1'], socket, .15)
    materials['bone']['tile_size_m'] = .65
    materials['stone'] = _material('cut limestone statue pedestal', roughness=.83)
    for field, socket in [('color', 'Base Color'), ('rough', 'Roughness'), ('normal', 'Normal')]:
        _texture(materials['stone'], maps['cut_stone_' + field + '_v1'], socket, .18)
    materials['stone']['tile_size_m'] = .65
    materials['steel'] = _metal(None, 'registration neutral brushed steel', (.50, .52, .51), maps, 0)
    materials['brass'] = _metal(None, 'registration warm gold brass', (.72, .49, .18), maps, .08)
    crystal = materials['crystal'] = _material('cyan crystal transparent shell',
                                               (.04, .46, .49), .085, alpha=.58)
    p = _pbr(crystal)
    p.inputs['IOR'].default_value = 1.46
    p.inputs['Transmission Weight'].default_value = 0
    p.inputs['Coat Weight'].default_value = .38
    p.inputs['Coat Roughness'].default_value = .08
    p.inputs['Emission Strength'].default_value = .18
    _texture(crystal, maps['crystal_mist_v1'], 'Emission Color')
    crystal.surface_render_method = 'BLENDED'
    crystal.use_transparent_shadow = True
    crystal['portable_alpha_mode'] = 'BLEND'
    crystal['transmission_policy'] = 'Alpha fallback intentionally used; no promise of Godot physical refraction.'
    crystal['alpha_factor'] = .58
    crystal['reference'] = 'U10/U11 cyan sphere; restrained cloudy luminance, ring remains legible'
    inset = materials['inset'] = _material('cyan polished crystal inlay', (.035, .39, .42), .16)
    _pbr(inset).inputs['Coat Weight'].default_value = .25
    _pbr(inset).inputs['Emission Color'].default_value = (.006, .18, .20, 1)
    _pbr(inset).inputs['Emission Strength'].default_value = .08
    stars = materials['stars'] = _material('internal blue white luminous dust', (.24, .72, .9), .4)
    _pbr(stars).inputs['Emission Color'].default_value = (.24, .76, 1, 1)
    _pbr(stars).inputs['Emission Strength'].default_value = 4.5

    changed = set()
    wood_copies = {}

    def aged_wood(old, color, label):
        key = (old.name, label)
        if key not in wood_copies:
            new = old.copy()
            new.name = 'Guild reference 20261013 | ' + label + ' ' + str(len(wood_copies))
            new['reference_material_revision'] = REVISION
            p = _pbr(new)
            link = next((l for l in new.node_tree.links if l.to_socket == p.inputs['Base Color']), None)
            if not link or link.from_node.type != 'TEX_IMAGE':
                raise RuntimeError('Unexpected joinery image chain: ' + old.name)
            image = link.from_node.image
            new.node_tree.links.remove(link)
            _multiply_color(new, image, color)
            p.inputs['Metallic'].default_value = 0
            new['wood_finish'] = 'Neutral-light verified aged timber; original 2048 PBR maps and grain UV retained'
            wood_copies[key] = new
        return wood_copies[key]

    inset_source = next(m for m in bpy.data.materials
                        if m.name.startswith('Guild owned natural joinery timber') and m.use_nodes
                        and any(n.type == 'TEX_IMAGE' and n.image and
                                'furniture_v1' in n.image.filepath.replace('\\', '/')
                                for n in m.node_tree.nodes))
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH':
            continue
        aid = _asset_id(obj)
        changes = []
        uv_faces = {}
        for index, old in enumerate(obj.data.materials):
            if not old:
                continue
            target = None
            tile = None
            if aid in ('guild_guest_bed', 'guild_guest_chair'):
                if old.name == 'Guild linen':
                    target, tile = materials['linen'], .25
                elif old.name == 'Guild oxblood woven upholstery':
                    target, tile = materials['red_cloth'], .25
            if aid in ('guild_privacy_screen', 'guild_towel_rail') and old.name.startswith('Guild linen'):
                target, tile = materials['linen'], .25
            if aid in ('guild_wash_basin', 'guild_shower_tray', 'guild_registration_counter') and old.name.startswith('Guild pale counter brackets'):
                target, tile = materials['stone'], .65
            if aid == 'guild_storage_cabinet' and old.name.startswith('Guild recessed timber'):
                target = aged_wood(inset_source, (.165, .145, .11), 'recessed natural timber')
            if aid == 'guild_hanging_skeleton' and old.name == 'Guild PBR | aged bone':
                target, tile = materials['bone'], .65
            if obj.name.startswith('Statue stepped plinth') and old.name == 'WB pale stone clay':
                target, tile = materials['stone'], .65
            if aid == 'guild_registration_crystal':
                if old.name == 'Guild registration crystal':
                    target = materials['crystal']
                elif old.name == 'Guild blue inset crystal':
                    target = materials['inset']
                elif old.name.startswith('Guild worn pewter iron'):
                    target = materials['steel']
                elif old.name.startswith('Guild aged brass'):
                    target = materials['brass']
            if old.name.startswith('Guild owned natural joinery timber') and old.use_nodes:
                images = [n.image for n in old.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
                # Guest room timber already has its own darker source variant.
                # Final neutral-light review found the .39/.40/.29 multiplier
                # still read as raw yellow softwood.  Retain scanned maps and
                # bring the whole pale-source family into the aged wood range.
                if any('furniture_v1' in im.filepath.replace('\\', '/') for im in images):
                    target = aged_wood(old, (.20, .18, .135), 'aged hall timber')
                elif any('furnishings_v1' in im.filepath.replace('\\', '/') for im in images):
                    target = aged_wood(old, (.20, .18, .135), 'aged furnishing timber')
                elif any('textiles_sanitary_v1' in im.filepath.replace('\\', '/') for im in images):
                    target = aged_wood(old, (.28, .245, .19), 'sealed sanitary timber')
            if target:
                # Some repeated instances share mesh datablocks. Copy before
                # reassignment so every changed root is accounted for below.
                if obj.data.users > 1:
                    obj.data = obj.data.copy()
                obj.data.materials[index] = target
                changes.append({'from': old.name, 'to': target.name})
                if tile:
                    uv_faces.setdefault(tile, []).append(index)
        if changes:
            for tile, indices in uv_faces.items():
                _uv_project(obj, indices, tile)
            if aid:
                changed.add(aid)
            report['changes'].append({'object': obj.name, 'asset_id': aid,
                                      'materials': changes, 'tile_sizes_m': list(uv_faces)})
    report['bone_geometry'] = _bone_surface_geometry(materials['bone'])
    report['crystal_starfield'] = _crystal_interior_stars(stars)
    report['vessel_geometry'] = _vessel_meridians()
    changed.update(item['asset_id'] for item in report['vessel_geometry'])
    if report['crystal_starfield']:
        changed.add('guild_registration_crystal')
    report['changed_asset_ids'] = sorted(changed)
    report['material_names'] = sorted(set(change['to'] for item in report['changes']
                                          for change in item['materials']) | {stars.name})
    report['dimension_basis'] = {
        'linen': '0.25m repeat, supplied project plain weave; approximately 1mm yarns. UV projected in object metres.',
        'bone': '0.65m repeat, sub-mm cortical surface grain. Project supplemental material, not reference measurement.',
        'pedestal': '0.65m fine cut limestone repeat without mortar. Four existing step volumes unchanged.',
        'wood': 'Existing component-aligned UVs and all original 2K base/rough/normal images preserved.',
        'crystal': 'Original 0.42m sphere preserved; alpha BLEND .58, dielectric IOR1.46, roughness .085.'}
    report['protected_materials'] = ['Fab knight statue body', 'black iron lantern',
                                     'lantern glass panes', 'warm-white suspended magic stone']
    (OUT / 'interior_material_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return report
