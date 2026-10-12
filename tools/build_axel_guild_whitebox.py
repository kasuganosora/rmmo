"""Editable, metre-scale Axel guild blockout; Blender 4.5 background script.

No resource catalogue or user map is modified. Neutral materials are intentional
whitebox materials, not the project's finished realistic art treatment.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from axel_guild_decorative_panel import build_panel
from axel_guild_furniture import build_furniture, bake_game_meshes
from axel_guild_furnishings import build_furnishing, ASSETS as NEW_FURNISHINGS
from axel_guild_textiles_sanitary import build_fitting, ASSETS as TEXTILE_SANITARY
from axel_guild_guestroom import build_guestroom, rig_cabinet, ASSETS as GUESTROOM
from axel_guild_fab_statue import build_knight_statue
from axel_guild_exterior import build_exterior, build_heraldry, build_main_doors
from axel_guild_landmarks import install_landmarks
from axel_guild_roof_joinery import fit_roof_wall_plates
from axel_alarm_tower_shaft import install_shooting_slits

P = argparse.ArgumentParser()
P.add_argument('--no-render', action='store_true')
P.add_argument('--shots', default='exterior,cutaway,ground,upper,hall,gallery,site,reception')
ARGS = P.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
ROOT = Path(__file__).resolve().parents[2] / 'rmmo_runtime'
OUT = ROOT / 'art_sources/axel_guild/whitebox_v13'
OUT.mkdir(parents=True, exist_ok=True)
SC = bpy.context.scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
SC.unit_settings.system = 'METRIC'
SC.unit_settings.scale_length = 1
COLLECTIONS = {}
ROOTS = {}
OBJECTS = []
ROOMS = []
FLOOR = 4.48
EAVE = 8.2
RIDGE = 14.0
CEILING = FLOOR + 3.6
DOOR_W = 1.6
DOOR_H = 3.0  # 2.1m actor + default 18 degree third-person orbit clearance.


def group(name):
    c = bpy.data.collections.new(name)
    SC.collection.children.link(c)
    root = bpy.data.objects.new(name, None)
    c.objects.link(root)
    root['whitebox_only'] = True
    root['semantic_group'] = name
    COLLECTIONS[name] = c
    ROOTS[name] = root


for name in ['00_Foundation', '10_Exterior_L0', '11_Exterior_Upper',
             '12_Facade_Detail', '20_Floor_L1', '21_Stair', '22_Rails',
             '23_Supports', '30_Rooms_L1', '31_Doors_L1', '32_Furniture_L1', '33_Ceilings_L1',
             '40_Reception_L0', '41_Furniture_L0', '42_Independent_Props',
             '43_Entrance_Doors', '44_Hanging_Landmark', '50_Roof', '51_Trusses',
             '60_Scale_Figures', '70_Alarm_Tower_Context', '71_Guardhouse_Context',
             '80_Labels', '90_Studio']:
    group(name)


def material(name, value, roughness=.83):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*value, 1)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*value, 1)
    b.inputs['Roughness'].default_value = roughness
    return m


WHITE = material('WB plaster clay', (.70, .71, .69))
TRIM = material('WB pale stone clay', (.84, .83, .78))
ROOF = material('WB roof clay', (.24, .28, .30))
WOOD = material('WB timber clay', (.40, .42, .40))
FURN = material('WB furniture clay', (.55, .57, .55))
FLOORMAT = material('WB floor clay', (.61, .62, .58))
DARK = material('WB inset clay', (.19, .23, .24))
GLASS = material('WB opaque glazing indicator', (.39, .52, .54))
SCALE = material('WB 1.75m scale figure', (.66, .41, .23))
LABEL = material('WB plan labels', (.13, .18, .20))

FURNITURE_CACHE = {}
FURNITURE_INSTANCES = []
FURNITURE_ROOTS = []
FURNITURE_MATS = {'wood':FURN,'wood_dark':WOOD,'steel':TRIM,'metal':FURN,
                  'inset':WOOD,'glass':TRIM,'paper':WHITE,'linen':TRIM,
                  'cloth':WOOD,'soil':DARK}
FURNITURE_MATS.update({k:FURN for k in ['redwood','brass','dark','dark_inset','blueglass','crystal','bottle',
    'pewter','ceramic','cork','terracotta','purple','stone','pale_stone','counter_stone','papers','notice','label','rug','inscription']})
FURNITURE_MATS.update({'brass':TRIM,'dark':DARK,'blueglass':GLASS,'crystal':GLASS,'papers':WHITE,'notice':WHITE})
FURNITURE_MATS.update({'tapestry':WOOD,'banner':WOOD,'rope':FURN,'soap':TRIM,'upholstery':WOOD,'welt':WOOD,'wax':WHITE,'wick':DARK,'iron':DARK})


def prop(kind, location, group_name='41_Furniture_L0', yaw=0, scale=(1,1,1)):
    """Independent roots, one shared mesh per material across same-type instances."""
    name='Guild_'+kind+'_'+str(len(FURNITURE_INSTANCES)+1).zfill(3)
    if kind not in FURNITURE_CACHE:
        builder=build_guestroom if kind in GUESTROOM else build_fitting if kind in TEXTILE_SANITARY else build_furnishing if kind in NEW_FURNISHINGS else build_furniture
        root,parts=builder(kind,COLLECTIONS[group_name],FURNITURE_MATS,'game',name)
        parts=bake_game_meshes(root,parts)
        if kind in GUESTROOM:rig_cabinet(root,parts,animate=False)
        FURNITURE_CACHE[kind]=(root,parts)
    else:
        original,original_parts=FURNITURE_CACHE[kind]
        root=original.copy();root.name=name;COLLECTIONS[group_name].objects.link(root)
        parts=[]
        for source in original_parts:
            o=source.copy();o.data=source.data;o.name=name+'_'+str(len(parts))
            o.parent=root;COLLECTIONS[group_name].objects.link(o);parts.append(o)
    root.parent=ROOTS[group_name];root.location=location;root.rotation_euler.z=math.radians(yaw);root.scale=scale
    root['semantic_group']=group_name
    root['asset_source']=('../guestroom_v1/' if kind in GUESTROOM else '../textiles_sanitary_v1/' if kind in TEXTILE_SANITARY else '../furnishings_v1/' if kind in NEW_FURNISHINGS else '../furniture_v1/')+'game/guild_'+kind+'.glb'
    root['whitebox_only']=True
    for o in parts:
        o['semantic_group']=group_name;o['whitebox_only']=True;OBJECTS.append(o)
    FURNITURE_ROOTS.append(root)
    FURNITURE_INSTANCES.append({'name':name,'asset_id':'guild_'+kind,'location_blender':list(location),
                                'yaw_degrees':yaw,'scale':list(scale),'semantic_group':group_name})
    return root


def register(o, name, g, mat, collision=True):
    o.name = name
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COLLECTIONS[g].objects.link(o)
    o.parent = ROOTS[g]
    if mat:
        o.data.materials.append(mat)
    o['whitebox_only'] = True
    o['semantic_group'] = g
    o['collision_review'] = collision
    OBJECTS.append(o)
    return o


def mesh(name, verts, faces, g, mat, collision=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    SC.collection.objects.link(o)
    return register(o, name, g, mat, collision)


def box(name, x, y, z, w, d, h, g, mat=WHITE, bevel=0, collision=True):
    assert min(w, d, h) > 0, (name, w, d, h)
    v = [(x + sx*w/2, y + sy*d/2, z + sz*h/2)
         for sz in [-1, 1] for sy in [-1, 1] for sx in [-1, 1]]
    o = mesh(name, v, [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                       (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)], g, mat, collision)
    if bevel:
        m = o.modifiers.new('Whitebox edge light', 'BEVEL')
        m.width = bevel
        m.segments = 2
        m = o.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
        m.keep_sharp = True
    return o


def boundsbox(name, x0, x1, y0, y1, z0, z1, g, mat=WHITE, **kw):
    return box(name, (x0+x1)/2, (y0+y1)/2, (z0+z1)/2,
               x1-x0, y1-y0, z1-z0, g, mat, **kw)


def cylinder(name, loc, radius, depth, g, mat, vertices=24, rotation=None, collision=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    o = register(bpy.context.object, name, g, mat, collision)
    if rotation:
        o.rotation_euler = rotation
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return o


def sphere(name, loc, size, g, mat, collision=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=loc)
    o = register(bpy.context.object, name, g, mat, collision)
    o.scale = size
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def beam(name, start, end, width, g, mat=WOOD, collision=True):
    a, b = Vector(start), Vector(end)
    o = box(name, 0, 0, 0, width, width, (b-a).length, g, mat, collision=collision)
    o.location = (a+b)/2
    o.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return o


def cut(o, cutter):
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new('Actual opening', 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.object = cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    OBJECTS.remove(cutter)
    bpy.data.objects.remove(cutter, do_unlink=True)


def prism(name, points, z0, z1, g, mat):
    n = len(points)
    return mesh(name, [(x, y, z) for z in [z0, z1] for x, y in points],
                [tuple(reversed(range(n))), tuple(range(n, 2*n))] +
                [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)], g, mat)


def wallx(name, x0, x1, y, thickness, height, holes, g, zbase=0):
    # Holes have local/global x bounds and absolute z bounds.
    cuts = sorted(set([x0, x1] + [v for h in holes for v in h[:2] if x0 < v < x1]))
    for a, b in zip(cuts, cuts[1:]):
        mid = (a+b)/2
        occupied = [(zbase, zbase+height)]
        for left, right, bottom, top in holes:
            if left <= mid <= right:
                occupied = [(lo, hi) for low, high in occupied
                            for lo, hi in [(low, min(high, bottom)), (max(low, top), high)] if hi-lo > .001]
        for lo, hi in occupied:
            boundsbox(name, a, b, y-thickness/2, y+thickness/2, lo, hi, g)


def wally(name, y0, y1, x, thickness, height, holes, g, zbase=0):
    made = len(OBJECTS)
    wallx(name, y0, y1, x, thickness, height, holes, g, zbase)
    for o in OBJECTS[made:]:
        for v in o.data.vertices:
            v.co.x, v.co.y = v.co.y, v.co.x
        # Coordinate swap reverses orientation.
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces)); bm.to_mesh(o.data); bm.free()


def outline_window(x, y, z, w, h, g, side=False):
    if side:
        for yy in [y-w/2, y+w/2]:
            box('Stone window jamb', x, yy, z+h/2, .65, .12, h+.18, g, TRIM)
        for zz in [z-.06, z+h+.06]:
            box('Stone window sill', x, y, zz, .68, w+.24, .12, g, TRIM)
        box('Window mullion', x, y, z+h/2, .08, .06, h, g, WOOD, collision=False)
        box('Window transom', x, y, z+h*.52, .08, w, .06, g, WOOD, collision=False)
    else:
        for xx in [x-w/2, x+w/2]:
            box('Stone window jamb', xx, y, z+h/2, .12, .65, h+.18, g, TRIM)
        for zz in [z-.06, z+h+.06]:
            box('Stone window sill', x, y, zz, w+.24, .68, .12, g, TRIM)
        box('Window mullion', x, y, z+h/2, .06, .08, h, g, WOOD, collision=False)
        box('Window transom', x, y, z+h*.52, w, .08, .06, g, WOOD, collision=False)


def rail(name, start, end, z=FLOOR, g='22_Rails', height=1.1):
    a, b = Vector((*start, z)), Vector((*end, z))
    beam(name+' top', a+Vector((0, 0, height)), b+Vector((0, 0, height)), .085, g)
    beam(name+' bottom', a+Vector((0, 0, .16)), b+Vector((0, 0, .16)), .07, g)
    n = max(1, math.ceil((b-a).length/.22))
    for i in range(n+1):
        p = a.lerp(b, i/n)
        beam(name+' baluster', p, p+Vector((0, 0, height)), .045, g)


def roof_z(y):
    return EAVE + (7-abs(y-7))*(RIDGE-EAVE)/7


def upper_wall(name, x0, x1, y0, y1):
    top = [CEILING for _ in range(4)]
    verts = [(x,y,FLOOR) for x,y in [(x0,y0),(x1,y0),(x1,y1),(x0,y1)]]
    verts += [(x,y,z) for (x,y),z in zip([(x0,y0),(x1,y0),(x1,y1),(x0,y1)],top)]
    return mesh(name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], '30_Rooms_L1',WHITE)


def text_floor(body, x, y, z, size=.42):
    cu = bpy.data.curves.new('Plan label', 'FONT'); cu.body = body
    cu.align_x = 'CENTER'; cu.size = size; cu.extrude = .001
    o = bpy.data.objects.new(body, cu); SC.collection.objects.link(o)
    o.location = (x,y,z)
    return register(o, body, '80_Labels', LABEL, False)


# Ground slab and approach. Ground floor walking datum is exactly z=0.
boundsbox('Guild foundation 32x14m', 0,32,0,14,-.3,0,'00_Foundation',FLOORMAT)
boundsbox('Entry upper step',12.6,19.4,-1.2,0,-.16,0,'00_Foundation',TRIM)
boundsbox('Entry lower step',12.3,19.7,-1.8,-1.2,-.32,-.16,'00_Foundation',TRIM)
front_windows = [3.5,7,10.5,21.5,25,28.5]
front_holes = [(x-.65,x+.65,.95,3.4) for x in front_windows]+[(14.4,17.6,0,3.35)]
wallx('Front L0',0,32,.25,.5,FLOOR,front_holes,'10_Exterior_L0')
wallx('Rear L0',0,32,13.75,.5,FLOOR,[(x-.65,x+.65,1.1,3.45) for x in [3.5,10,16]]+[(18.95,20.55,0,3.0)],'10_Exterior_L0')
for x in [.25,31.75]:
    wally('End wall L0',.5,13.5,x,.5,FLOOR,[(y-.65,y+.65,.95,3.4) for y in [3.5,6.5,9.5]],'10_Exterior_L0')
    for y in [3.5,6.5,9.5]: outline_window(x,y,.95,1.3,2.45,'10_Exterior_L0',True)
for x in front_windows: outline_window(x,.25,.95,1.3,2.45,'10_Exterior_L0')
for x in [3.5,10,16]: outline_window(x,13.75,1.1,1.3,2.35,'10_Exterior_L0')
# Split exterior above L1; removing upper geometry reveals the ground floor.
wallx('Front upper',0,32,.25,.5,EAVE-FLOOR,[(15.1,16.9,FLOOR,FLOOR+3.0)],'11_Exterior_Upper',FLOOR)
wallx('Rear upper',0,32,13.75,.5,EAVE-FLOOR,[(x-.55,x+.55,5.48,7.28) for x in [3.5,10,16,24,29.5]],'11_Exterior_Upper',FLOOR)
for x in [3.5,10,16,24,29.5]:outline_window(x,13.75,5.48,1.1,1.8,'11_Exterior_Upper')
for x in [18.89,20.61]:box('Rear entry jamb',x,13.88,1.52,.16,.60,3.12,'10_Exterior_L0',TRIM)
box('Rear entry lintel',19.75,13.88,3.08,1.90,.65,.16,'10_Exterior_L0',TRIM)
rear_door=box('Rear entry proposed leaf',19.75,13.76,1.49,1.57,.10,2.98,'43_Entrance_Doors',WOOD)
rear_door['door_pose']='closed';rear_door['door_hinge']=[18.96,13.76,0]
rear_door['reference_status']='U21 confirms secondary entrance, exact position is proposed'
box('Rear entrance canopy',19.75,14.33,3.38,2.50,1.12,.14,'12_Facade_Detail',WOOD)
for x in [18.67,20.83]:beam('Rear canopy bracket',(x,14.0,2.85),(x,14.75,3.3),.07,'12_Facade_Detail',WOOD)
for x in [.25,31.75]:
    wally('End upper',.5,13.5,x,.5,EAVE-FLOOR,[(y-.55,y+.55,5.48,7.28) for y in [3.5,6.5,10.6]],'11_Exterior_Upper',FLOOR)
    v = [(xx,y,z) for xx in [x-.25,x+.25] for y,z in [(0,EAVE),(14,EAVE),(7,RIDGE)]]
    mesh('End roof gable',v,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],'11_Exterior_Upper',WHITE)
    for y in [3.5,6.5,10.6]: outline_window(x,y,5.48,1.1,1.8,'11_Exterior_Upper',True)

# Editable slabs; complete stair opening, including the portion inside west wing.
for name,x0,x1,y0,y1 in [('West front',.5,7.4,.5,8.95),('West rear',.5,7.4,10.95,13.5),
                         ('Top landing',.5,3.0,8.95,10.95),('Rear gallery',7.4,21.75,11.0,13.5),
                         ('Guest wing',21.75,31.5,.5,13.5)]:
    boundsbox(name,x0,x1,y0,y1,4.23,FLOOR,'20_Floor_L1',FLOORMAT)
for name,x0,x1,y0,y1 in [('West ceiling',.5,7.4,.5,13.5),('Rear ceiling',7.4,21.75,11,13.5),
                         ('East ceiling',21.75,31.5,.5,13.5)]:
    boundsbox(name,x0,x1,y0,y1,CEILING,CEILING+.2,'33_Ceilings_L1',WHITE)
for i in range(28):
    # 27 treads at .30; the final .16 rise meets a 2.5m upper landing at x=3.
    if i == 27: break
    xright = 11.1-i*.3
    top=(i+1)*.16
    boundsbox('Timber tread %02d'%(i+1),xright-.3,xright,8.95,10.95,top-.055,top,'21_Stair',WOOD)
    boundsbox('Timber riser %02d'%(i+1),xright-.035,xright,8.95,10.95,max(0,top-.215),top-.055,'21_Stair',WOOD)
# Closed treads/risers on housed side strings and a central carriage. The walking
# profile is unchanged; the obsolete floor-to-tread solid blocks are removed.
for y in [8.89,9.95,11.01]:
    verts=[(x,yy,z) for yy in [y-.06,y+.06] for x,z in [(11.1,0),(3,4.32),(3,4.02),(10.54,0)]]
    mesh('Timber stair string',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'21_Stair',WOOD)
boundsbox('Top landing timber riser',2.97,3.0,8.95,10.95,4.265,FLOOR,'21_Stair',WOOD)
for y in [8.90,11.00]:
    beam('Stair handrail',(11.1,y,1.1),(3,y,5.58),.085,'22_Rails')
    for i in range(15):
        t=i/14; x=11.1-8.1*t; z=4.48*t
        beam('Stair baluster',(x,y,z),(x,y,z+1.1),.045,'22_Rails')
rail('Rear gallery guard',(7.4,11.0),(21.75,11.0))
rail('Upper stair opening rear guard',(3.05,11.0),(7.4,11.0))
rail('Upper stair opening front guard',(3.05,8.90),(7.4,8.90))
# The other edges of the void meet enclosed L1 room walls.
for x,y in [(7.4,1),(7.4,8.5),(7.4,11.2),(21.75,1),(21.75,8.5),(21.75,11.2),(13.1,11.2),(18.8,11.2)]:
    cylinder('Floor support post',(x,y,2.05),.18,4.1,'23_Supports',WOOD)
    box('Stone column foot',x,y,.15,.48,.48,.3,'23_Supports',TRIM)
for x in [7.3,21.85]:
    # Do not bridge the stair hole with a beam.
    for ya,yb in ([(.5,8.8),(11.1,13.5)] if x<10 else [(.5,13.5)]):
        box('Inner floor edge beam',x,(ya+yb)/2,4.07,.28,yb-ya,.32,'23_Supports',WOOD)
box('Rear gallery beam',14.575,11.2,4.07,14.35,.3,.32,'23_Supports',WOOD)
for x in [2.8,5.8,23.5,26.5,29.5]:
    for ya,yb in ([(.5,8.8),(11.1,13.5)] if x<7 else [(.5,13.5)]):
        box('Slab secondary joist',x,(ya+yb)/2,4.13,.14,yb-ya,.2,'23_Supports',WOOD)

# Room clear bounds follow A-02. Wall meshes live outside each clear rectangle.
def room(code, x0,x1,y0,y1,door_side,door_y):
    ROOMS.append(dict(code=code,bounds=[x0,x1,y0,y1],door=[x0 if door_side=='left' else x1,door_y,DOOR_W],door_side=door_side,door_height=DOOR_H,ceiling_clear=CEILING-FLOOR))
    for ya,yb in [(y0-.1,y0),(y1,y1+.1)]:
        # The continuous exterior already supplies this wall and its window.
        # A second coplanar lining z-fights and changes after render batching.
        if abs(ya-13.5)<.001:continue
        upper_wall(code+' end',x0-.1,x1+.1,ya,yb)
    for side,x in [('left',x0),('right',x1)]:
        if abs(x-31.5)<.001 or abs(x-.5)<.001:continue
        xa,xb=(x-.15,x) if side=='left' else (x,x+.15)
        o=upper_wall(code+' side',xa,xb,y0,y1)
        balcony_access = code=='01 MEETING' and side=='right'
        if side==door_side or balcony_access:
            if balcony_access: door_y=.72
            c=boundsbox('Door aperture',xa-.05,xb+.05,door_y,door_y+DOOR_W,FLOOR-.02,FLOOR+DOOR_H,'30_Rooms_L1')
            cut(o,c)
            # Park the leaf against the room wall. A 90-degree 1.6m leaf acted
            # as a camera baffle even after enlarging the opening.
            sign=1 if side=='left' else -1
            if code=='04 LINEN':
                # Small utility room: two folding pairs occupy 0.4m, not 1.6m.
                for end in [0,1]:
                    yy=door_y-.06 if end==0 else door_y+DOOR_W+.06
                    for part in [0,1]:
                        leaf=box(code+' folded leaf',x+sign*.21,yy+((.045 if end else -.045) if part else 0),FLOOR+(DOOR_H-.04)/2,.40,.035,DOOR_H-.04,'31_Doors_L1',WOOD)
                        leaf['door_hinge']=[x,yy,FLOOR]
                        leaf['door_pose']='folded_open'
            else:
                leaf=box(code+' door parked 180deg',x+sign*.07,door_y+DOOR_W+(DOOR_W-.02)/2,FLOOR+(DOOR_H-.04)/2,.055,DOOR_W-.02,DOOR_H-.04,'31_Doors_L1',WOOD)
                leaf['door_hinge']=[x,door_y+DOOR_W,FLOOR]
                leaf['door_pose']='parked_open_180'
            leaf['door_clear_width']=DOOR_W
    text_floor(code,(x0+x1)/2,y0+.4,FLOOR+.012,.38)


room('01 MEETING',3.05,7.25,.5,4.3,'left',.95)
room('02 OFFICE',3.05,7.25,4.5,8.7,'left',4.95)
for code,y in [('201 SINGLE',.5),('202 SINGLE',4.6)]: room(code,21.9,25.05,y,y+3.9,'right',y+.4)
for code,y in [('203 TWIN',.5),('204 TWIN',4.6)]: room(code,27.75,31.5,y,y+3.9,'left',y+.4)
room('04 LINEN',21.9,25.05,8.7,10.8,'right',8.9)
room('05 WASHROOM',27.75,31.5,8.7,13.5,'left',9.0)
# Actual opening from west corridor to upper landing remains unobstructed.
# Authored access from meeting room to the banner platform; not screenshot evidence.
boundsbox('Balcony access gallery',7.25,17.20,.50,2.42,4.23,FLOOR,'20_Floor_L1',FLOORMAT)
rail('Balcony access gallery guard',(7.4,2.42),(17.20,2.42))
rail('Balcony access gallery return',(17.20,2.42),(17.20,.5))
box('Balcony access edge beam',12.22,2.36,4.11,9.96,.20,.24,'23_Supports',WOOD)
for x in [10.4,16.8]:
    cylinder('Balcony access support',(x,2.30,2.05),.14,4.10,'23_Supports',WOOD)
    box('Balcony access support foot',x,2.30,.12,.34,.34,.24,'23_Supports',TRIM)


# U15/U22 reference furniture; room dimensions remain the approved camera plan.
for y in [.5,4.6]:
    group='32_Furniture_L1'
    prop('guest_bed',(24.15,y+2.73,FLOOR),group)
    prop('guest_nightstand',(23.17,y+3.61,FLOOR),group)
    prop('guest_candlestick',(23.17,y+3.61,FLOOR+.96),group)
    prop('guest_desk',(22.72,y+.42,FLOOR),group,yaw=180)
    prop('guest_chair',(22.72,y+.83,FLOOR),group)
    prop('guest_low_cabinet',(22.16,y+2.85,FLOOR),group,yaw=90)
    prop('guest_candle_sconce',(22.03,y+2.02,FLOOR+1.75),group,yaw=90)
    for x in [28.55,30.65]:prop('guest_bed',(x,y+2.73,FLOOR),group)
    prop('guest_nightstand',(29.60,y+3.61,FLOOR),group)
    prop('guest_candlestick',(29.60,y+3.61,FLOOR+.96),group)
    prop('guest_desk',(29.95,y+.42,FLOOR),group,yaw=180)
    prop('guest_chair',(29.95,y+.83,FLOOR),group)
    prop('guest_candle_sconce',(29.60,y+3.77,FLOOR+1.75),group)
prop('dining_table',(5.25,3.0,FLOOR),'32_Furniture_L1',scale=(2.2/2.4,1,1))
for x in [4.4,5.2,6]:
    for y in [2.25,3.75]: prop('stool',(x,y,FLOOR),'32_Furniture_L1')
prop('writing_desk',(5,7.9,FLOOR),'32_Furniture_L1')
for x in [4.0,5.1,6.2]:prop('storage_cabinet',(x,8.45,FLOOR),'32_Furniture_L1',scale=(1,.875,1))
prop('long_bench',(6.3,6.2,FLOOR),'32_Furniture_L1',yaw=90,scale=(2/2.4,1,1))
for x in [3.2,4.3,5.4]:prop('storage_cabinet',(x,13.15,FLOOR),'32_Furniture_L1',scale=(1,.875,1.6/1.8))
for x in [22.95,24.05]:prop('storage_cabinet',(x,10.5,FLOOR),'32_Furniture_L1')
for x in [27.85,29.65,31.25]:
    prop('privacy_screen',(x,12.65,FLOOR),'32_Furniture_L1',yaw=90)
prop('shower_tray',(28.7,12.65,FLOOR),'32_Furniture_L1')
prop('shower_column',(28.7,13.25,FLOOR+.08),'32_Furniture_L1')
prop('privy_seat',(30.5,12.85,FLOOR),'32_Furniture_L1')
prop('washstand',(30.35,9.90,FLOOR),'32_Furniture_L1',yaw=180)
for dx in [-.43,.43]:
    prop('wash_basin',(30.35+dx,9.935,FLOOR+.84),'32_Furniture_L1')
    prop('brass_faucet',(30.35+dx,9.625,FLOOR+.84),'32_Furniture_L1',yaw=180)
prop('wash_ewer',(30.35,9.90,FLOOR+.84),'32_Furniture_L1')
prop('soap_dish',(29.67,10.00,FLOOR+.84),'32_Furniture_L1')
prop('towel_rail',(31.37,10.6,FLOOR+1.05),'32_Furniture_L1',yaw=-90)

# Reception has four actual arched apertures and a separate staff access door.
reception=box('Registration window wall',26.6,10.9,2.115,9.8,.3,4.23,'40_Reception_L0')
# U16: board on the perpendicular return beneath the guest-wing gallery.
# Coordinates are a game-layout interpretation, not measured animation plans.
boundsbox('Reception timber return',21.66,21.82,6.1,10.9,0,4.23,'40_Reception_L0',WOOD)
def arch_cutter(cx,y,w,bottom,spring,depth,g):
    pts=[(cx-w/2,bottom),(cx+w/2,bottom)] + [(cx+w/2*math.cos(t*math.pi/20),spring+w/2*math.sin(t*math.pi/20)) for t in range(21)]
    n=len(pts)
    return mesh('Arched opening cutter',[(x,yy,z) for yy in [y-depth/2,y+depth/2] for x,z in pts],
                [tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],g,WHITE)

for x in [22.8,24.65,26.5,28.35]:
    cut(reception,arch_cutter(x,10.9,1.4,1.04,2.65,.7,'40_Reception_L0'))
    for xx in [x-.78,x+.78]: box('Arch window jamb',xx,10.68,1.85,.16,.22,1.65,'40_Reception_L0',TRIM)
    for i in range(20):
        t0=i*math.pi/20;t1=(i+1)*math.pi/20
        beam('Arch ring',(x+.79*math.cos(t0),10.65,2.65+.79*math.sin(t0)),
             (x+.79*math.cos(t1),10.65,2.65+.79*math.sin(t1)),.16,'40_Reception_L0',TRIM)
    box('Fanlight transom',x,10.88,2.65,1.4,.07,.06,'40_Reception_L0',WOOD)
    for t in [math.pi/4,math.pi/2,3*math.pi/4]:
        beam('Fanlight radial',(x,10.88,2.65),(x+.66*math.cos(t),10.88,2.65+.66*math.sin(t)),.04,'40_Reception_L0',WOOD,False)
cut(reception,boundsbox('Staff doorway',29.7,31.3,10.5,11.3,-.02,DOOR_H,'40_Reception_L0'))
for x in [22.8,24.65,26.5,28.35]:prop('registration_counter',(x,10.45,0),'40_Reception_L0',scale=(1.85/2.275,1,1))


def dining_table(x,y,small=False):
    prop('small_table' if small else 'dining_table',(x,y,0))
    for yy in [y-.8,y+.8]:
        prop('short_bench' if small else 'long_bench',(x,yy,0))


for x,y in [(7,4.2),(11,4.2),(8,7.4),(11.1,7.4)]: dining_table(x,y)
for x,y in [(7,4.2),(11,4.2),(8,7.4),(11.1,7.4)]:
    for dx in [-.65,.65]:
        prop('dining_plate',(x+dx,y-.18,.85))
        prop('tankard',(x+dx+.20,y+.13,.85))
    prop('serving_jug',(x,y,.85))
for x in [3.6,7,10.5]: dining_table(x,1.6,True)
prop('bar_counter',(1.1,6.8,0),yaw=90)
for y in [5.2,6.35,7.5]:prop('barrel',(1.2,y,1.12))
for y in [5.5,7.3]:prop('bar_stool',(2.05,y,0))
for kind,y in [('bottle_tall',5.65),('bottle_round',6.8),('bottle_squat',7.95)]:prop(kind,(1.38,y,1.12))
for y in [3.8,6.4]:
    prop('waiting_bench',(30.7,y+.95,0),yaw=-90)
prop('planter',(31.15,12.8,0),yaw=90)
prop('sloped_notice_stand',(22.35,6.0,0))
prop('round_notice_board',(29.3,8.5,0))
prop('quest_board_filled',(22.16,8.05,0),'42_Independent_Props',yaw=90)
# U05/U18: sword held in both hands, cloak and stepped plinth. This remains an
# user-approved Fab knight; retain the editable layered plinth below.
g='42_Independent_Props'
for z,w,h in [(.10,2.2,.2),(.28,1.98,.16),(.71,1.72,.70),(1.12,1.94,.12)]:
    box('Statue stepped plinth',16,7.5,z,w,w,h,g,TRIM,bevel=.025)
statue_root,statue_parts,statue_info=build_knight_statue(COLLECTIONS[g],FURN,height=3.15)
statue_root.parent=ROOTS[g];statue_root.location=(16,7.5,1.18)
statue_root['semantic_group']=g
for obj in statue_parts:obj['semantic_group']=g;OBJECTS.append(obj)
# The reference shows freestanding ornament panels, not partition walls.
# Two linked instances of the separately authored asset; front faces the entry.
panel_materials = {'board':FURN,'rose':WOOD,'trim':TRIM,'gold':TRIM}
panel_root, panel_parts = build_panel(COLLECTIONS['42_Independent_Props'],panel_materials,
                                     'Guild_decorative_panel_L','game')
panel_root.parent = ROOTS['42_Independent_Props']
panel_root.location = (13.0,7.5,0)
panel_root['semantic_group'] = '42_Independent_Props'
panel_root['asset_source'] = '../decorative_panel_v1/guild_statue_decorative_panel_game.glb'
for o in panel_parts:
    o['semantic_group'] = '42_Independent_Props'
    OBJECTS.append(o)
other_root = panel_root.copy();other_root.name = 'Guild_decorative_panel_R'
COLLECTIONS['42_Independent_Props'].objects.link(other_root)
other_root.location = (19.0,7.5,0)
for o in panel_parts:
    other = o.copy();other.data = o.data
    other.name = o.name.replace('_L_', '_R_');other.parent = other_root
    COLLECTIONS['42_Independent_Props'].objects.link(other)
    OBJECTS.append(other)
prop('registration_crystal',(24.65,10.4,1.10),'42_Independent_Props')
for x,y in [(12.8,2.7),(19.2,2.7),(13.1,6.65),(19.2,6.65),(4.3,5.6),(30,3)]:
    prop('hall_lantern',(x,y,0),'42_Independent_Props')
prop('entry_runner',(16,3.4,0),'42_Independent_Props')
for x in [12.5,19.5]:prop('round_planter',(x,1.5,0),'42_Independent_Props')
for x in [13.8,18.2]: cylinder('Entry timber post',(x,1.15,3.3),.32,6.6,'23_Supports',WOOD)
# Four soft sheets follow sloped rafter bays; their four corners have real
# suspension points. No patterns/textures are introduced in this revision.
for bay,(xa,xb) in enumerate([(7.35,12.65),(19.35,24.65)]):
    for back in [False,True]:
        ya,yb=(8.0,12.7) if back else (1.3,6.0)
        verts=[]
        for r in range(25):
            v=r/24;y=ya+(yb-ya)*v
            for c in range(29):
                u=c/28;x=xa+(xb-xa)*u
                z=roof_z(y)-.42-.75*math.sin(math.pi*u)*math.sin(math.pi*v)-.09*math.sin(u*10*math.pi)*math.sin(math.pi*v)
                verts.append((x,y,z))
        faces=[(r*29+c,r*29+c+1,(r+1)*29+c+1,(r+1)*29+c) for r in range(24) for c in range(28)]
        cloth=mesh('Slope cloth bay %s %s'%(bay,'rear' if back else 'front'),verts,faces,'44_Hanging_Landmark',WOOD,False)
        cloth['independent_prop']=True;cloth['reference']='U18';cloth['dimensions_are_proposed']=True
        cloth.modifiers.new('Cloth thickness','SOLIDIFY').thickness=.004
        for x,tx in [(xa,xa-.35),(xb,xb+.35)]:
            for y in [ya,yb]:
                beam('Slope cloth corner tie',(x,y,roof_z(y)-.42),(tx,y,roof_z(y)-.2),.018,'44_Hanging_Landmark',FURN,False)
                box('Slope cloth rafter clamp',tx,y,roof_z(y)-.2,.28,.09,.28,'44_Hanging_Landmark',DARK,collision=False)
for x in [13,19]:
    # Round-bottom long banners hung from existing tie beams, clear of the route.
    verts=[]
    for r in range(25):
        t=r/24
        for c in range(17):
            u=c/16;xx=(u-.5)*.88;bottom=5.2+.44*(1-math.sqrt(max(0,1-(2*u-1)**2)))
            verts.append((x+xx,3.5-.09*math.sin(math.pi*u)*math.sin(math.pi*t),8.18+(bottom-8.18)*t))
    faces=[(r*17+c,r*17+c+1,(r+1)*17+c+1,(r+1)*17+c) for r in range(24) for c in range(16)]
    cloth=mesh('Round bottom long banner',verts,faces,'44_Hanging_Landmark',WOOD,False)
    cloth['independent_prop']=True;cloth['reference']='U18'
    cloth.modifiers.new('Banner thickness','SOLIDIFY').thickness=.004
    beam('Banner crossbar',(x-.52,3.5,8.20),(x+.52,3.5,8.20),.035,'44_Hanging_Landmark',FURN,False)
    for dx in [-.34,.34]:beam('Banner suspension',(x+dx,3.5,8.20),(x,3.5,8.34),.016,'44_Hanging_Landmark',FURN,False)
# Relocate the inner wall textile clear of the new balcony opening.
prop('wall_tapestry',(10.0,.67,4.75),'44_Hanging_Landmark',yaw=180)
for x in [12.9,19.1]:prop('long_banner',(x,.71,2.85),'44_Hanging_Landmark',yaw=180)
# Door leaves are open and exported separately; not baked into wall collision.
build_main_doors(globals())

# Main pitched roof and timber truss envelopes.
front_roof=mesh('Main front roof', [(-.45,-.45,roof_z(-.45)),(32.45,-.45,roof_z(-.45)),(32.45,7,RIDGE),(-.45,7,RIDGE)],[(0,1,2,3)],'50_Roof',ROOF)
back_roof=mesh('Main back roof',[(-.45,7,RIDGE),(32.45,7,RIDGE),(32.45,14.45,roof_z(14.45)),(-.45,14.45,roof_z(14.45))],[(0,1,2,3)],'50_Roof',ROOF)
for o in [front_roof,back_roof]:
    bpy.context.view_layer.objects.active=o
    m=o.modifiers.new('Roof thickness','SOLIDIFY');m.thickness=.18
    bpy.ops.object.modifier_apply(modifier=m.name)


def cross_gable(cx, width, eave, peak, front, name, rose=False, rear=False):
    made=len(OBJECTS)
    left,right=cx-width/2,cx+width/2
    ye=(eave-EAVE)*7/(RIDGE-EAVE);yp=(peak-EAVE)*7/(RIDGE-EAVE)
    cut_front=front-.6 if front<0 else front+.09
    hole=prism('Roof join cut',[(left,cut_front),(right,cut_front),(right,ye),(cx,yp),(left,ye)],5.8,15,'50_Roof',WHITE)
    if rear:
        for vertex in hole.data.vertices:vertex.co.y=14-vertex.co.y
        bm=bmesh.new();bm.from_mesh(hole.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(hole.data);bm.free()
    cut(back_roof if rear else front_roof,hole)
    # Explicit closed roof wedges; intersect the main roof by 12cm at valleys.
    # Avoid open surfaces plus Solidify in a multi-roof Boolean assembly.
    for side in [-1,1]:
        edge=cx+side*width/2
        top=[(edge,front-.08,eave+.04),(cx,front-.08,peak+.04),
             (cx,yp+.12,peak+.04),(edge,ye+.12,eave+.04)]
        pts=top+[(x,y,z-.18) for x,y,z in top]
        mesh(name+' roof '+('left' if side<0 else 'right'),pts,
             [(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'50_Roof',ROOF)
        beam(name+' valley flashing',(edge,ye,eave+.08),(cx,yp,peak+.08),.075,'50_Roof',TRIM,False)
    for x in [left,right]:
        cheek=mesh(name+' side cheek',[(x,front,roof_z(front)),(x,front,eave),(x,ye,eave)],[(0,1,2)],'12_Facade_Detail',WHITE)
        m=cheek.modifiers.new('Cheek thickness','SOLIDIFY');m.thickness=.18
    bottom=EAVE if rose else (6.7 if front<0 else roof_z(front)+.02)
    v=[(x,y,z) for y in [front+.1,front+.4] for x,z in [(left,bottom),(right,bottom),(right,eave),(cx,peak),(left,eave)]]
    face=mesh(name+' gable',v,[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],'12_Facade_Detail',WHITE)
    if rose:
        c=cylinder('Rose window cut',(cx,front+.25,9.4),1.16,1,'12_Facade_Detail',WHITE,48,(math.pi/2,0,0))
        cut(face,c)
        # Round aperture continues through the higher central front wall where applicable.
        for i in range(40):
            t0=i*2*math.pi/40;t1=(i+1)*2*math.pi/40
            beam('Rose window rim',(cx+1.24*math.cos(t0),front+.05,9.4+1.24*math.sin(t0)),
                 (cx+1.24*math.cos(t1),front+.05,9.4+1.24*math.sin(t1)),.16,'12_Facade_Detail',TRIM)
        for i in range(16):
            t=i*2*math.pi/16
            beam('Rose window tracery',(cx,front+.09,9.4),(cx+1.13*math.cos(t),front+.09,9.4+1.13*math.sin(t)),.045,'12_Facade_Detail',WOOD,False)
    else:
        z=7.15 if front<0 else roof_z(front)+.20
        h=2.20 if front<0 else 1.35
        cut(face,boundsbox('Dormer actual aperture',cx-.48,cx+.48,front-.1,front+.6,z,z+h,'12_Facade_Detail'))
        if front<0:
            for wall in list(COLLECTIONS['11_Exterior_Upper'].objects):
                if wall.type=='MESH' and wall.name.startswith('Front upper'):
                    cut(wall,boundsbox('Dormer wall opening',cx-.48,cx+.48,-.4,.8,z,z+h,'11_Exterior_Upper'))
        outline_window(cx,front+.2,z,.96,h,'12_Facade_Detail')
        for zz in [z+h*.25,z+h*.75]:box('Dormer extra transom',cx,front+.17,zz,.96,.08,.04,'12_Facade_Detail',WOOD,collision=False)
    beam(name+' verge left',(left,front-.04,eave),(cx,front-.04,peak),.15,'12_Facade_Detail',TRIM)
    beam(name+' verge right',(cx,front-.04,peak),(right,front-.04,eave),.15,'12_Facade_Detail',TRIM)
    if front>0:
        apron=[(xx,yy,roof_z(yy)+.04) for xx,yy in [(left-.06,front-.10),(right+.06,front-.10),(right+.06,front+.22),(left-.06,front+.22)]]
        mesh(name+' sill flashing',apron,[(0,1,2,3)],'50_Roof',ROOF,False)
    if rear:
        from mathutils import Matrix
        for obj in OBJECTS[made:]:
            if obj.type!='MESH':continue
            transform=obj.matrix_world.copy()
            for vertex in obj.data.vertices:
                point=transform@vertex.co;point.y=14-point.y;vertex.co=point
            obj.matrix_world=Matrix.Identity(4)
            bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()


cross_gable(16,5.8,10.8,13.8,-.62,'Central frontage',True)
for x in [3.5,10.2,21.8,28.5]: cross_gable(x,2.75,9.7,11.9,-.2,'Secondary gable')
for x in [7.0,25.0]: cross_gable(x,1.65,11.55,12.85,2.0,'Small dormer')
for x in [3.5,10.0,16.0]:cross_gable(x,1.8,11.55,12.85,2.0,'Rear dormer',rear=True)
# Actual rooflights over internal room 202 and its single-room neighbour.
for x,y in [(23.65,2.75),(23.65,6.3)]:
    target=front_roof if y<=7 else back_roof
    c=boundsbox('Rooflight opening',x-.35,x+.35,y-.55,y+.55,5.5,15,'50_Roof')
    cut(target,c)
    for ceiling_obj in list(COLLECTIONS['33_Ceilings_L1'].objects):
        if ceiling_obj.type=='MESH' and ceiling_obj.name.startswith('East ceiling'):
            cut(ceiling_obj,boundsbox('Ceiling rooflight aperture',x-.35,x+.35,y-.55,y+.55,CEILING-.1,CEILING+.3,'33_Ceilings_L1'))
    # Real light-well sides, never a painted opening in an opaque ceiling.
    corners=[(x-.35,y-.55),(x+.35,y-.55),(x+.35,y+.55),(x-.35,y+.55)]
    for j in range(4):
        a,b=corners[j],corners[(j+1)%4]
        mesh('Rooflight well',[(a[0],a[1],CEILING),(b[0],b[1],CEILING),(b[0],b[1],roof_z(b[1])-.1),(a[0],a[1],roof_z(a[1])-.1)],[(0,1,2,3)],'33_Ceilings_L1',WHITE)
    z=roof_z(y)
    verts=[(xx,yy,roof_z(yy)+.025) for xx,yy in corners]
    mesh('Room daylight rooflight',verts,[(0,1,2,3)],'50_Roof',GLASS,False)
    for i in range(4): beam('Rooflight frame',verts[i],verts[(i+1)%4],.07,'50_Roof',TRIM,False)
for x in [3.5,12,29.3]:
    box('Chimney envelope',x,7.4,14.3,.65,.65,3.0,'50_Roof',TRIM)
    box('Chimney cap',x,7.4,15.8,.86,.86,.18,'50_Roof',WHITE)
box('Front balcony platform',16,-1.10,FLOOR-.125,6.2,2.4,.25,'12_Facade_Detail',TRIM)
for x in [13.05,18.95]:box('Central gable pier',x,-.16,5.4,.35,.82,10.8,'12_Facade_Detail',TRIM)
rail('Facade platform rail',(13.2,-2.25),(18.8,-2.25),FLOOR,'12_Facade_Detail',1.05)
for x in [13.2,18.8]: rail('Facade side rail',(x,-2.25),(x,-.15),FLOOR,'12_Facade_Detail',1.05)
for x in [15.04,16.96]:box('Balcony door stone jamb',x,-.04,FLOOR+1.52,.16,.62,3.12,'12_Facade_Detail',TRIM)
box('Balcony door lintel',16,-.04,FLOOR+3.08,2.10,.66,.16,'12_Facade_Detail',TRIM)
for x in [15.56,16.44]:
    hinge_x=15.1 if x<16 else 16.9
    pivot=bpy.data.objects.new('Balcony door hinge '+('left' if x<16 else 'right'),None)
    SC.collection.objects.link(pivot);register(pivot,pivot.name,'31_Doors_L1',None,False)
    pivot.location=(hinge_x,.22,FLOOR);pivot['door_hinge']=[hinge_x,.22,FLOOR]
    pivot['door_pose']='closed';pivot['open_angle_degrees']=90 if x<16 else -90
    start=len(OBJECTS)
    leaf=box('Balcony door closed leaf',x,.22,FLOOR+1.49,.87,.10,2.98,'31_Doors_L1',WOOD)
    leaf['door_pose']='closed';leaf['door_hinge']=[15.1 if x<16 else 16.9,.22,FLOOR]
    leaf['reference_status']='authored behind obscuring banner; user requested functional access'
    for z in [FLOOR+.3,FLOOR+1.5,FLOOR+2.7]:box('Balcony door panel rail',x,.15,z,.75,.045,.065,'31_Doors_L1',TRIM)
    for piece in OBJECTS[start:]:
        piece.parent=pivot;piece.location-=pivot.location
build_heraldry(globals())
build_exterior(globals())
beam('Central finial',(16,-.48,13.7),(16,-.48,14.65),.07,'12_Facade_Detail',WOOD)
for y in [.25,13.75]:
    spans=[(0,32)] if y>7 else [(0,2.10),(4.90,8.8),(11.6,13.05),(18.95,20.4),(23.2,27.1),(29.9,32)]
    for a,b in spans:box('Roof wall plate',(a+b)/2,y,EAVE+.12,b-a,.6,.24,'51_Trusses',WOOD)
for x in [1,7,13,19,25,31]:
    beam('Roof tie beam',(x,.55,8.45),(x,13.45,8.45),.22,'51_Trusses')
    beam('Principal rafter',(x,.55,roof_z(.55)-.2),(x,7,RIDGE-.3),.22,'51_Trusses')
    beam('Principal rafter',(x,7,RIDGE-.3),(x,13.45,roof_z(13.45)-.2),.22,'51_Trusses')
    beam('King post',(x,7,8.45),(x,7,RIDGE-.3),.18,'51_Trusses')
# Independent reference-led crown, horns and hanging skeleton.
LANDMARKS = install_landmarks(globals())


def figure(x,y,z=0):
    sphere('1.75m scale head',(x,y,z+1.60),(.12,.12,.15),'60_Scale_Figures',SCALE)
    box('1.75m scale torso',x,y,z+1.15,.39,.22,.63,'60_Scale_Figures',SCALE,bevel=.1,collision=False)
    for dx in [-.11,.11]:
        beam('Scale leg',(x+dx,y,z+.06),(x+dx,y,z+.87),.12,'60_Scale_Figures',SCALE,False)
        box('Scale foot',x+dx,y-.035,z+.045,.14,.25,.09,'60_Scale_Figures',SCALE,collision=False)
    for dx in [-.27,.27]: beam('Scale arm',(x+dx,y,z+.82),(x+dx*.8,y,z+1.43),.09,'60_Scale_Figures',SCALE,False)


for x,y,z in [(16,-2.8,-.32),(21,6,0),(10.05,9.95,.64),(26.4,6.4,FLOOR),(14,12.25,FLOOR)]: figure(x,y,z)

# Separate context masses follow A-03 only; no invented connecting corridor.
g='70_Alarm_Tower_Context'; cx,cy=23,42
alarm_shaft=cylinder('Alarm tower context shaft',(cx,cy,12),2.55,24,g,WHITE,48)
install_shooting_slits(alarm_shaft)
g='71_Guardhouse_Context'
box('Guardhouse context mass',8.5,30,3.2,13,10,6.4,g,WHITE)
mesh('Guardhouse roof context',[(2,25,6.4),(15,25,6.4),(15,35,6.4),(2,35,6.4),(2,30,10.8),(15,30,10.8)],
     [(0,1,5,4),(4,5,2,3),(0,4,3),(1,2,5),(3,2,1,0)],g,ROOF)

# Persist evidence and expected route heights for independent mesh review.
routes = {
 'main_entry_to_reception': [(16,-2.7,-.32),(16,-1.5,-.16),(16,-.6,0),(16,3.5,0),(20.5,4.6,0),(24,5.5,0),(24,8.3,0)],
 'entry_to_stair': [(16,3.5,0),(14.45,4.8,0),(14.45,9.95,0),(11.5,9.95,0)],
 'stair': [(11.5,9.95,0)]+[(10.95-i*.3,9.95,(i+1)*.16) for i in range(27)]+[(1.7,9.95,FLOOR)],
 'upper_main': [(1.7,9.95,FLOOR),(1.7,12.25,FLOOR),(21,12.25,FLOOR),(26.4,12.25,FLOOR),(26.4,1.7,FLOOR)],
 'office_access': [(1.7,9.95,FLOOR),(1.7,5.75,FLOOR),(4.3,5.75,FLOOR)],
 'meeting_access': [(1.7,5.75,FLOOR),(1.7,1.75,FLOOR),(4.2,1.75,FLOOR)],
 'balcony_access': [(4.2,1.55,FLOOR),(6.7,1.55,FLOOR),(7.8,1.55,FLOOR),(12.0,1.95,FLOOR),(14.6,1.95,FLOOR),(16,1.6,FLOOR),(16,-1.2,FLOOR),(14.1,-1.2,FLOOR)],
 'guest_201': [(26.4,1.7,FLOOR),(23.8,1.7,FLOOR)],
 'guest_202': [(26.4,5.8,FLOOR),(23.8,5.8,FLOOR)],
 'guest_203': [(26.4,1.7,FLOOR),(29.1,1.7,FLOOR)],
 'guest_204': [(26.4,5.8,FLOOR),(29.1,5.8,FLOOR)],
 'linen': [(26.4,9.7,FLOOR),(23.8,9.7,FLOOR)],
 'washroom': [(26.4,9.8,FLOOR),(29.0,9.8,FLOOR)],
 'reception_staff': [(24,8.3,0),(24,9.3,0),(30.5,9.3,0),(30.5,12,0)],
}

# Over-wide timber wall plates pierced the tiled eaves; keep them on masonry.
ROOF_WALL_JOINERY = fit_roof_wall_plates(OBJECTS)
(OUT/'roof_wall_joinery_review.json').write_text(json.dumps(ROOF_WALL_JOINERY,ensure_ascii=False,indent=2),encoding='utf8')
# Studio and seven reproducible views, keeping geometry independent of previews.
box('Studio floor',16,18,-.42,180,180,.2,'90_Studio',material('Studio warm grey',(.48,.49,.46)),collision=False)
SC.world.use_nodes=True
background=next(n for n in SC.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value=(.68,.75,.82,1)
background.inputs[1].default_value=.45
bpy.ops.object.light_add(type='SUN',location=(10,-20,35));sun=bpy.context.object
register(sun,'Studio sun','90_Studio',None,False);sun.rotation_euler=(.5,-.45,-.5);sun.data.energy=2.4;sun.data.angle=.12
for loc,power,size in [((15,5,12),1700,9),((27,5,3.9),650,5),((5,6,3.9),550,5),((10,-12,20),2200,15),((26.4,4,7.1),180,2),((26.4,10,7.1),180,2)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object
    register(o,'Review soft fill','90_Studio',None,False);o.data.energy=power;o.data.shape='DISK';o.data.size=size
bpy.ops.object.camera_add();CAM=bpy.context.object;SC.camera=CAM
register(CAM,'Review camera','90_Studio',None,False)
SC.render.engine='CYCLES';SC.cycles.samples=24;SC.cycles.use_denoising=True
SC.render.resolution_x=1600;SC.render.resolution_y=1000;SC.render.resolution_percentage=100
SC.view_settings.view_transform='AgX'
SC.render.image_settings.file_format='PNG'
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='OPTIX';prefs.get_devices()
    found=False
    for dev in prefs.devices:
        dev.use=dev.type=='OPTIX';found=found or dev.use
    if found:SC.cycles.device='GPU'
except Exception: pass


def visible(hidden=(),context=False,labels=False):
    for g,c in COLLECTIONS.items():
        c.hide_render=g in hidden or (g.startswith(('70_','71_')) and not context) or (g=='80_Labels' and not labels)
        c.hide_viewport=c.hide_render


def camera(eye,target,ortho=0):
    CAM.location=eye
    direction=Vector(target)-CAM.location
    CAM.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
    CAM.data.type='ORTHO' if ortho else 'PERSP'
    CAM.data.ortho_scale=ortho or 45
    CAM.data.lens=23 if not ortho else 50
    CAM.data.clip_end=500


def render(name,eye,target,ortho=0,hidden=(),context=False,labels=False):
    visible(hidden,context,labels);camera(eye,target,ortho)
    doors=[o for o in OBJECTS if o.name.startswith('Main door hinge')]
    old_angles=[o.rotation_euler.z for o in doors]
    if name in ['01_exterior','16_front_elevation','17_rear_exterior','18_entry_detail']:
        for o in doors:o.rotation_euler.z=0
    exterior=name in ['01_exterior','16_front_elevation','17_rear_exterior','18_entry_detail','19_balcony_door']
    # Large interior area lights intersect dormer slopes and create false-looking
    # bright roof patches in exterior renders; only illuminate interiors with them.
    for o in OBJECTS:
        if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=exterior
    SC.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    for o,angle in zip(doors,old_angles):o.rotation_euler.z=angle


visible();camera((48,-43,30),(16,6,6),45)
# Save default exterior and preconfigured semantic collections; source stays editable.
for o in OBJECTS:
    if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=True
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=47
            area.spaces.active.region_3d.view_location=(16,7,5)
            area.spaces.active.clip_end=500
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_whitebox.blend'),compress=True)
# glTF exports preserve group nodes. No studio or annotation geometry in the model.
for c in COLLECTIONS.values():c.hide_viewport=False
bpy.ops.object.select_all(action='DESELECT')
for o in OBJECTS:
    if not o['semantic_group'].startswith(('70_','71_','80_','90_')): o.select_set(True)
for g,o in ROOTS.items():
    if not g.startswith(('70_','71_','80_','90_')):o.select_set(True)
for o in [panel_root,other_root,statue_root]+FURNITURE_ROOTS:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'axel_guild_whitebox.glb'),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
bpy.ops.object.select_all(action='DESELECT')
for o in OBJECTS:
    if o['semantic_group'].startswith(('70_','71_')):o.select_set(True)
for g,o in ROOTS.items():
    if g.startswith(('70_','71_')):o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'guild_neighbour_context.glb'),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
visible()
deps=bpy.context.evaluated_depsgraph_get();triangles=0;counts={}
for o in OBJECTS:
    if o.type!='MESH' or o['semantic_group'].startswith(('70_','71_','80_','90_')):continue
    ev=o.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles();triangles+=len(me.loop_triangles);ev.to_mesh_clear()
    counts[o['semantic_group']]=counts.get(o['semantic_group'],0)+1
manifest={'stage':'whitebox_v13_roof_wall_plates','generator':'tools/build_axel_guild_whitebox.py',
          'roof_wall_joinery':ROOF_WALL_JOINERY,
          'dimensions_m':{'footprint':[32,14],'upper_floor':FLOOR,'roof_eave':EAVE,'roof_ridge':RIDGE,'main_entry_width':3.2,
                          'upper_ceiling_clear':CEILING-FLOOR,'upper_ceiling_bottom':CEILING,'roof_tie_clear':8.45-.11-FLOOR,
                          'door_aperture':[DOOR_W,DOOR_H],'door_leaf_clear_width':DOOR_W,
                          'office_corridor':2.4,'guest_corridor':2.4,'rear_gallery_clear':2.4575,
                          'central_void_nominal':[7.4,21.75,.5,11.0]},
          'rooms':ROOMS,'route_probes_xyz_blender':routes,'stairs':{'rises':28,'rise':.16,'treads':27,'going':.30,'width':2.0,'upper_landing_depth':2.5},
          'mesh_count_by_group':counts,'triangles_evaluated':triangles,
          'furniture_instances':FURNITURE_INSTANCES,
          'furniture_asset_source':'../furniture_v1/manifest.json',
          'additional_furnishing_source':'../furnishings_v1/manifest.json',
          'textiles_sanitary_source':'../textiles_sanitary_v1/manifest.json',
          'guestroom_source':'../guestroom_v1/manifest.json',
          'furniture_shared_meshes':True,
          'fab_statue':dict(statue_info,location_blender=[16,7.5,1.18],source='../fab_knight_statue_v1/provenance.json',independent_parts=2),
          'exterior_revision':{'reference_images':['U01','U19','U20','U21'],
              'large_front_gables':4,'small_front_dormers':2,'rear_dormers':3,
              'balcony_door_clear_m':[1.8,3.0],'balcony_floor_m':FLOOR,'balcony_depth_m':2.4,
              'balcony_access':'Authored meeting-room door and front gallery; not directly visible in reference.',
              'banner':'Independent shield-bottom cloth beyond rail; no texture.',
              'rear_entry':'U21 supports secondary entry, location x19.75 is proposed.',
              'roof_join_reference':'https://copper.org/applications/architecture/arch_dhb/arch-details/flashings_copings/dormers.php',
              'preview_lighting':'Interior area lights disabled for exterior; they crossed roof planes and created misleading bright patches.'},
          'geometry_revision':{'reference_images':['U05','U16','U18','U24'],
              'quest_board_location':[22.16,8.05,0],'quest_board_yaw':90,
              'reception_windows_x':[22.8,24.65,26.5,28.35],
              'sloped_cloths':4,'round_bottom_banners':2,
              'stair_material_intent':'timber; no textures','tread_thickness':.055,
              'statue':'User-approved Fab Knight Statue sword variant; neutral clay; full source geometry retained',
              'skeleton':'Independent 13-pair rib cage, 18 vertebrae, socketed skull, separate jaw and V-cable armature; fantasy anatomy provisional',
              'construction_reference':'https://stair-parts.com/parts-of-a-staircase-diagram-glossary-list-of-stair-part-names/'},
          'decorative_panels':{'asset_id':'guild_statue_decorative_panel','independent_instances':2,
                               'locations_blender':[[13.0,7.5,0],[19.0,7.5,0]],'front_axis_blender':'-Y',
                               'body_thickness_m':.06,'frame_thickness_m':.10,
                               'structural_wall':False,'source':'../decorative_panel_v1/guild_statue_decorative_panel_game.glb'},
          'deviations':['Eave raised from 6.6 to 8.2m; ridge retained at 14m, reducing pitch to about 40 degrees for L1 clearance.',
                        'Statue-side boxes replaced by arched independent decorative panels; dimensions and rear anchors are proposed.',
                        'L1 rooms and corridors have a real 3.6m-clear ceiling; roof ties are above it.',
                        'Room proportions adjusted for 2.4m corridors, 2m stair and 2.5m top landing; 4 guest rooms / 6 beds retained.',
                        'Door apertures enlarged to 1.6x3.0m specifically for the normal 18-degree third-person orbit.',
                        'Rooflights added as proposed daylight for inner guest rooms; not animation evidence.',
                        'Reception partially beneath upper floor; beam underside approx 3.91m.',
                        'Alarm tower crown replaced with U23 components; 8 horns/windows/dormers and dimensions authored. Shaft and guardhouse remain context masses; interiors unconfirmed.'],
          'design_completion_authorized':True,
          'landmark_assets':['guild_hanging_skeleton','guild_alarm_crown','guild_alarm_conical_roof','guild_alarm_ring_supports','guild_alarm_horn'],
          'runtime_catalog_published':False,'user_map_modified':False,
          'exports':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.glb')}}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('WHITEBOX_EXPORTED',triangles,'triangles',flush=True)
if not ARGS.no_render:
    shots=set(ARGS.shots.split(','))
    if 'exterior' in shots:render('01_exterior',(48,-43,30),(16,6,6),45)
    if 'front' in shots:render('16_front_elevation',(16,-50,7),(16,6,7),38)
    if 'rear' in shots:render('17_rear_exterior',(-26,48,26),(16,7,6),45)
    if 'entry' in shots:render('18_entry_detail',(23,-15,8),(16,0,5),14)
    if 'balcony' in shots:
        banner_parts=[o for o in OBJECTS if o.get('banner_assembly',False)]
        for o in banner_parts:o.hide_render=True
        render('19_balcony_door',(20,-12,8),(16,0,5.8),9)
        for o in banner_parts:o.hide_render=False
    if 'cutaway' in shots:render('02_cutaway',(47,-36,34),(16,6.5,3),42,('50_Roof','51_Trusses','33_Ceilings_L1','11_Exterior_Upper','12_Facade_Detail','44_Hanging_Landmark'))
    if 'ground' in shots:render('03_ground_floor',(16,7,40),(16,7,0),37,('50_Roof','51_Trusses','33_Ceilings_L1','11_Exterior_Upper','12_Facade_Detail','20_Floor_L1','30_Rooms_L1','31_Doors_L1','32_Furniture_L1','22_Rails','23_Supports','60_Scale_Figures','44_Hanging_Landmark'))
    if 'guestroom' in shots:render('12_guestroom',(24.25,.95,6.20),(23.4,3.35,5.35),0)
    if 'upper' in shots:render('04_upper_floor',(16,7,42),(16,7,FLOOR),37,('50_Roof','51_Trusses','33_Ceilings_L1','11_Exterior_Upper','12_Facade_Detail','44_Hanging_Landmark'),labels=True)
    if 'hall' in shots:render('05_hall',(29,2.3,1.7),(7,8,3.8))
    if 'gallery' in shots:render('06_upper_gallery',(26.4,12.5,6.13),(26.4,2,5.8))
    if 'site' in shots:render('07_site_context',(75,-65,75),(16,22,11),94,context=True)
    if 'reception' in shots:render('08_reception',(27.5,4.5,2.1),(23.8,9.3,2),0)
    if 'textiles' in shots:render('10_hanging_textiles',(16,2.6,5.4),(16,8,10.2),0)
    if 'stairs' in shots:render('14_timber_stair',(12.5,6.2,3.8),(6,9.9,2.5),0)
    if 'overview' in shots:
        visible();camera((16,1.8,4.5),(16,7.5,7.5));CAM.data.lens=18
        SC.render.filepath=str(OUT/'15_hall_geometry.png');bpy.ops.render.render(write_still=True)
    if 'washroom' in shots:render('11_washroom',(28.0,9.85,6.9),(30,12.0,5.5),0)
    if 'panels' in shots:render('09_statue_decorative_panels',(16,1.8,2.3),(16,7.5,2.0))
    if 'panels_side' in shots:render('10_decorative_panels_side',(22,1.9,3.4),(16,7.5,1.9))
visible();camera((48,-43,30),(16,6,6),45)
print('WHITEBOX_DONE',OUT,flush=True)
