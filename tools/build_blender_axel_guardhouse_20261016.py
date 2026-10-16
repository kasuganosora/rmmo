"""Complete Axel guardhouse, authored in background Blender; no map/catalog writes.

U13 establishes a detached pale two-storey red-roofed building. All dimensions,
internal plan, rear elevation and joinery details are project supplemental design.
Game coordinates are metres, +Y up, +Z front. Blender conversion is (x,-z,y).
"""
from pathlib import Path
import sys, json, math, hashlib, struct, argparse
from collections import defaultdict

import bpy, bmesh
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from axel_guild_furniture import build_furniture, bake_game_meshes

P = argparse.ArgumentParser()
P.add_argument('--version', default='v1')
ARGS = P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
BASE = Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/guardhouse')
OUT = BASE/ARGS.version
REVIEW = Path('D:/code/rmmo/review_artifacts/axel_landmarks_20261016/guardhouse')
LIB = Path('D:/code/rmmo_runtime/packs/default/assets/materials')
GUILD = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
OUT.mkdir(parents=True, exist_ok=True); REVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
SC=bpy.context.scene; SC.unit_settings.system='METRIC'; SC.unit_settings.scale_length=1
ROOT=bpy.data.objects.new('Axel_Guardhouse',None);SC.collection.objects.link(ROOT)
ROOT['asset_id']='axel_guardhouse_20261016';ROOT['front_axis']='+Z Godot / -Y Blender'
ROOT['design_status']='U13 silhouette; hidden features project supplemental design'
ROOT['rmmo_model_components']={'version':1}
REGIONS=[
 {'id':'ground_watch_office_store','floor':0,'min':[-6.1,.30,-4.60],'max':[6.1,3.60,4.60]},
 {'id':'upper_main_office_rest','floor':1,'min':[-2.1,3.90,-4.60],'max':[6.1,7.08,4.60]},
 {'id':'upper_front_landing','floor':1,'min':[-6.1,3.90,1.7],'max':[-2.1,7.08,4.60]},
 {'id':'upper_rear_landing','floor':1,'min':[-6.1,3.90,-4.60],'max':[-2.1,7.08,-3.7]},
 {'id':'stair_lower_flight','floor':0,'min':[-5.95,.30,-3.25],'max':[-4.18,5.50,1.7]},
 {'id':'stair_upper_flight','floor':1,'min':[-3.98,2.10,-1.55],'max':[-2.24,7.08,1.70]}
]
ROOT['rmmo_building']={'version':1,'regions':REGIONS}
GROUPS={}; OBJECTS=[]; MAT_SPECS={}; DOORS=[]; MATERIAL_FILES={}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def coord(p):return Vector((p[0],-p[2],p[1]))
def game(p):return [float(p.x),float(p.z),float(-p.y)]

def group(name,floor,role):
    if name not in GROUPS:
        ob=bpy.data.objects.new(name,None);SC.collection.objects.link(ob);ob.parent=ROOT
        GROUPS[name]=ob
        ob['semantic_group']=name
        ob['author_floor']=floor;ob['author_role']=role
    return GROUPS[name]

def image(path,color):
    path=Path(path).resolve();im=bpy.data.images.load(str(path),check_existing=True)
    im.colorspace_settings.name='sRGB' if color else 'Non-Color';im.pack()
    MATERIAL_FILES[str(path)]={'path':str(path),'sha256':sha(path),'bytes':path.stat().st_size,'dimensions':list(im.size),'color_space':im.colorspace_settings.name}
    return im

def material(name,color=(1,1,1,1),roughness=.8,metallic=0,maps=None,tile=(1,1),normal=1):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=color
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=color
    p.inputs['Roughness'].default_value=roughness;p.inputs['Metallic'].default_value=metallic
    for key,path in (maps or {}).items():
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image(path,key=='base');tex.extension='REPEAT'
        if key=='normal':
            nm=m.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=normal
            m.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
        elif key=='ao':
            from io_scene_gltf2.blender.com.material_helpers import create_settings_group
            ng=bpy.data.node_groups.get('glTF Material Output') or create_settings_group('glTF Material Output')
            settings=m.node_tree.nodes.new('ShaderNodeGroup');settings.node_tree=ng
            m.node_tree.links.new(tex.outputs['Color'],settings.inputs['Occlusion'])
        else:m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color' if key=='base' else 'Roughness'])
    MAT_SPECS[name]={'tile_m':tile,'color':color,'roughness':roughness,'metallic':metallic,'normal_scale':normal,'maps':{k:str(v) for k,v in (maps or {}).items()}}
    return m

def from_library(id,name=None):
    path=LIB/id/'material.json';spec=json.loads(path.read_text(encoding='utf8'))['material'];maps={}
    for key,role in [('texture_path','base'),('normal_path','normal'),('roughness_path','rough'),('ao_path','ao')]:
        if spec.get(key):maps[role]=(path.parent/spec[key]).resolve()
    m=material(name or spec['name'],tuple(spec.get('color',[1,1,1,1])),spec.get('roughness',.8),spec.get('metallic',0),maps,tuple(spec.get('tile_size',[1,1])),spec.get('normal_strength',1))
    MAT_SPECS[m.name]['definition']={'path':str(path),'sha256':sha(path)}
    return m

