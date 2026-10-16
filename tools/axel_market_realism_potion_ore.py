"""CPU-only replacement goods. Load a COPY of the master, then apply(key, collection).

Does not save, render, export, alter shelves/bins, or touch production resources.
Blender units are metres, Z up. See docs/axel_market_realism_potion_ore_20261016.md.
"""
import math
import random
import bpy
import bmesh
from mathutils import Vector, Matrix, noise

VERSION = 4
PREFIX = 'MarketRealism'


def _bounds(obj):
    points = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    return Vector(tuple(min(v[i] for v in points) for i in range(3))), Vector(tuple(max(v[i] for v in points) for i in range(3)))


def _material(name, color, roughness=.8, metallic=0):
    name = PREFIX + '_' + name
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    m.diffuse_color = (*color, 1)
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    m['authoring_bake_required'] = True
    return m


def _grain_material(name, low, high, scale, bump_m, roughness=.8):
    m = _material(name, high, roughness)
    nt = m.node_tree
    if nt.nodes.get('Metre grain'):
        return m
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    coord = nt.nodes.new('ShaderNodeNewGeometry')
    n = nt.nodes.new('ShaderNodeTexNoise'); n.name = 'Metre grain'
    n.inputs['Scale'].default_value = scale
    n.inputs['Detail'].default_value = 3
    nt.links.new(coord.outputs['Position'], n.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMixRGB')
    mix.inputs[1].default_value = (*low, 1); mix.inputs[2].default_value = (*high, 1)
    nt.links.new(n.outputs['Fac'], mix.inputs[0]); nt.links.new(mix.outputs[0], p.inputs['Base Color'])
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .32; bump.inputs['Distance'].default_value = bump_m
    nt.links.new(n.outputs['Fac'], bump.inputs['Height']); nt.links.new(bump.outputs[0], p.inputs['Normal'])
    return m


def _optical_material(name, tint, rough, alpha=.06):
    m = _material(name, tint, rough)
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Transmission Weight'].default_value = 1
    p.inputs['IOR'].default_value = 1.46
    p.inputs['Alpha'].default_value = alpha
    m.diffuse_color = (*tint, alpha)
    m.surface_render_method = 'DITHERED'
    m.use_backface_culling = True
    m['authoring_bake_required'] = False
    m['authoring_optics_spec'] = {'transmittance': list(tint), 'roughness': rough}
    return m


def _mesh(name, verts, faces, material, collection, part, specimen, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces); data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new(name, data); collection.objects.link(obj)
    data.materials.append(material)
    uv = data.uv_layers.new(name='Authoring projection UV')
    for face in data.polygons:
        face.use_smooth = smooth
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][axis]
        for li in face.loop_indices:
            co = data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv = co[a], co[b]
    obj['market_realism_version'] = VERSION
    obj['market_goods_part'] = part
    obj['market_specimen_id'] = specimen
    obj['rmmo_export_group'] = 'GoodsOpaque'
    return obj


def _optical(obj, material, group):
    obj['rmmo_export_group'] = group
    obj['rmmo_tinted_glass'] = {'version': 1, 'materials': {material.name: material['authoring_optics_spec'].to_dict()}}


def _lathe(name, profile, segments, material, col, part, specimen, origin):
    vs, fs, rings = [], [], []
    for radius, z in profile:
        ring = []
        for j in range(1 if radius == 0 else segments):
            angle = j * math.tau / segments
            ring.append(len(vs)); vs.append((radius * math.cos(angle), radius * math.sin(angle), z))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(segments):
            k = (j + 1) % segments
            if len(a) == 1:
                fs.append((a[0], b[k], b[j]))
            elif len(b) == 1:
                fs.append((a[j], a[k], b[0]))
            else:
                fs.append((a[j], a[k], b[k], b[j]))
    o = _mesh(name, vs, fs, material, col, part, specimen, True)
    o.location = origin
    return o


def _radius_at(profile, z):
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1-r0) * (z-z0)/(z1-z0)
    return profile[-1][0]


