"""CPU-only source module for the two market goods collections.

Entry point: apply('pottery'|'scroll', appended_variant_collection).
All edits stay inside its CONTENTS child. Never save/export/render from here.
Blender procedural Base Color/Roughness/Normal must be baked by the assembler.
No clearcoat, displacement, or Blender-only optical effect is required.
"""
import math
import random
import bpy
import numpy as np
from mathutils import Vector

VERSION = 4
TAU = math.tau


def _bounds(objects):
    points = [o.matrix_world @ Vector(p) for o in objects for p in o.bound_box]
    return ([min(p[k] for p in points) for k in range(3)],
            [max(p[k] for p in points) for k in range(3)])


def _mesh(collection, name, vertices, faces, materials, uv=None, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    for material in materials:
        data.materials.append(material)
    layer = data.uv_layers.new(name='GoodsUV')
    for polygon in data.polygons:
        polygon.use_smooth = smooth
        for li in polygon.loop_indices:
            vi = data.loops[li].vertex_index
            layer.data[li].uv = uv[vi] if uv else (vertices[vi][0], vertices[vi][1])
    obj['rmmo_market_goods_revision'] = VERSION
    obj['rmmo_project_supplement'] = True
    return obj


def _material(name, color, rough_min, rough_max, micro_distance, paper=False):
    material = bpy.data.materials.new('MarketRealism_' + name)
    material.use_nodes = True
    material.diffuse_color = (*color, 1)
    tree = material.node_tree
    p = next(node for node in tree.nodes if node.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = (rough_min + rough_max) / 2
    p.inputs['Metallic'].default_value = 0
    p.inputs['Coat Weight'].default_value = 0
    p.inputs['Specular IOR Level'].default_value = .22 if paper else .38
    coord = tree.nodes.new('ShaderNodeTexCoord')
    macro = tree.nodes.new('ShaderNodeTexNoise')
    macro.inputs['Scale'].default_value = 31 if paper else 18
    macro.inputs['Detail'].default_value = 3
    macro.inputs['Roughness'].default_value = .67
    tree.links.new(coord.outputs['Object'], macro.inputs['Vector'])
    ramp = tree.nodes.new('ShaderNodeValToRGB')
    ramp.name = 'BAKE_BASE_COLOR_variation'
    ramp.color_ramp.elements[0].position = .18
    ramp.color_ramp.elements[0].color = (*(max(0, c * .78) for c in color), 1)
    ramp.color_ramp.elements[1].position = .82
    ramp.color_ramp.elements[1].color = (*(min(.95, c * 1.13) for c in color), 1)
    tree.links.new(macro.outputs['Fac'], ramp.inputs[0])
    tree.links.new(ramp.outputs['Color'], p.inputs['Base Color'])
    micro = tree.nodes.new('ShaderNodeTexNoise')
    micro.name = 'BAKE_MICRO_HEIGHT'
    micro.inputs['Scale'].default_value = 630 if paper else 920
    micro.inputs['Detail'].default_value = 2
    tree.links.new(coord.outputs['Object'], micro.inputs['Vector'])
    if paper:
        stretch = tree.nodes.new('ShaderNodeVectorMath')
        stretch.operation = 'MULTIPLY'
        stretch.inputs[1].default_value = (1, .18, 1)
        tree.links.new(coord.outputs['Object'], stretch.inputs[0])
        tree.links.new(stretch.outputs[0], micro.inputs['Vector'])
    rough = tree.nodes.new('ShaderNodeMapRange')
    rough.name = 'BAKE_ROUGHNESS'
    rough.inputs['To Min'].default_value = rough_min
    rough.inputs['To Max'].default_value = rough_max
    tree.links.new(micro.outputs['Fac'], rough.inputs['Value'])
    tree.links.new(rough.outputs[0], p.inputs['Roughness'])
    bump = tree.nodes.new('ShaderNodeBump')
    bump.name = 'BAKE_TANGENT_NORMAL'
    bump.inputs['Strength'].default_value = .36
    bump.inputs['Distance'].default_value = micro_distance
    tree.links.new(micro.outputs['Fac'], bump.inputs['Height'])
    tree.links.new(bump.outputs['Normal'], p.inputs['Normal'])
    material['rmmo_bake_channels'] = 'Base Color; Roughness; tangent Normal; Metallic=0; Coat=0; alpha=1'
    material['rmmo_micro_height_m'] = micro_distance
    return material


def _hermite_profile(points, subdivisions=4):
    """Monotone cubic radius against height; avoids faceted shoulders/overshoot."""
    zs = [p[0] for p in points]
    rs = [p[1] for p in points]
    slopes = [(rs[i+1]-rs[i])/(zs[i+1]-zs[i]) for i in range(len(points)-1)]
    tangents = [slopes[0]]
    for a, b in zip(slopes, slopes[1:]):
        tangents.append(0 if a*b <= 0 else 2*a*b/(a+b))
    tangents.append(slopes[-1])
    result = []
    for i in range(len(points)-1):
        dz = zs[i+1]-zs[i]
        for step in range(subdivisions):
            t = step/subdivisions
            r = ((2*t**3-3*t*t+1)*rs[i] + (t**3-2*t*t+t)*dz*tangents[i]
                 + (-2*t**3+3*t*t)*rs[i+1] + (t**3-t*t)*dz*tangents[i+1])
            result.append((r, zs[i]+dz*t))
    result.append((rs[-1], zs[-1]))
    return result


def _pot(collection, index, bounds, materials):
    low, high = bounds
    cx, cy = (low[0]+high[0])/2, (low[1]+high[1])/2
    base, height = low[2], high[2]-low[2]
    radius = (high[0]-low[0])*.497
    wall = .0055
    lip = .0042
    neck = radius*(.55 + .025*math.sin(index*1.9))
    points = [(height*.025, radius*.67), (height*.10, radius*.79),
              (height*.26, radius*.97), (height*.43, radius),
              (height*.60, radius*.94), (height*.73, radius*.79),
              (height*.86, neck), (height*.92, neck*.98),
              (height-lip, neck+lip)]
    outer = _hermite_profile(points, 3)
    profile = [(0, 0), (radius*.58, 0), (radius*.65, height*.008)] + outer
    profile += [(neck + lip*math.cos(t*math.pi/6), height-lip+lip*math.sin(t*math.pi/6)) for t in range(1,7)]
    inner = [(max(.01, r-wall), z) for r,z in reversed(_hermite_profile(points, 2)[:-1]) if .014 < z < height*.93]
    profile += [(neck-lip, height*.94)] + inner
    profile += [(radius*.57, .014), (0, .014)]
    vertices, faces, uv, rings = [], [], [], []
    n = 48
    for j,(r,z) in enumerate(profile):
        ring = []
        for k in range(1 if r == 0 else n):
            a = k*TAU/n
            # Sub-mm hand-thrown irregularity, no repeatable large scallops.
            perturb = .00024*(math.sin(a*3+index*.8+z*11)+.35*math.sin(a*7-index*.9))
            rr = r if r == 0 else r+perturb*math.sin(math.pi*z/height)
            ring.append(len(vertices))
            vertices.append((cx+rr*math.cos(a), cy+rr*math.sin(a), base+z))
            uv.append((k/n, j/(len(profile)-1)))
        rings.append(ring)
    for row,(a,b) in enumerate(zip(rings,rings[1:])):
        for k in range(n):
            if len(a)==1:face=(a[0],b[(k+1)%n],b[k])
            elif len(b)==1:face=(a[k],a[(k+1)%n],b[0])
            else:face=(a[k],a[(k+1)%n],b[(k+1)%n],b[k])
            faces.append(face)
    obj = _mesh(collection, 'Goods_Pottery_%02d'%index, vertices, faces, materials)
    # Correct cylindrical seam per-loop; profile path unfolds exterior/lip/interior.
    layer = obj.data.uv_layers.active
    for p in obj.data.polygons:
        us=[]
        for li in p.loop_indices:
            vi=obj.data.loops[li].vertex_index; us.append(uv[vi][0])
        wraps=max(us)-min(us)>.5
        for li,u in zip(p.loop_indices,us):
            vi=obj.data.loops[li].vertex_index
            layer.data[li].uv=(u+1 if wraps and u<.5 else u,uv[vi][1])
        z=sum(vertices[v][2] for v in p.vertices)/len(p.vertices)-base
        # Three jars have a dipped shoulder/interior glaze, four stay entirely bare.
        if index in (1,3,5) and z > height*(.58+.018*math.sin(p.index*.07+index)):
            p.material_index=1
    obj['goods_kind']='wheel_thrown_earthenware'
    obj['wall_nominal_m']=wall
    obj['rim_radius_m']=lip
    obj['glazed_region']='upper shoulder and inside' if index in (1,3,5) else 'none'
    return obj


def _ink_mask():
    """Original, unreadable quill-like marks; no font, copied manuscript or relief."""
    size=1024
    field=np.zeros((size,size),dtype=np.float32)
    rng=random.Random(161016)
    def stroke(x0,y0,x1,y1,width,opacity):
        xmin=max(0,int((min(x0,x1)-width*3)*size));xmax=min(size,int((max(x0,x1)+width*3)*size)+1)
        ymin=max(0,int((min(y0,y1)-width*3)*size));ymax=min(size,int((max(y0,y1)+width*3)*size)+1)
        if xmax<=xmin or ymax<=ymin:return
        yy,xx=np.mgrid[ymin:ymax,xmin:xmax]/size
        dx=x1-x0;dy=y1-y0;length=max(dx*dx+dy*dy,1e-9)
        t=np.clip(((xx-x0)*dx+(yy-y0)*dy)/length,0,1)
        dist=np.sqrt((xx-x0-t*dx)**2+(yy-y0-t*dy)**2)
        coverage=np.exp(-((dist/max(width,.0005))**4))*opacity
        field[ymin:ymax,xmin:xmax]=np.maximum(field[ymin:ymax,xmin:xmax],coverage)
    # The dedicated atlas gives the front about 500 px width, followed by a
    # steep in-game viewing angle. Fewer larger marks retain actual ink at that
    # scale instead of averaging the manuscript into a near-blank surface.
    for row in range(14):
        baseline=.14+row*.050+rng.uniform(-.003,.003)
        x=.105+rng.uniform(-.005,.005)
        end=.89-rng.uniform(.0,.11) if row%5!=4 else .57+rng.random()*.18
        while x < end:
            w=rng.uniform(.016,.025);h=rng.uniform(.026,.035)
            opacity=rng.uniform(.86,.98);weight=rng.uniform(.0010,.0013)
            # Original mixed quill gestures, not a repeated row of identical marks.
            gesture=rng.randrange(5)
            if gesture==0:
                poly=[(0,0),(.20,1),(.54,.12),(.82,.84),(1,.16)]
            elif gesture==1:
                poly=[(.84,.78),(.42,1),(.08,.75),(.04,.25),(.45,.05),(.92,.35)]
            elif gesture==2:
                poly=[(.11,.08),(.24,1.15),(.25,.54),(.68,.71),(.89,.45),(.80,.05),(1,.14)]
            elif gesture==3:
                poly=[(.08,.75),(.45,1),(.84,.78),(.74,.48),(.18,.37),(.24,.03),(.90,.07)]
            else:
                poly=[(.13,.04),(.29,.94),(.39,.58),(.87,.62),(.97,.15)]
            for a,b in zip(poly,poly[1:]):
                stroke(x+w*a[0],baseline+h*a[1],x+w*b[0],baseline+h*b[1],
                       weight*rng.uniform(.90,1.05),opacity*rng.uniform(.90,1))
            if rng.random()>.81:stroke(x+w*.22,baseline+h*1.25,x+w*.3,baseline+h*1.22,weight,.82)
            x+=w+rng.uniform(.003,.006)
            if rng.random()<.22:x+=rng.uniform(.009,.018)
    image=bpy.data.images.new('MarketRealism_OriginalFadedManuscriptMask',width=size,height=size,alpha=False)
    image.colorspace_settings.name='Non-Color'
    pixels=np.ones((size,size,4),dtype=np.float32)
    pixels[:,:,:3]=field[:,:,None]
    image.pixels.foreach_set(pixels.ravel());image.update();image.pack()
    image['purpose']='Original faded dark quill ink; 14 irregular rows; baked flat, no raised ink geometry'
    image['source_stroke_width_px_range']='approximately 2.0-2.7 at 1024, before individual quill pressure'
    return image


def _written_material(paper):
    written=paper.copy();written.name='MarketRealism_WrittenParchment'
    tree=written.node_tree;p=next(node for node in tree.nodes if node.type == 'BSDF_PRINCIPLED')
    tex=tree.nodes.new('ShaderNodeTexImage');tex.image=_ink_mask();tex.name='ORIGINAL_INK_MASK'
    uv=tree.nodes.new('ShaderNodeUVMap');uv.uv_map='GoodsUV'
    tree.links.new(uv.outputs['UV'],tex.inputs['Vector'])
    original=p.inputs['Base Color'].links[0].from_socket
    mix=tree.nodes.new('ShaderNodeMixRGB');mix.name='BAKE_BASE_COLOR_WITH_FLAT_INK'
    tree.links.new(tex.outputs['Color'],mix.inputs[0]);tree.links.new(original,mix.inputs[1])
    mix.inputs[2].default_value=(.018,.009,.003,1)
    tree.links.new(mix.outputs[0],p.inputs['Base Color'])
    return written


def _roll(collection,index,center,paper,binding):
    rng=random.Random(380+index)
    radius=.045+rng.uniform(-.003,.003)
    # Original back row floated over the counter. Seat both rows on the existing
    # 72cm-deep counter with a small gap; preserve nine rolls and their X positions.
    x,y,_=center
    y=-.30 if y>-.29 else -.62
    # The cord's outer radius is r + 1.4mm + 1.7mm: seat the cord itself on wood.
    z=1.009+radius+.0031
    length=.286+rng.uniform(-.008,.008)
    angle=rng.uniform(-.045,.045)
    def position(r,a,v):
        px=r*math.cos(a);py=(v-.5)*length+.00045*math.sin(a*2+index)*(2*v-1)
        return (x+px*math.cos(angle)-py*math.sin(angle),y+px*math.sin(angle)+py*math.cos(angle),z+r*math.sin(a))
    turns=12;thickness=.00045
    samples=[]
    for turn in range(turns):
        segments=24 if turn<6 else 32 if turn<10 else 40
        samples.extend((turn+j/segments)/turns for j in range(segments))
    samples.append(1.0);steps=len(samples)-1
    vertices=[];uv=[];faces=[]
    for side in [0,1]:
        for t in samples:
            a=t*TAU*turns+index*.74
            r=radius*.63+(radius-radius*.63)*t-side*thickness
            for v in [0,1]:
                vertices.append(position(r,a,v));uv.append((t,v))
    half=(steps+1)*2
    for j in range(steps):
        q=j*2
        faces.extend([(q,q+2,q+3,q+1),(half+q+1,half+q+3,half+q+2,half+q),
                      (q,half+q,half+q+2,q+2),(q+3,half+q+3,half+q+1,q+1)])
    faces.extend([(0,1,half+1,half),(steps*2,half+steps*2,half+steps*2+1,steps*2+1)])
    faces=[tuple(reversed(face)) for face in faces]
    obj=_mesh(collection,'Goods_ParchmentRoll_%02d'%index,vertices,faces,[paper],uv)
    obj['goods_kind']='rolled_thin_parchment';obj['sheet_thickness_m']=thickness;obj['visible_turns']=turns
    # Closed thin linen cord. Explicit mesh and UV survive evaluated-copy joining.
    tie_vertices=[];tie_uv=[];tie_faces=[]
    for j in range(32):
        a=j*TAU/32
        for k in range(5):
            b=k*TAU/5
            rr=radius+.0014+.0017*math.cos(b)
            px=rr*math.cos(a);py=.0017*math.sin(b)
            tie_vertices.append((x+px*math.cos(angle)-py*math.sin(angle),
                                 y+px*math.sin(angle)+py*math.cos(angle),z+rr*math.sin(a)))
            tie_uv.append((j/32,k/5))
    for j in range(32):
        for k in range(5):
            tie_faces.append((j*5+(k+1)%5,((j+1)%32)*5+(k+1)%5,((j+1)%32)*5+k,j*5+k))
    tie=_mesh(collection,'Goods_ScrollTie_%02d'%index,tie_vertices,tie_faces,[binding],tie_uv)
    tie['goods_kind']='fine_linen_binding'
    return obj,tie


def _sheet(collection,bounds,paper,written):
    low,high=bounds;x0,y0=low[:2];width=high[0]-low[0];depth=high[1]-low[1]
    nx,ny=32,24;thickness=.0006
    vertices=[];uv=[];faces=[];material_indices=[]
    def surface(u,v):
        # Gentle turned edges, shallow non-periodic handling waves; grounded middle.
        z=1.0098+.011*(1-v)**14+.020*v**15
        z+=.0014*(.5+.5*math.sin(u*8.3+v*4.1))*(math.sin(math.pi*v)**2)
        z+=.003*(u**13+(1-u)**16)*(.2+.8*math.sin(math.pi*v)**2)
        xx=x0+u*width+.0007*math.sin(v*19+2)*math.sin(math.pi*u)
        yy=y0+v*depth+.0006*math.sin(u*31)*math.sin(math.pi*v)
        return xx,yy,z
    for side in [0,1]:
        for j in range(ny+1):
            for i in range(nx+1):
                u,v=i/nx,j/ny;x,y,z=surface(u,v)
                vertices.append((x,y,z-side*thickness));uv.append((u,v))
    half=(nx+1)*(ny+1)
    for j in range(ny):
        for i in range(nx):
            q=j*(nx+1)+i
            faces.append((q,q+1,q+nx+2,q+nx+1));material_indices.append(1)
            faces.append((half+q+nx+1,half+q+nx+2,half+q+1,half+q));material_indices.append(0)
    perimeter=[i for i in range(nx+1)]+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
    for a,b in zip(perimeter,perimeter[1:]+perimeter[:1]):
        faces.append((b,a,half+a,half+b));material_indices.append(0)
    obj=_mesh(collection,'Goods_UnfurledManuscript',vertices,faces,[paper,written],uv)
    for polygon,index in zip(obj.data.polygons,material_indices):polygon.material_index=index
    obj['goods_kind']='thin_parchment_sample';obj['sheet_thickness_m']=thickness
    obj['rmmo_export_group']='PaperSheet'
    return obj


def apply(asset_key, collection):
    """Rebuild goods only, returning a serializable integration/audit manifest."""
    if asset_key not in ('pottery','scroll'):raise ValueError('Unsupported asset_key: '+str(asset_key))
    children=[c for c in collection.children if '_CONTENTS' in c.name]
    if len(children)!=1:raise ValueError('Expected exactly one CONTENTS child')
    contents=children[0]
    if contents.get('rmmo_market_realism_revision'):raise ValueError('Already rebuilt; append a fresh source collection')
    old=list(contents.all_objects)
    old_bounds=_bounds(old)
    if asset_key=='pottery':
        pots=sorted([o for o in old if o.name.startswith('Replaceable open pottery')],key=lambda o:_bounds([o])[0][0])
        if len(pots)!=7:raise ValueError('Expected seven source pots')
        source=[_bounds([o]) for o in pots]
    else:
        rolls=sorted([o for o in old if o.name.startswith('Replaceable parchment roll')],key=lambda o:(round(o.location.y,2),o.location.x))
        sheets=[o for o in old if o.name.startswith('Unfurled sample parchment')]
        if len(rolls)!=9 or len(sheets)!=1:raise ValueError('Expected nine rolls and one sample')
        source=[tuple(o.location) for o in rolls];sheet_bounds=_bounds(sheets)
    # Removing only direct goods objects cannot touch any linked structure object.
    for obj in old:
        if any(c!=contents for c in obj.users_collection):raise ValueError('Goods object shared outside CONTENTS: '+obj.name)
    for obj in old:bpy.data.objects.remove(obj,do_unlink=True)
    created=[]
    if asset_key=='pottery':
        clay=_material('WarmUnglazedClay',(.30,.145,.073),.76,.92,.00028)
        glazes=[_material('MutedHoneyGlaze',(.24,.115,.030),.28,.40,.00007),
                _material('MutedOliveGlaze',(.115,.15,.061),.29,.42,.00008),
                _material('IronBrownGlaze',(.13,.056,.025),.31,.43,.00008)]
        for i,bounds in enumerate(source):created.append(_pot(contents,i,bounds,[clay,glazes[(i//2)%3]]))
        count={'pots':7,'unglazed':4,'partly_glazed':3}
    else:
        paper=_material('ParchmentFiber',(.58,.49,.34),.81,.94,.000035,True)
        binding=_material('FadedRussetLinen',(.14,.037,.018),.83,.95,.000055,True)
        written=_written_material(paper)
        for i,center in enumerate(source):created.extend(_roll(contents,i,center,paper,binding))
        created.append(_sheet(contents,sheet_bounds,paper,written))
        count={'rolled_sheets':9,'ties':9,'unfurled_sheet':1,'raised_ink_objects':0,'black_spiral_objects':0}
    contents['rmmo_market_realism_revision']=VERSION
    contents['design_basis']='Project supplementary realistic goods design, retains source display counts and approximate positions'
    bpy.context.view_layer.update()
    return {'asset_key':asset_key,'version':VERSION,'collection':collection.name,'contents':contents.name,'counts':count,
            'objects':[o.name for o in created],'old_goods_bounds_blender':old_bounds,'new_goods_bounds_blender':_bounds(created),
            'required_game_bake':['Base Color including faint manuscript ink','Roughness','OpenGL tangent Normal'],
            'constant_channels':{'metallic':0,'clearcoat':0,'alpha':1},
            'source_modified_on_disk':False,'rendered':False}