STONE=from_library('walls/stone_tiles_facade','Guardhouse | weathered limestone masonry')
WOOD=from_library('wood/natural_joinery','Guardhouse | natural oak joinery')
ROOF=from_library('roofs/terracotta_warm','Guardhouse | red clay overlap tiles')
IRON=from_library('details/forged_iron','Guardhouse | forged iron')
TRIM=material('Guardhouse | cut limestone',maps={'base':GUILD/'guild_cut_limestone_mineral_color.png','normal':GUILD/'guild_cut_limestone_micro_normal.png','rough':GUILD/'guild_cut_limestone_roughness.png'},normal=.3,tile=(1,1))
# Reuse the already portable fine mineral maps for pale limewashed infill;
# deliberately no masonry joints in the plaster and no extra texture set.
PLASTER=material('Guardhouse | warm limewash',(.78,.72,.62,1),.88,0,{'normal':GUILD/'guild_cut_limestone_micro_normal.png','rough':GUILD/'guild_cut_limestone_roughness.png'},normal=.14,tile=(1,1))
GLASS=material('Guardhouse | clear slightly green glazing',(.08,.10,.095,.04),.08)
gp=next(n for n in GLASS.node_tree.nodes if n.type=='BSDF_PRINCIPLED');gp.inputs['Alpha'].default_value=.04
gp.inputs['IOR'].default_value=1.45
GLASS.surface_render_method='DITHERED';GLASS.use_transparency_overlap=False
# Use the established native thin-glass consumer: background transmission and
# dielectric reflection are separate passes, so sunlight cannot turn a pale
# alpha-blended diffuse surface into an opaque-looking white panel. The glTF
# fallback remains unobtrusively transparent in viewers without this recipe.
GLASS_RECIPE={'version':1,'materials':{GLASS.name:{'transmittance':[.97,.985,.98],'roughness':.08}}}
MAT_SPECS[GLASS.name]['rmmo_tinted_glass']=GLASS_RECIPE
LINEN=material('Guardhouse | unbleached linen',(.62,.56,.44,1),.96)
PAPER=material('Guardhouse | pale records',(.68,.60,.42,1),.97)

def finish(ob,mat,grp,floor,role,collision='block',bevel=0,grain=False):
    ob.parent=group(grp,floor,role);ob.data.materials.append(mat)
    ob['semantic_group']=grp;ob['author_floor']=floor;ob['author_role']=role
    ob['rmmo_collision']=collision
    # Project onto physical face planes; slope length rather than horizontal
    # projection controls roof texel density. Per-board long axis controls oak.
    uv=ob.data.uv_layers.new(name='MetreUV');tile=MAT_SPECS[mat.name]['tile_m']
    ext=[max(v.co[i] for v in ob.data.vertices)-min(v.co[i] for v in ob.data.vertices) for i in range(3)]
    longest=max(range(3),key=lambda i:ext[i])
    for f in ob.data.polygons:
        normal=f.normal
        if mat==ROOF:
            u=Vector((1,0,0));u=(u-normal*u.dot(normal)).normalized()
            v=normal.cross(u).normalized()
            if v.z<0:v=-v
        else:
            axis=max(range(3),key=lambda i:abs(normal[i]));axes=[i for i in range(3) if i!=axis]
            if grain and longest in axes:axes.remove(longest);axes.append(longest)
            u=Vector(tuple(float(i==axes[0]) for i in range(3)));v=Vector(tuple(float(i==axes[1]) for i in range(3)))
        for li in f.loop_indices:
            co=ob.data.vertices[ob.data.loops[li].vertex_index].co
            uv.data[li].uv=(co.dot(u)/tile[0],co.dot(v)/tile[1])
    if bevel:
        mod=ob.modifiers.new('Small worked edge bevel','BEVEL');mod.width=bevel;mod.segments=2;mod.limit_method='ANGLE'
        wn=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');wn.keep_sharp=True
    OBJECTS.append(ob);return ob

def mesh(name,verts,faces,mat,grp='10_Exterior_L0',floor=0,role='body',collision='block',bevel=0,grain=False):
    data=bpy.data.meshes.new(name);data.from_pydata([coord(p) for p in verts],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    ob=bpy.data.objects.new(name,data);SC.collection.objects.link(ob)
    return finish(ob,mat,grp,floor,role,collision,bevel,grain)

def box(name,c,s,mat=WOOD,grp='10_Exterior_L0',floor=0,role='body',collision='block',bevel=.006,grain=False):
    x,y,z=c;w,h,d=s
    vs=[(x+a*w/2,y+b*h/2,z+c*d/2) for c in [-1,1] for b in [-1,1] for a in [-1,1]]
    return mesh(name,vs,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],mat,grp,floor,role,collision,bevel,grain)

def roof_deck_underside(ob):
    """The existing solid roof shell includes wood decking below the tiles.

    Assign its downward face instead of layering a coplanar decorative plane.
    The same closed geometry and collision volume are retained.
    """
    ob.data.materials.append(WOOD);slot=len(ob.data.materials)-1
    tile=MAT_SPECS[WOOD.name]['tile_m'];uv=ob.data.uv_layers.active
    for f in ob.data.polygons:
        if f.normal.z>=-.5:continue
        f.material_index=slot
        along=Vector((1,0,0));across=f.normal.cross(along).normalized()
        for li in f.loop_indices:
            co=ob.data.vertices[ob.data.loops[li].vertex_index].co
            uv.data[li].uv=(co.dot(across)/tile[0],co.dot(along)/tile[1])
    return ob