def _label_patch(name, center, r, h, col, material, sid, umin, umax, vmin, vmax, depth, nx=16, ny=3):
    # u is polar angle about the front (-Y); v is relative bottle height.
    vs, fs = [], []
    for layer in range(2):
        for j in range(ny+1):
            v = vmin + (vmax-vmin)*j/ny
            for i in range(nx+1):
                u = umin+(umax-umin)*i/nx
                rad = r+.0006+layer*depth
                vs.append((center.x+rad*math.sin(u), center.y-rad*math.cos(u), center.z+v*h))
    size = (nx+1)*(ny+1)
    for j in range(ny):
        for i in range(nx):
            q=j*(nx+1)+i
            fs.extend([(q,q+1,q+nx+2,q+nx+1),(q+size,q+nx+1+size,q+nx+2+size,q+1+size)])
    boundary = list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
    for a,b in zip(boundary,boundary[1:]+boundary[:1]): fs.append((a,b,b+size,a+size))
    return _mesh(name,vs,fs,material,col,'label' if depth>.0001 else 'label_ink',sid)


def _potions(col):
    old = [o for o in col.all_objects if o.name.startswith('Replaceable potion bottle')]
    assert len(old)==16, 'Expected original 16 bottles; apply only once to a freshly loaded master.'
    old.sort(key=lambda o: (_bounds(o)[0].y,_bounds(o)[0].x))
    specs=[]
    for o in old:
        lo,hi=_bounds(o)
        kind=next(k for k in ['Emerald','Amethyst','Amber'] if k in o.data.materials[0].name)
        specs.append((Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z)),(hi.x-lo.x)/2,hi.z-lo.z,kind))
    for o in list(col.all_objects):
        if o.name.startswith(('Replaceable potion bottle','Bottle stopper','Bottle paper label')): bpy.data.objects.remove(o,do_unlink=True)
    clear=_optical_material('Bottle_ClearGlass',(.94,.975,.96),.11,.025)
    liquids={k:_optical_material('Liquid_'+k,c,.10,.24) for k,c in [('Emerald',(.48,.83,.61)),('Amethyst',(.76,.52,.85)),('Amber',(.96,.76,.38))]}
    cork=_grain_material('Cork',(.105,.058,.025),(.31,.205,.095),430,.0007,.88)
    paper=_grain_material('RagPaper',(.48,.42,.30),(.78,.73,.59),780,.00018,.91)
    ink=_material('LabelIronGallInk',(.041,.027,.017),.88)
    report=[]
    for i,(center,r,h,kind) in enumerate(specs):
        sid='potion_%02d'%i; wall=.0022
        outer=[(.59*r,0),(.84*r,.013*h),(.96*r,.04*h),(r,.10*h),(r,.49*h),(.96*r,.54*h),(.76*r,.64*h),(.49*r,.71*h),(.335*r,.78*h),(.335*r,.925*h),(.41*r,.943*h),(.425*r,.972*h),(.40*r,h)]
        inner=[(max(rad-wall,.001),max(z,.0042)) for rad,z in reversed(outer[2:])]
        # Finish above the bottom; no collapsed rings or coincident liquid/glass faces.
        profile=[(0,0)]+outer+inner+[(.65*r,.0042),(0,.0042)]
        shell=_lathe(sid+'_glass',profile,40,clear,col,'glass_shell',sid,center)
        _optical(shell,clear,'Glass_Clear')
        shell['wall_thickness_m']=wall; shell['base_thickness_m']=.0042
        fill=(.56+(i%4)*.025)*h
        inside=[(rad-wall-.0008,max(z,.005)) for rad,z in outer if .03*h<=z<fill and rad>wall]
        fill_radius=_radius_at(outer,fill)-wall-.0008
        liquid_profile=[(0,.005),(.63*r,.005)]+inside+[(fill_radius,fill+.0012),(fill_radius*.94,fill+.00035),(fill_radius*.82,fill),(0,fill)]
        liquid=_lathe(sid+'_liquid_'+kind,liquid_profile,40,liquids[kind],col,'liquid',sid,center)
        _optical(liquid,liquids[kind],'Liquid_'+kind)
        liquid['fill_height_m']=fill; liquid['meniscus_rise_m']=.0012
        cr=.335*r-wall
        stopper=_lathe(sid+'_cork',[(0,h-.018),(cr*.92,h-.018),(cr,h-.014),(cr*1.015,h+.019),(cr*.93,h+.023),(0,h+.023)],28,cork,col,'cork',sid,center)
        _label_patch(sid+'_paper',center,r,h,col,paper,sid,-.49,.49,.275,.465,.00035)
        # A small emblem and uneven short ink strokes, not a repeated printed-white slab.
        offset=r+.00040
        for j in range(3):
            a=-.32+(i%3)*.02; b=.28-(j%2)*.08; v=.30+j*.025
            _label_patch(sid+'_ink_%d'%j,center,offset,h,col,ink,sid,a,b,v,v+.005,.00006,nx=9,ny=1)
        _label_patch(sid+'_ink_vertical',center,offset,h,col,ink,sid,-.018,.018,.385,.444,.00006,nx=1,ny=2)
        _label_patch(sid+'_ink_cross',center,offset,h,col,ink,sid,-.12,.12,.410,.418,.00006,nx=7,ny=1)
        report.append({'id':sid,'kind':kind,'center_blender':list(center),'radius_m':r,'height_m':h,'wall_m':wall,'fill_m':fill,'meniscus_m':.0012})
    return {'bottles':report,'counts':{'bottles':16,'liquids':16,'corks':16,'labels':16},'transparency_groups':['Glass_Clear','Liquid_Emerald','Liquid_Amethyst','Liquid_Amber']}