def beam(name,a,b,width,mat=WOOD,grp='10_Exterior_L0',floor=0,role='body',collision='none',depth=None):
    a,b=Vector(a),Vector(b);delta=b-a;axis=delta.normalized()
    ref=Vector((0,0,1)) if abs(axis.z)<.8 else Vector((1,0,0))
    u=axis.cross(ref).normalized()*width/2;v=axis.cross(u).normalized()*(depth or width)/2
    vs=[p+u*i+v*j for p in [a,b] for j in [-1,1] for i in [-1,1]]
    return mesh(name,vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,grp,floor,role,collision,.003,mat==WOOD)

def cylinder(name,c,r,h,mat,grp,floor=0,role='body',collision='none',segments=16):
    vs=[(c[0]+r*math.cos(i*math.tau/segments),c[1]+yy*h/2,c[2]+r*math.sin(i*math.tau/segments)) for yy in [-1,1] for i in range(segments)]
    faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,segments*2))]+[(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    return mesh(name,vs,faces,mat,grp,floor,role,collision,.002)

def wall(name,axis,fixed,u0,u1,y0,y1,thickness,holes,mat,grp,floor):
    """Watertight wall shell with real openings, not opaque window decals."""
    us=sorted(set([u0,u1]+[q for h in holes for q in [h[0],h[1]]]))
    ys=sorted(set([y0,y1]+[q for h in holes for q in [h[2],h[3]]]))
    cells=set()
    for i in range(len(us)-1):
        for j in range(len(ys)-1):
            u=(us[i]+us[i+1])/2;y=(ys[j]+ys[j+1])/2
            if not any(a<u<b and c<y<d for a,b,c,d in holes):cells.add((i,j))
    verts=[];faces=[];index={}
    def point(u,y,n):return (u,y,n) if axis=='x' else (n,y,u)
    def face(points):
        ids=[]
        for p in points:
            p=tuple(p)
            if p not in index:index[p]=len(verts);verts.append(p)
            ids.append(index[p])
        faces.append(ids)
    for i,j in cells:
        a,b=us[i:i+2];c,d=ys[j:j+2];near=fixed-thickness/2;far=fixed+thickness/2
        for n in [near,far]:face([point(a,c,n),point(b,c,n),point(b,d,n),point(a,d,n)])
        for ni,nj,ends in [(i-1,j,[(a,c),(a,d)]),(i+1,j,[(b,c),(b,d)]),(i,j-1,[(a,c),(b,c)]),(i,j+1,[(a,d),(b,d)])]:
            if (ni,nj) not in cells:
                (u,y),(v,z)=ends;face([point(u,y,near),point(v,z,near),point(v,z,far),point(u,y,far)])
    return mesh(name,verts,faces,mat,grp,floor,'body','block',.012)

def window(name,axis,fixed,u,width,bottom,height,floor,out):
    grp='12_Window_L0' if floor==0 else '31_Window_L1'
    def c(uu,y,n):return (uu,y,n) if axis=='x' else (n,y,uu)
    def s(w,h,d):return (w,h,d) if axis=='x' else (d,h,w)
    for side in [-1,1]:box(name+' stone jamb',c(u+side*(width/2+.095),bottom+height/2,fixed),s(.19,height+.26,.55),TRIM,grp,floor,bevel=.015)
    for yy in [bottom-.08,bottom+height+.09]:box(name+' sill lintel',c(u,yy,fixed+out*.045),s(width+.42,.18,.65),TRIM,grp,floor,bevel=.02)
    for side in [-1,1]:box(name+' oak side',c(u+side*(width/2-.055),bottom+height/2,fixed-out*.03),s(.11,height,.10),WOOD,grp,floor,grain=True)
    for yy in [bottom+.045,bottom+height-.045,bottom+height*.5]:box(name+' oak rail',c(u,yy,fixed-out*.03),s(width,.09,.11),WOOD,grp,floor,grain=True)
    box(name+' oak mullion',c(u,bottom+height/2,fixed-out*.03),s(.075,height,.12),WOOD,grp,floor,grain=True)
    # Four separate thin glass panes expose the actual full-depth reveal.
    for du in [-1,1]:
        for dv in [0,1]:box(name+' clear glass',c(u+du*width*.245,bottom+height*(.25+.5*dv),fixed-out*.04),s(width*.445,height*.44,.009),GLASS,grp,floor,collision='none',bevel=0)

def door(name,axis,fixed,u,width,bottom,height,floor,out,double=False):
    grp='43_Doors_L0' if floor==0 else '31_Doors_L1'
    def c(uu,y,n):return (uu,y,n) if axis=='x' else (n,y,uu)
    def s(w,h,d):return (w,h,d) if axis=='x' else (d,h,w)
    # Fixed lining and masonry lintel never rotate with the leaf.
    for side in [-1,1]:box(name+' fixed jamb',c(u+side*(width/2+.11),bottom+height/2,fixed),s(.22,height+.16,.57),TRIM,grp,floor,bevel=.02)
    box(name+' lintel',c(u,bottom+height+.12,fixed),s(width+.58,.25,.62),TRIM,grp,floor,bevel=.025)
    leaves=[(-1,width/2),(1,width/2)] if double else [(-1,width)]
    for side,w in leaves:
        pivot_u=u+side*width/2;center_u=pivot_u-side*w/2
        for frac in [.18,.5,.82]:
            yy=bottom+height*frac
            box(name+' fixed hinge wall plate',c(pivot_u+side*.10,yy,fixed+out*.06),s(.15,.23,.026),IRON,grp,floor,'body','none',.006)
            beam(name+' fixed hinge pintle arm',c(pivot_u+side*.11,yy-.07,fixed+out*.06),c(pivot_u,yy-.07,fixed),.026,IRON,grp,floor,'body','none')
            cylinder(name+' fixed hinge pintle',c(pivot_u,yy,fixed),.017,.23,IRON,grp,floor,'body','none',12)
        start=len(OBJECTS);leaf=name+('_left' if side==-1 else '_right');leafgrp='door_'+leaf
        for i in range(max(3,round(w/.18))):
            n=max(3,round(w/.18));uu=center_u-w/2+(i+.5)*w/n
            box(leaf+' plank',c(uu,bottom+height/2,fixed),s(w/n-.003,height-.035,.08),WOOD,leafgrp,floor,'door','block',.004,True)
        for frac in [.18,.5,.82]:
            yy=bottom+height*frac
            box(leaf+' iron strap',c(center_u,yy,fixed+out*.055),s(w-.05,.065,.025),IRON,leafgrp,floor,'door','block',.005)
            cylinder(leaf+' hinge barrel',c(pivot_u,yy,fixed),.04,.18,IRON,leafgrp,floor,'door','block',12)
            for q in [.17,.50,.83]:
                box(leaf+' rivet',c(pivot_u-side*w*q,yy,fixed+out*.075),s(.027,.027,.018),IRON,leafgrp,floor,'door','none',.007)
        handleu=pivot_u-side*w*.84
        for face in [-1,1]:
            box(leaf+' latchplate',c(handleu,bottom+height*.47,fixed+face*.06),s(.13,.23,.025),IRON,leafgrp,floor,'door','block')
            beam(leaf+' pull handle',c(handleu,bottom+height*.43,fixed+face*.11),c(handleu,bottom+height*.51,fixed+face*.11),.028,IRON,leafgrp,floor,'door','none')
        for frac in [.18,.82]:
            box(leaf+' inside ledge',c(center_u,bottom+height*frac,fixed-out*.06),s(w-.06,.14,.055),WOOD,leafgrp,floor,'door','block',.006,True)
        DOORS.append({'id':leaf,'objects':OBJECTS[start:],'pivot_game':list(c(pivot_u,bottom,fixed)),'angle':float(-side*out*100),'floor':floor,'group':leafgrp,'axis':axis})

# Exact foundation, thresholds and short approach steps: no blocked entrance.
box('Stone ground floor',(0,.15,0),(13,.30,10),STONE,'00_Foundation',0,'floor','walk',.015)
for z,w,depth,h in [(5.675,4.5,1.35,.30),(6.50,4.7,.35,.15)]:
    box('Entry stone step',(0,h/2,z),(w,h,depth),TRIM,'00_Foundation',0,'floor','walk',.012)
box('Rear service threshold',(3.7,.15,-5.25),(2.0,.30,.5),TRIM,'00_Foundation',0,'floor','walk')
box('Rear lower step',(3.7,.075,-5.48),(2.0,.15,.25),TRIM,'00_Foundation',0,'floor','walk')

FRONT0=[(-1.1,1.1,.30,3.25),(-4.95,-3.65,1.25,2.95),(3.65,4.95,1.25,2.95)]
REAR0=[(2.95,4.45,.30,3.10),(-5.05,-3.75,1.25,2.95),(-.75,.55,1.25,2.95)]
UPPER=[(x-.6,x+.6,4.85,6.65) for x in [-4.5,-1.5,1.5,4.5]]
SIDE0=[(z-.65,z+.65,1.25,2.95) for z in [-2.8,2.8]]
SIDE1=[(z-.6,z+.6,4.85,6.65) for z in [-2.8,2.8]]
for floor,y0,y1,grp,mat in [(0,.30,3.9,'10_Exterior_L0',STONE),(1,3.9,7.25,'11_Exterior_Upper',PLASTER)]:
    for side,holes in [(1,FRONT0 if floor==0 else UPPER),(-1,REAR0 if floor==0 else UPPER)]:
        wall(('Front' if side==1 else 'Rear')+' wall L'+str(floor),'x',side*4.8,-6.5,6.5,y0,y1,.40,holes,mat,grp,floor)
        for i,(a,b,c,d) in enumerate(holes):
            if c>y0+.2:window(('Front' if side==1 else 'Rear')+f' window {floor}_{i}','x',side*4.8,(a+b)/2,b-a,c,d-c,floor,side)
    for side in [-1,1]:
        holes=SIDE0 if floor==0 else SIDE1
        wall(('Left' if side==-1 else 'Right')+' wall L'+str(floor),'z',side*6.3,-4.6,4.6,y0,y1,.4,holes,mat,grp,floor)
        for i,(a,b,c,d) in enumerate(holes):window(('Left' if side==-1 else 'Right')+f' window {floor}_{i}','z',side*6.3,(a+b)/2,b-a,c,d-c,floor,side)
    # Worked corner quoins are discrete large blocks, held to the load-bearing
    # masonry corners; trim does not float over window/door openings.
    for x in [-6.25,6.25]:
        for z in [-4.75,4.75]:
            n=math.ceil((y1-y0)/.44)
            for row in range(n):
                height=(y1-y0)/n
                box('Corner quoin', (x,y0+(row+.5)*height,z),(.56,height-.012,.56),TRIM,grp,floor,bevel=.012)
    for side in [-1,1]:
        box('Long stone stringcourse',(0,y1-.08,side*4.82),(13.1,.16,.48),TRIM,grp,floor,bevel=.015)
        box('Short stone stringcourse',(side*6.32,y1-.08,0),(.48,.16,9.6),TRIM,grp,floor,bevel=.015)

door('Front watch entrance','x',4.84,0,2.2,.30,2.95,0,1,True)
door('Rear service entrance','x',-4.84,3.7,1.5,.30,2.8,0,-1)

# Open porch frame. Four post positions preserve a 2.45 m central passage.
for x in [-1.55,1.55]:
    box('Porch stone plinth',(x,.47,6.08),(.45,.34,.45),TRIM,'13_Porch',0,bevel=.018)
    box('Porch oak post',(x,1.98,6.08),(.22,2.72,.22),WOOD,'13_Porch',0,grain=True)
    beam('Porch triangular front brace',(x,2.75,6.08),(x-math.copysign(.5,x),3.33,6.08),.13,WOOD,'13_Porch')
    beam('Porch triangular depth brace',(x,2.75,6.08),(x,3.55,5.35),.13,WOOD,'13_Porch')
box('Porch front lintel',(0,3.42,6.08),(3.5,.23,.25),WOOD,'13_Porch',0,grain=True)
for x in [-1.65,0,1.65]:beam('Porch rafter',(x,3.5,6.55),(x,4.15,4.7),.14,WOOD,'13_Porch')
roof_deck_underside(mesh('Porch clay roof',[(-1.95,3.65,6.6),(1.95,3.65,6.6),(1.95,4.3,4.7),(-1.95,4.3,4.7),(-1.95,3.54,6.6),(1.95,3.54,6.6),(1.95,4.19,4.7),(-1.95,4.19,4.7)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],ROOF,'13_Porch',0,'roof','block',.008))

# Floor 1 avoids the entire stairwell. Load paths are beams carried by masonry.
for c,s in [((2.1,3.75,0),(8.4,.3,9.2)),((-4.2,3.75,3.15),(4.2,.3,2.9)),((-4.2,3.75,-4.15),(4.2,.3,.9))]:
    box('Upper oak floor slab',c,s,WOOD,'20_Floor_L1',1,'floor','walk',.005,True)
box('Stair top landing connection',(-3.12,3.75,1.575),(1.65,.30,.25),WOOD,'20_Floor_L1',1,'floor','walk',.003,True)
for z in [-4.4,1.65,4.4]:beam('Floor carrying beam',(-6.1,3.43,z),(6.1,3.43,z),.22,WOOD,'23_Supports',0,'body','block',.30)
beam('Stair opening header',(-2.10,3.43,-3.70),(-2.10,3.43,1.70),.22,WOOD,'23_Supports',0,'body','block',.30)
for x in [0.0,3.5]:
    for z in [-2.5,0]:beam('Ground ceiling joist',(x-1.5,3.49,z),(x+1.5,3.49,z),.12,WOOD,'23_Supports',0,'body','none',.17)

# Dogleg stair: 20 x 0.18m rises, two 1.65m flights, 0.30m treads.
for i in range(10):
    h=(i+1)*.18
    box('Stair first flight tread',(-5.05,.30+h/2,1.45-(i+.5)*.30),(1.65,h,.30),WOOD,'21_Stair',0,'floor','walk',.006,True)
box('Stair half landing',(-4.08,2.02,-2.40),(3.60,.16,1.70),WOOD,'21_Stair',0,'floor','walk',.005,True)
for i in range(10):
    h=(i+1)*.18
    box('Stair return tread',(-3.12,2.10+h/2,-1.55+(i+.5)*.30),(1.65,h,.30),WOOD,'21_Stair',0,'floor','walk',.006,True)
for x,z0,z1,y0,y1 in [(-5.91,1.50,-1.55,.30,2.10),(-4.19,1.50,-1.55,.30,2.10),(-3.98,-1.55,1.50,2.10,3.90),(-2.26,-1.55,1.50,2.10,3.90)]:
    beam('Stair handrail',(x,y0+1.03,z0),(x,y1+1.03,z1),.075,WOOD,'22_Rails',0,'body','block')
    for t in [0,.25,.5,.75,1]:
        z=z0+(z1-z0)*t;y=y0+(y1-y0)*t
        beam('Stair baluster',(x,y,z),(x,y+1.02,z),.055,WOOD,'22_Rails',0,'body','block')
for a,b in [((-5.95,4.95,1.70),(-4.14,4.95,1.70)),((-2.13,4.95,-3.65),(-2.13,4.95,1.55)),((-5.95,4.95,-3.65),(-2.13,4.95,-3.65))]:
    beam('Upper stairwell guard rail',a,b,.075,WOOD,'30_Upper_Rails',1,'body','block')
    length=(Vector(b)-Vector(a)).length
    for i in range(math.ceil(length/.24)+1):
        p=Vector(a).lerp(Vector(b),i/math.ceil(length/.24));beam('Upper stairwell baluster',(p.x,3.90,p.z),p,.045,WOOD,'30_Upper_Rails',1,'body','block')

# Functional room partitions, with true door openings at both levels.
wall('Ground armour store partition','x',-1.1,1.7,6.1,.30,3.60,.16,[(2.8,4.4,.30,3.10)],PLASTER,'14_Internal_L0',0)
wall('Ground store return','z',1.7,-4.6,-1.1,.30,3.6,.16,[],PLASTER,'14_Internal_L0',0)
door('Armour store door','x',-1.1,3.6,1.6,.30,2.8,0,1)
wall('Upper rest room partition','x',-.55,-2.05,6.1,3.90,7.08,.14,[(-.65,.95,3.90,6.70)],PLASTER,'30_Rooms_L1',1)
door('Upper rest room door','x',-.55,.15,1.6,3.90,2.8,1,1)

# Visible closed stone fireplace and open flue/chimney; purely architecture,
# no baked point light or fake emissive fire added to the model.
for x in [-.9,.9]:box('Hearth jamb',(x,1.15,-4.3),(.3,1.7,.55),TRIM,'14_Internal_L0',0)
box('Hearth lintel',(0,2.12,-4.3),(2.1,.3,.62),TRIM,'14_Internal_L0',0)
box('Hearth fireback',(0,1.25,-4.52),(1.55,1.9,.12),IRON,'14_Internal_L0',0)
box('Hearth stone slab',(0,.38,-4.05),(2.35,.16,1.0),TRIM,'14_Internal_L0',0,'floor','walk')
box('Flue breast',(0,2.85,-4.35),(1.4,1.15,.5),STONE,'14_Internal_L0',0)
box('Upper flue breast',(0,5.55,-4.40),(1.4,3.3,.5),PLASTER,'30_Rooms_L1',1)

# Attic gables, closed roof thickness, purlins, tie beams and diagonal rafters.
# Sloped wall-plate infill meets the actual underside of the overhanging roof.
# A horizontal wall stopping at the low eave would leave a 0.34m daylight gap.
for side in [-1,1]:
    vs=[]
    for x in [-6.5,6.5]:
        for z in [side*4.6,side*5.0]:
            for y in [7.18,10.8-abs(z)*3.55/5.55-.12]:vs.append((x,y,z))
    mesh('Sloped eave wall plate',vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],PLASTER,'11_Exterior_Upper',1,'body','block',.004)
for side in [-1,1]:
    x=side*6.3
    profile=[(7.18,-4.8),(7.18,4.8),(10.68-4.8*3.55/5.55,4.8),(10.68,0),(10.68-4.8*3.55/5.55,-4.8)]
    verts=[(x+dx,y,z) for dx in [-.20,.20] for y,z in profile];n=len(profile)
    mesh('Gable masonry',verts,[tuple(range(n)),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],PLASTER,'50_Roof',1,'roof','block',.01)
    for z in [-5.55,5.55]:beam('Gable verge stone',(side*7.0,7.30,z),(side*7.0,10.85,0),.17,TRIM,'50_Roof',1,'roof','none')
for side in [-1,1]:
    verts=[(x,10.8-abs(z)*3.55/5.55-y,z) for y in [0,.14] for x,z in [(-7.05,0),(7.05,0),(7.05,side*5.55),(-7.05,side*5.55)]]
    roof_deck_underside(mesh('Main clay roof '+str(side),verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],ROOF,'50_Roof',1,'roof','block',.005))
    beam('Roof eave fascia',(-7.05,7.15,side*5.50),(7.05,7.15,side*5.50),.16,WOOD,'50_Roof',1,'roof','none',.24)
    for x in [-6.4,-3.2,0,3.2,6.4]:beam('Roof rafter',(x,7.12,side*5.35),(x,10.63,0),.17,WOOD,'50_Roof',1,'roof','none',.22)
    beam('Mid-slope purlin',(-6.5,8.64,side*2.80),(6.5,8.64,side*2.80),.18,WOOD,'50_Roof',1,'roof','none',.24)
for x in [-6.2,-3.1,0,3.1,6.2]:
    beam('Roof tie beam',(x,7.08,-4.60),(x,7.08,4.60),.20,WOOD,'50_Roof',1,'roof','none',.25)
    beam('King post',(x,7.08,0),(x,10.55,0),.17,WOOD,'50_Roof',1,'roof','none')
    for side in [-1,1]:beam('Roof truss brace',(x,7.08,side*2.80),(x,8.90,0),.15,WOOD,'50_Roof',1,'roof','none')
# Individually lapped ridge caps give a real silhouette without making every
# tile of the roof geometry; the metre-based normal carries field overlaps.
for i in range(44):
    x=-7.04+(i+.5)*14.08/44;segments=10
    vs=[]
    for xx in [x-.17,x+.17]:
        for r in [.18,.14]:
            for j in range(segments+1):
                a=j*math.pi/segments;vs.append((xx,10.76+r*math.sin(a),r*math.cos(a)))
    n=segments+1;faces=[]
    for j in range(segments):faces.extend([(j,j+1,2*n+j+1,2*n+j),(n+j,3*n+j,3*n+j+1,n+j+1)])
    for k in [0,segments]:faces.append((k,2*n+k,3*n+k,n+k))
    for offset in [0,2*n]:
        for j in range(segments):faces.append((offset+j,offset+n+j,offset+n+j+1,offset+j+1))
    mesh('Lapped terracotta ridge cap',vs,faces,ROOF,'50_Roof',1,'roof','none',0)