def _rock_material(name, copper=False):
    m=_grain_material(name,(.032,.038,.032),(.105,.12,.10),310,.00075,.87)
    nt=m.node_tree; p=next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    if nt.nodes.get('Sparse broken veins'):return m
    coord=nt.nodes.new('ShaderNodeNewGeometry')
    # A narrow, distorted isosurface band creates a vein; stochastic gates break
    # its continuity. Unlike DistanceToEdge it cannot trace every closed cell.
    broad=nt.nodes.new('ShaderNodeTexNoise');broad.name='Sparse broken veins';broad.inputs['Scale'].default_value=17;broad.inputs['Detail'].default_value=2;broad.inputs['Roughness'].default_value=.7
    nt.links.new(coord.outputs['Position'],broad.inputs['Vector'])
    centered=nt.nodes.new('ShaderNodeMath');centered.operation='SUBTRACT';centered.inputs[1].default_value=.49
    nt.links.new(broad.outputs['Fac'],centered.inputs[0])
    absolute=nt.nodes.new('ShaderNodeMath');absolute.operation='ABSOLUTE';nt.links.new(centered.outputs[0],absolute.inputs[0])
    ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.003;ramp.color_ramp.elements[0].color=(1,1,1,1)
    ramp.color_ramp.elements[1].position=.012;ramp.color_ramp.elements[1].color=(0,0,0,1)
    nt.links.new(absolute.outputs[0],ramp.inputs[0])
    grain=nt.nodes.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=115;grain.inputs['Detail'].default_value=3
    nt.links.new(coord.outputs['Position'],grain.inputs['Vector'])
    gate=nt.nodes.new('ShaderNodeValToRGB');gate.color_ramp.elements[0].position=.44;gate.color_ramp.elements[0].color=(0,0,0,1);gate.color_ramp.elements[1].position=.63;gate.color_ramp.elements[1].color=(1,1,1,1)
    nt.links.new(grain.outputs['Fac'],gate.inputs[0])
    mask=nt.nodes.new('ShaderNodeMath');mask.operation='MULTIPLY';nt.links.new(ramp.outputs[0],mask.inputs[0]);nt.links.new(gate.outputs[0],mask.inputs[1])
    old_color=p.inputs['Base Color'].links[0].from_socket
    mix=nt.nodes.new('ShaderNodeMixRGB');mix.inputs[2].default_value=((.27,.17,.045,1) if copper else (.20,.20,.165,1))
    nt.links.new(old_color,mix.inputs[1]);nt.links.new(mask.outputs[0],mix.inputs[0]);nt.links.new(mix.outputs[0],p.inputs['Base Color'])
    if copper:
        scale=nt.nodes.new('ShaderNodeMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=.74
        nt.links.new(mask.outputs[0],scale.inputs[0]);nt.links.new(scale.outputs[0],p.inputs['Metallic'])
        rough=nt.nodes.new('ShaderNodeMapRange');rough.inputs['To Min'].default_value=.87;rough.inputs['To Max'].default_value=.43
        nt.links.new(mask.outputs[0],rough.inputs[0]);nt.links.new(rough.outputs[0],p.inputs['Roughness'])
    return m


def _fractured(name,lo,hi,seed,material,col,sid,part='fractured_host'):
    rng=random.Random(seed);bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=3,radius=1)
    shift=Vector((seed*.17,seed*.11,seed*.07))
    for v in bm.verts:
        direction=v.co.normalized()
        v.co*=1+.14*noise.noise_vector(direction*3.7+shift).x+.045*noise.noise_vector(direction*12+shift).y
    for j in range(4):
        n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1))).normalized()
        result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=n*rng.uniform(.60,.83),plane_no=n,clear_outer=True,clear_inner=False)
        boundary=[e for e in bm.edges if e.is_boundary]
        if boundary:
            filled=bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
            for f in filled['faces']:f.smooth=False
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.verts.ensure_lookup_table();bm.verts.index_update()
    mn=Vector(tuple(min(v.co[i] for v in bm.verts) for i in range(3)));mx=Vector(tuple(max(v.co[i] for v in bm.verts) for i in range(3)))
    for v in bm.verts:
        v.co=Vector(tuple(lo[i]+(v.co[i]-mn[i])/(mx[i]-mn[i])*(hi[i]-lo[i]) for i in range(3)))
    vs=[tuple(v.co) for v in bm.verts];fs=[tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free();o=_mesh(name,vs,fs,material,col,part,sid)
    for f in o.data.polygons:f.use_smooth=len(f.vertices)<=4
    return o


def _crystal(name,lo,hi,seed,material,col,sid):
    rng=random.Random(seed)
    # Beryl: six-sided prism and basal termination, with a narrow edge bevel.
    verts=[];faces=[];rotation=rng.uniform(0,math.tau)
    for z,r,phase in [(-1,.72,0),(-.82,1,0),(.80,1,0),(.91,.90,0),(1,.72,.015)]:
        for j in range(6):
            a=j*math.tau/6+rotation+phase;verts.append((r*math.cos(a),r*math.sin(a),z))
    faces.append(tuple(reversed(range(6))))
    for row in range(4):
        for j in range(6):k=(j+1)%6;faces.append((row*6+j,row*6+k,(row+1)*6+k,(row+1)*6+j))
    faces.append(tuple(range(24,30)))
    rot=Matrix.Rotation(rng.uniform(-.35,.35),4,'X') @ Matrix.Rotation(rng.uniform(-.35,.35),4,'Y')
    points=[rot@Vector(v) for v in verts]
    mn=Vector(tuple(min(v[i] for v in points) for i in range(3)));mx=Vector(tuple(max(v[i] for v in points) for i in range(3)))
    verts=[tuple(lo[i]+(v[i]-mn[i])/(mx[i]-mn[i])*(hi[i]-lo[i]) for i in range(3)) for v in points]
    o=_mesh(name,verts,faces,material,col,'beryl_hex_prism',sid)
    _optical(o,material,'Glass_Aquamarine')
    return o


def _crystal_lamella(name,lo,hi,seed,material,col,sid):
    """One buried mineral flake, not a round opaque bead inside every gem."""
    rng=random.Random(seed);span=hi-lo;count=rng.randrange(7,10)
    c=(lo+hi)*.5+Vector((span.x*rng.choice((-1,1))*.10,span.y*rng.choice((-1,1))*.11,span.z*rng.uniform(-.08,.09)))
    rx=span.x*rng.uniform(.075,.10);ry=span.y*rng.uniform(.035,.055)
    thickness=min(span)*rng.uniform(.003,.005)
    rot=Matrix.Rotation(rng.uniform(-.8,.8),4,'Z') @ Matrix.Rotation(rng.uniform(.35,1.05),4,'X') @ Matrix.Rotation(rng.uniform(-.55,.55),4,'Y')
    outline=[]
    for j in range(count):
        angle=math.tau*j/count+rng.uniform(-.12,.12);radius=rng.uniform(.68,1)
        outline.append(Vector((math.cos(angle)*rx*radius,math.sin(angle)*ry*radius,0)))
    verts=[tuple(c+rot@(p+Vector((0,0,side*thickness*.5)))) for side in (-1,1) for p in outline]
    faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
    for j in range(count):
        k=(j+1)%count;faces.append((j,k,k+count,j+count))
    o=_mesh(name,verts,faces,material,col,'crystal_inclusion',sid)
    o['inclusion_design']='Sparse eccentric dark mineral lamella, not emissive; project supplementary design'
    o['lamella_thickness_m']=thickness
    return o


def _ores(col):
    chunks=[o for o in col.all_objects if o.name.startswith('Replaceable mineral chunk')]
    assert len(chunks)==30,'Expected 30 original mineral specimens; apply once to a fresh master.'
    chunks.sort(key=lambda o:o.location.x)
    specs=[]
    for i,o in enumerate(chunks):
        lo,hi=_bounds(o);specs.append((lo,hi,i//10))
    old_inclusions=[o for o in col.all_objects if o.name.startswith('Copper mineral inclusion')]
    assert len(old_inclusions)==10
    for o in chunks+old_inclusions:bpy.data.objects.remove(o,do_unlink=True)
    dark=_rock_material('CharcoalHostQuartzVeins')
    copper=_rock_material('CopperBearingHost',True)
    blue=_optical_material('AquamarineCrystal',(.56,.80,.90),.19,.20)
    inclusion=_grain_material('CrystalMineralLamellae',(.025,.035,.032),(.07,.09,.08),420,.00005,.72)
    report=[]
    for i,(lo,hi,bin_index) in enumerate(specs):
        sid='ore_%02d'%i
        if bin_index<2:
            o=_fractured(sid+'_host',lo,hi,10981+i,copper if bin_index==1 else dark,col,sid)
        else:
            o=_crystal(sid+'_crystal',lo,hi,10981+i,blue,col,sid)
            # A small opaque host at the broken base gives a physical inclusion;
            # it remains inside the same original specimen's bounds.
            span=hi-lo
            _fractured(sid+'_matrix',lo+Vector((span.x*.12,span.y*.12,0)),Vector((hi.x-span.x*.12,hi.y-span.y*.12,lo.z+span.z*.24)),20981+i,dark,col,sid,'crystal_matrix')
            # Most specimens stay optically clean. A few contain thin, subdued
            # mineral flakes at varied offsets; no repeated central white core.
            if i in (20,23,27,28):
                _crystal_lamella(sid+'_internal_lamella',lo,hi,30981+i,inclusion,col,sid)
        o['ore_bin']=bin_index
        report.append({'id':sid,'bin':bin_index,'old_bounds_min':list(lo),'old_bounds_max':list(hi)})
    return {'specimens':report,'counts':{'specimens':30,'dark':10,'copper_host':10,'aquamarine':10},'transparency_groups':['Glass_Aquamarine']}


def apply(asset_key, collection):
    """Replace only original CONTENTS goods and return authoring/audit metadata.

    Keep the returned group metadata when merging/exporting. Explicit optical
    contracts belong to mesh extras; material authoring props alone do nothing
    at runtime. Opaque materials require root's PBR bake before glTF export.
    """
    if asset_key not in ('potion','ore'):raise ValueError(asset_key)
    col=collection if collection.name.endswith('_CONTENTS') else next((c for c in collection.children_recursive if c.name.endswith('_CONTENTS')),None)
    if col is None:raise ValueError('Missing original CONTENTS collection')
    bpy.context.view_layer.update()
    result=_potions(col) if asset_key=='potion' else _ores(col)
    bpy.context.view_layer.update()
    result.update({'version':VERSION,'asset_key':asset_key,'collection':col.name,'coordinates':'Blender metres Z-up; original master offset preserved','project_supplementary_design':True,'optics':'Current rmmo_tinted_glass multiplication + dielectric reflection; not volumetric refraction or caustics','gpu_review':'pending','publication':'not performed'})
    return result