# Square flue emerges above the back slope and retains a real central hole.
for c,s in [((-.48,9.25,-4.20),(.22,4.10,.95)),((.48,9.25,-4.20),(.22,4.10,.95)),((0,9.25,-4.57),(.74,4.10,.22)),((0,9.25,-3.83),(.74,4.10,.22))]:
    box('Chimney flue shell',c,s,STONE,'50_Roof',1,'roof','block',.012)
for c,s in [((-.55,11.23,-4.2),(.25,.14,1.2)),((.55,11.23,-4.2),(.25,.14,1.2)),((0,11.23,-4.68),(.85,.14,.25)),((0,11.23,-3.72),(.85,.14,.25))]:
    box('Chimney coping',c,s,TRIM,'50_Roof',1,'roof','none',.02)

# Reuse established furnishing builders; keep parts independent from structure.
FURN_MATS={'wood':WOOD,'wood_dark':WOOD,'steel':IRON,'metal':IRON,'inset':WOOD,'glass':GLASS,'paper':PAPER,'linen':LINEN,'cloth':LINEN,'soil':STONE}
FURN=[]
def furniture(kind,p,yaw=0,floor=0):
    col=SC.collection;root,parts=build_furniture(kind,col,FURN_MATS,'game','guardhouse_'+kind+'_'+str(len(FURN)))
    parts=bake_game_meshes(root,parts);root.parent=group('32_Furniture_L1' if floor else '41_Furniture_L0',floor,'furniture')
    root.location=coord(p);root.rotation_euler.z=math.radians(yaw)
    for o in parts:
        o['semantic_group']='32_Furniture_L1' if floor else '41_Furniture_L0';o['author_floor']=floor;o['author_role']='furniture'
        o['rmmo_collision']='block' if o.get('collision_review',True) else 'none';OBJECTS.append(o)
    FURN.append({'kind':kind,'position_game':p,'yaw':yaw,'floor':floor,'builder':'tools/axel_guild_furniture.py'})
furniture('writing_desk',(-4.45,.30,3.75),0,0)
furniture('stool',(-4.45,.30,2.85),0,0)
furniture('dining_table',(2.5,.30,2.5),0,0)
furniture('short_bench',(2.5,.30,1.6),0,0)
furniture('short_bench',(2.5,.30,3.4),0,0)
furniture('waiting_bench',(5.5,.30,.2),90,0)
furniture('writing_desk',(3.8,3.90,3.7),0,1)
furniture('stool',(3.8,3.90,2.8),0,1)
for x in [-.9,2.0,4.9]:furniture('single_bed',(x,3.90,-2.9),0,1)
furniture('small_table',(2.0,3.90,-.05),0,1)
# Simple open weapon/equipment rack, attached to the store wall, without
# adding new collectable weapons or game interaction systems.
for x in [2.1,5.6]:box('Equipment rack post',(x,1.45,-4.12),(.12,2.3,.15),WOOD,'41_Furniture_L0',0,grain=True)
for y in [.5,1.4,2.3]:box('Equipment rack shelf',(3.85,y,-4.12),(3.65,.09,.65),WOOD,'41_Furniture_L0',0,grain=True)
for x in [2.4,3.0,3.6,4.2,4.8,5.4]:beam('Rack hook',(x,1.8,-4.2),(x,1.8,-3.92),.035,IRON,'41_Furniture_L0',0)

# Evaluate modifiers, then merge only stable same-floor/role/material batches.
# Doors remain separate leaves, with all hardware transformed by their hinge.
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
for ob in list(OBJECTS):
    ev=ob.evaluated_get(deps);data=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=deps)
    old=ob.data;ob.modifiers.clear();ob.data=data
    if old.users==0:bpy.data.meshes.remove(old)

def join(objects,name):
    if len(objects)==1:
        objects[0].name=name
        return objects[0]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=objects[0];o.name=name
    return o

door_parts={o for row in DOORS for o in row['objects']};final=[]
for row in DOORS:
    ob=join(row.pop('objects'),'DoorLeaf_'+row['id'])
    world=ob.matrix_world.copy();pivot=coord(row['pivot_game'])
    # Preserve all world vertices while moving the mesh origin to the hinge.
    ob.data.transform(Matrix.Translation(-pivot)@world);ob.matrix_world=Matrix.Translation(pivot)
    ob['rmmo_hinge']={'id':row['id'],'pivot':[0.0,0.0,0.0],'angle':row['angle'],'open':0.0}
    ob['rmmo_collision']='block';ob['author_role']='door';final.append(ob)

batches=defaultdict(list)
for ob in list(bpy.data.objects):
    if ob.type!='MESH' or ob in final:continue
    key=(ob.get('semantic_group','Ungrouped'),ob.get('author_floor',0),ob.get('author_role','body'),ob.get('rmmo_collision','block'),tuple(m.name for m in ob.data.materials))
    batches[key].append(ob)
for key,obs in batches.items():
    batchid=hashlib.sha256(str(key).encode()).hexdigest()[:8]
    ob=join(obs,key[0]+'__'+key[2]+'__'+batchid);final.append(ob)

nodes=[];triangle_count=0;zero_triangles=0
for i,ob in enumerate(sorted(final,key=lambda o:o.name)):
    ob['uuid']='axel_guardhouse_'+hashlib.sha256(ob.name.encode()).hexdigest()[:16]
    if any(m==GLASS for m in ob.data.materials):
        ob['rmmo_tinted_glass']=GLASS_RECIPE
    role='stairs' if ob['semantic_group']=='21_Stair' else ob['author_role']
    ob['rmmo_part']={'floor':int(ob['author_floor']),'floor_y':.3 if int(ob['author_floor'])==0 else 3.9,'role':role,'part':ob['uuid']}
    if any(len(p.vertices)>4 for p in ob.data.polygons):
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Export ngon triangulation','TRIANGULATE');mod.min_vertices=5;mod.keep_custom_normals=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.data.calc_loop_triangles();tris=ob.data.loop_triangles;triangle_count+=len(tris)
    for t in tris:
        a,b,c=[ob.data.vertices[k].co for k in t.vertices]
        if (b-a).cross(c-a).length_squared<1e-18:zero_triangles+=1
    points=[game(ob.matrix_world@v.co) for v in ob.data.vertices]
    mn=[min(p[a] for p in points) for a in range(3)];mx=[max(p[a] for p in points) for a in range(3)]
    nodes.append({'uuid':ob['uuid'],'name':ob.name,'group':ob['semantic_group'],'floor':int(ob['author_floor']),'role':role,'rmmo_part':ob['rmmo_part'].to_dict(),'collision':ob['rmmo_collision'],'triangles':len(tris),'aabb_min':mn,'aabb_max':mx,'hinge':ob['rmmo_hinge'].to_dict() if ob.get('rmmo_hinge') else None})

assert zero_triangles==0, f'Unexpected degenerate triangles: {zero_triangles}'
bpy.ops.object.select_all(action='DESELECT')
for ob in bpy.data.objects:
    if ob.type in ['MESH','EMPTY']:ob.select_set(True)
SC.render.engine='BLENDER_EEVEE_NEXT'
for m in list(bpy.data.materials):
    if m.users==0:bpy.data.materials.remove(m)
master=OUT/'axel_guardhouse.blend';export=OUT/'axel_guardhouse.glb'
bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_extras=True,export_apply=True,export_tangents=True,export_animations=False,export_cameras=False,export_lights=False)
# Exporter may omit factors when an image is connected. Restore the intended
# glTF base-color multiplicative factor explicitly; packed image bytes unchanged.
raw=export.read_bytes();jsize,jtype=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+jsize]);tail=raw[20+jsize:]
for m in doc.get('materials',[]):
    if m['name'] in MAT_SPECS:
        m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=list(MAT_SPECS[m['name']]['color'])
payload=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();payload+=b' '*(-len(payload)%4)
export.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(tail),len(payload),jtype)+payload+tail)

manifest={'asset_id':'axel_guardhouse_20261016','version':ARGS.version,'stage':'candidate_cpu_built_gpu_pending','master':{'path':str(master),'sha256':sha(master),'bytes':master.stat().st_size},'export':{'path':str(export),'sha256':sha(export),'bytes':export.stat().st_size},'script':{'path':str(Path(__file__)),'sha256':sha(__file__)},'dimensions_m':[14.1,11.3,12.2],'front':'+Z','units':'metres','nodes':nodes,'triangles':triangle_count,'degenerate_triangles':zero_triangles,'materials':MAT_SPECS,'source_images':list(MATERIAL_FILES.values()),'doors':DOORS,'furnishing_instances':FURN,'rooms':[{'id':'ground_watch_office','floor':0,'bounds_min':[-6.1,.30,-4.60],'bounds_max':[6.1,3.60,4.60]},{'id':'upper_office_rest','floor':1,'bounds_min':[-6.1,3.90,-4.60],'bounds_max':[6.1,7.08,4.60]}],'stairwell':{'min':[-6.0,.30,-3.7],'max':[-2.1,7.08,1.7],'rises':20,'rise_m':.18,'tread_m':.30,'width_m':1.65},'review':{'resource_audit':'pending exported CPU audit','visual':'pending root GPU review','runtime_pipeline':'pending root native import/save/reopen','formal_library':'pending root publication','map':'not modified'},'limits':['No dormer windows invented from unresolved distant U13 pixels','No alarm tower or connecting corridor','No formal-map edits','No actual RSS/VRAM measurement','No game interaction logic for furniture','Floor/roof semantic consumption awaits root generic building adapter']}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
manifest['rooms']=REGIONS
manifest['rmmo_building']={'version':1,'regions':REGIONS}
manifest['actual_geometry_bounds']={'min':[min(n['aabb_min'][a] for n in nodes) for a in range(3)],'max':[max(n['aabb_max'][a] for n in nodes) for a in range(3)]}
manifest['dimensions_m']=[manifest['actual_geometry_bounds']['max'][a]-manifest['actual_geometry_bounds']['min'][a] for a in range(3)]
manifest['limits'][-1]='Generic rmmo_model_components/rmmo_part/rmmo_building authored; actual runtime consumer validation pending root'
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'build_script.py').write_text(Path(__file__).read_text(encoding='utf8'),encoding='utf8')
(BASE/'latest_candidate.json').write_text(json.dumps({'version':ARGS.version,'manifest':str(OUT/'manifest.json'),'sha256':sha(OUT/'manifest.json'),'glb':str(export),'glb_sha256':sha(export)},indent=2),encoding='utf8')
print('GUARDHOUSE_BUILT',json.dumps({'export':str(export),'sha256':sha(export),'triangles':triangle_count,'nodes':len(nodes),'source_images':len(MATERIAL_FILES)}),flush=True)
