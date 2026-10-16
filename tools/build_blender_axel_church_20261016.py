"""Complete authored Axel church. Blender 4.5 -b CPU construction only.

Reference is the user's church frame, not the S12 riverside house. Hidden plan,
furnishings, tower stairs and rear elevation are project supplemental design.
Never writes a map, catalogue, shared material, or production script.
"""
import argparse, hashlib, json, math, shutil, struct, sys
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix

P=argparse.ArgumentParser(); P.add_argument('--version',default='v1')
ARGS=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
ROOT=Path('D:/code/rmmo'); BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church')
OUT=BASE/ARGS.version; REVIEW=ROOT/'review_artifacts/axel_landmarks_20261016/church'/ARGS.version
OUT.mkdir(parents=True,exist_ok=True); REVIEW.mkdir(parents=True,exist_ok=True)
LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials')
GM=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
if (OUT/'axel_church.glb').exists(): raise RuntimeError('Version immutable; choose a new --version')
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
SC=bpy.context.scene; SC.unit_settings.system='METRIC'; SC.unit_settings.scale_length=1
OBJECTS=[]; PARTS=[]; IMAGES={}; MATERIALS={}; OPENINGS=[]; INPUTS={}
ROOT_OBJ=bpy.data.objects.new('Axel_Church',None); SC.collection.objects.link(ROOT_OBJ)
ROOT_OBJ['asset_id']='axel_church'; ROOT_OBJ['model_source']='Blender church 20261016'
ROOT_OBJ['reference_scope']='User church exterior; interior and concealed structure are project supplementary design'
ROOT_OBJ['rmmo_model_components']={'version':1}

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def coord(v): return (v[0],-v[2],v[1])
def godot(v): return Vector((v[0],v[2],-v[1]))
def image(path,color=True,dx=False):
    path=Path(path); key=(str(path),color,dx)
    if key in IMAGES:return IMAGES[key]
    INPUTS[str(path)]={'sha256':sha(path),'bytes':path.stat().st_size}
    im=bpy.data.images.load(str(path),check_existing=False)
    im.colorspace_settings.name='sRGB' if color else 'Non-Color'
    if dx:
        arr=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(arr);arr[1::4]=1-arr[1::4]
        im.pixels.foreach_set(arr);im.filepath_raw=str(OUT/(path.parent.name+'_normal_opengl.png'));im.file_format='PNG';im.save()
    im.pack();IMAGES[key]=im;return im

def material(name,color=(1,1,1),metal=0,rough=.8,maps=None,normal=1,dx=False):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    m.use_backface_culling=True
    for socket,path in (maps or {}).items():
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image(path,socket=='Base Color',dx and socket=='Normal');tex.extension='REPEAT'
        if socket=='Normal':
            nm=m.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=normal
            m.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],p.inputs[socket])
        elif socket=='Occlusion':
            from io_scene_gltf2.blender.com.material_helpers import create_settings_group
            grp=bpy.data.node_groups.get('glTF Material Output') or create_settings_group('glTF Material Output')
            no=m.node_tree.nodes.new('ShaderNodeGroup');no.node_tree=grp;m.node_tree.links.new(tex.outputs['Color'],no.inputs['Occlusion'])
        else:m.node_tree.links.new(tex.outputs['Color'],p.inputs[socket])
    MATERIALS[name]=m;return m

stone=material('Church aged pale limestone masonry',maps={s:LIB/'walls/stone_tiles_facade'/f for s,f in [('Base Color','texture.jpg'),('Normal','normal.png'),('Roughness','roughness.png'),('Occlusion','ao.png')]},normal=1.05,rough=1)
trim=material('Church dressed limestone mouldings',maps={s:GM/f for s,f in [('Base Color','guild_cut_limestone_mineral_color.png'),('Normal','guild_cut_limestone_micro_normal.png'),('Roughness','guild_cut_limestone_roughness.png')]},normal=.18,rough=1)
roofmat=material('Church red terracotta fishscale roof',maps={s:GM/f for s,f in [('Base Color','guild_fishscale_large_repeat_color.png'),('Normal','guild_fishscale_large_repeat_normal.png'),('Roughness','guild_fishscale_large_repeat_roughness.png')]},normal=1,rough=1)
clay=material('Church plain fired clay roof thickness',maps={s:GM/f for s,f in [('Base Color','guild_baked_clay_plain_color.png'),('Normal','guild_baked_clay_plain_normal.png'),('Roughness','guild_baked_clay_plain_roughness.png')]},normal=.4,rough=1)
wood=material('Church structural oak',maps={s:LIB/'wood/solid_timber'/f for s,f in [('Base Color','texture.png'),('Normal','normal.png'),('Roughness','roughness.png')]},normal=.45,rough=1)
doorwood=wood.copy();doorwood.name='Church dark stained oak door'
dp=next(n for n in doorwood.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
base_link=dp.inputs['Base Color'].links[0].from_socket
mix=doorwood.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
mix.inputs[2].default_value=(.42,.27,.16,1)
doorwood.node_tree.links.new(base_link,mix.inputs[1]);doorwood.node_tree.links.new(mix.outputs[0],dp.inputs['Base Color'])
floor=material('Church stone flag paving',maps={s:LIB/'paving/sandstone_floor'/f for s,f in [('Base Color','texture.jpg'),('Normal','normal.png'),('Roughness','roughness.png'),('Occlusion','ao.png')]},normal=.65,rough=1,dx=True)
iron=material('Church blackened iron',(.027,.031,.029),.85,.46)
brass=material('Church aged brass fittings',(.31,.22,.07),.92,.32)
lead=material('Church dark window lead',(.035,.041,.038),.85,.43)
lead.use_backface_culling=False
glass=[]; GLASS_SPECS={}
for i,t in enumerate([(.24,.84,.29),(.22,.64,.85),(.51,.83,.67),(.66,.36,.79)]):
    m=material('Church stained glass '+str(i),t,0,.13)
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Alpha'].default_value=.32;p.inputs['Transmission Weight'].default_value=.7;p.inputs['IOR'].default_value=1.5
    m.surface_render_method='BLENDED';m.use_backface_culling=False;glass.append(m)
    GLASS_SPECS[m.name]={'transmittance':list(t),'roughness':.13}
clear=material('Church clear lantern glass',(.83,.91,.89),0,.10)
next(n for n in clear.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Alpha'].default_value=.13
next(n for n in clear.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Transmission Weight'].default_value=.85
clear.surface_render_method='BLENDED';clear.use_backface_culling=False
GLASS_SPECS[clear.name]={'transmittance':[.97,.985,.98],'roughness':.10}
glow=material('Church warm white floating magic stone',(.75,.68,.53),0,.18)
next(n for n in glow.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Emission Color'].default_value=(1,.88,.68,1)
next(n for n in glow.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Emission Strength'].default_value=.65
glow_facets=[]
for i,level in enumerate([.22,.34,.48,.60]):
    mat=material('Church magic stone cut facet '+str(i),(.12,.11,.09),0,.22)
    p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Emission Color'].default_value=(1,.92,.80,1);p.inputs['Emission Strength'].default_value=level
    glow_facets.append(mat)

def register(o,name,mat,floor_=0,role='body',collision='block',part='main',bevel=0):
    if role=='body' and part.startswith(('pew_','staff_rest','office_','reception_','lectern','altar','washstand')):role='furniture'
    o.name=name;o.parent=ROOT_OBJ
    o['uuid']='church_'+hashlib.sha256(name.encode()).hexdigest()[:24]
    o['rmmo_collision']=collision;o['semantic_group']=('50_' if role=='roof' else 'Church_')+part
    o['church_floor']=floor_;o['church_role']=role;o['church_part']=part
    o['rmmo_part']={'floor':floor_,'floor_y':.3+floor_*3 if part=='tower' else .3,'role':role,'part':part}
    if mat:o.data.materials.append(mat)
    if bevel:
        bpy.context.view_layer.objects.active=o
        mod=o.modifiers.new('Small dressed edge','BEVEL');mod.width=bevel;mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
        n=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');n.keep_sharp=True
        bpy.ops.object.modifier_apply(modifier=n.name)
    OBJECTS.append(o);return o

def mesh(name,verts,faces,mat,floor_=0,role='body',collision='block',part='main',bevel=0):
    data=bpy.data.meshes.new(name);data.from_pydata([coord(p) for p in verts],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    o=bpy.data.objects.new(name,data);SC.collection.objects.link(o)
    return register(o,name,mat,floor_,role,collision,part,bevel)

def box(name,center,size,mat=trim,floor_=0,role='body',collision='block',part='main',bevel=.015):
    x,y,z=center;w,h,d=[a/2 for a in size]
    verts=[(x+a*w,y+b*h,z+c*d) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    return mesh(name,verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],mat,floor_,role,collision,part,bevel)

def prism(name,poly,axis,fixed,depth,mat=stone,**kw):
    n=len(poly)
    def point(u,v,d):return (u,v,d) if axis=='z' else (d,v,u)
    verts=[point(u,v,fixed+d) for d in [-depth/2,depth/2] for u,v in poly]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,mat,**kw)

def arch(u,bottom,width,height,segments=10):
    # C02/C04 show a rounded arch, not a Gothic two-centre pointed arch.
    h=width/2;spring=bottom+height-h
    poly=[(u-h,bottom),(u-h,spring)]
    for i in range(1,segments*2+1):
        a=math.pi-i*math.pi/(segments*2);poly.append((u+h*math.cos(a),spring+h*math.sin(a)))
    poly.append((u+h,bottom));return poly

def cut(o,poly,axis,fixed,depth,name):
    cutter=prism('cutter_'+name,poly,axis,fixed,depth,None,collision='none',bevel=0)
    bpy.context.view_layer.objects.active=o
    mod=o.modifiers.new('Real opening '+name,'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    OBJECTS.remove(cutter);bpy.data.objects.remove(cutter,do_unlink=True)
    OPENINGS.append({'id':name,'axis':axis,'fixed':fixed,'polygon_uv':poly,'wall_depth':depth,'wall_object':o.name})

def beam(name,a,b,width,depth,mat=wood,floor_=0,role='body',collision='none',part='main'):
    a,b=Vector(a),Vector(b);v=b-a;n=v.normalized();cross=Vector((0,0,1)) if abs(n.z)<.9 else Vector((1,0,0));u=n.cross(cross).normalized()*width/2;w=n.cross(u).normalized()*depth/2
    verts=[tuple(p+su*u+sw*w) for p in [a,b] for su,sw in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    return mesh(name,verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,floor_,role,collision,part)

def arch_trim(name,poly,axis,fixed,width,height,u,bottom,mat=trim,floor_=0,part='main'):
    outer=arch(u,bottom-.13,width+.28,height+.30)
    inner=poly;n=len(inner)
    def p(a,d):return (a[0],a[1],d) if axis=='z' else (d,a[1],a[0])
    verts=[p(v,fixed+d) for d in [-.08,.08] for ring in [inner,outer] for v in ring]
    faces=[]
    for i in range(n):
        j=(i+1)%n;faces.extend([(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
    return mesh(name,verts,faces,mat,floor_,collision='none',part=part)

def clip(poly,a,b,c):
    out=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        u=a*p[0]+b*p[1]-c;v=a*q[0]+b*q[1]-c
        if u<=1e-8:out.append(p)
        if (u<0)!=(v<0):
            t=u/(u-v);out.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
    return out

def window(o,name,axis,fixed,u,bottom,width,height,pointed=True,floor_=0,part='main',outward=1):
    poly=arch(u,bottom,width,height) if pointed else [(u-width/2,bottom),(u+width/2,bottom),(u+width/2,bottom+height),(u-width/2,bottom+height)]
    cut(o,poly,axis,fixed,1.6,name)
    if pointed:arch_trim(name+'_stone_reveal',poly,axis,fixed+outward*.28,width,height,u,bottom,floor_=floor_,part=part)
    else:
        for x in [u-width/2-.075,u+width/2+.075]:
            c=(x,bottom+height/2,fixed+outward*.25) if axis=='z' else (fixed+outward*.25,bottom+height/2,x)
            size=(.15,height+.25,.18) if axis=='z' else (.18,height+.25,.15)
            box(name+'_stone_jamb_'+str(x),c,size,trim,floor_,part=part,collision='none')
        for y in [bottom-.065,bottom+height+.065]:
            c=(u,y,fixed+outward*.25) if axis=='z' else (fixed+outward*.25,y,u)
            size=(width+.29,.13,.20) if axis=='z' else (.20,.13,width+.29)
            box(name+'_stone_head_'+str(y),c,size,trim,floor_,part=part,collision='none')
    def pos(p):return (p[0],p[1],fixed) if axis=='z' else (fixed,p[1],p[0])
    # Reference C04: central upright, horizontal rails and alternating left/right
    # triangles, with pale violet border pieces. No diamond lattice or red/amber.
    gv=[];gf=[];gm=[];lv=[];lf=[];edges={}
    def pane(subject,mi):
        clipped=list(poly)
        area=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(subject,subject[1:]+subject[:1]))
        if area<0:subject=list(reversed(subject))
        for a,b in zip(subject,subject[1:]+subject[:1]):
            dx,dy=b[0]-a[0],b[1]-a[1]
            clipped=clip(clipped,dy,-dx,dy*a[0]-dx*a[1]) if clipped else []
        if len(clipped)<3:return
        area=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(clipped,clipped[1:]+clipped[:1]))
        if abs(area)<1e-7:return
        start=len(gv);gv.extend(pos(p) for p in clipped);gf.append(tuple(range(start,len(gv))));gm.append(mi)
        for a,b in zip(clipped,clipped[1:]+clipped[:1]):
            if math.dist(a,b)<1e-6:continue
            key=tuple(sorted((tuple(round(v,6) for v in a),tuple(round(v,6) for v in b))))
            edges[key]=(a,b)
    def rect(a,b,c,d):return [(a,c),(b,c),(b,d),(a,d)]
    edge=min(.10,width*.10);lo=u-width/2;hi=u+width/2
    rows=max(2,math.ceil(height/max(.42,width*.65)));dy=height/rows
    if name=='Main_transom':
        for i in range(4):
            a=lo+width*i/4;b=lo+width*(i+1)/4;m=(a+b)/2
            pane([(a,bottom),(b,bottom),(m,bottom+height/2)],i%3)
            pane([(a,bottom+height),(b,bottom+height),(m,bottom+height/2)],3)
            pane([(a,bottom),(a,bottom+height),(m,bottom+height/2)],(i+1)%3)
            pane([(b,bottom),(b,bottom+height),(m,bottom+height/2)],(i+2)%3)
    else:
        for j in range(rows):
            y0=bottom+j*dy;y1=y0+dy
            pane(rect(lo,lo+edge,y0,y1),3);pane(rect(hi-edge,hi,y0,y1),3)
            for k,(a,b) in enumerate([(lo+edge,u),(u,hi-edge)]):
                if (j+k)%2:
                    triangles=[[(a,y0),(b,y0),(b,y1)],[(a,y0),(b,y1),(a,y1)]]
                else:triangles=[[(a,y0),(b,y0),(a,y1)],[(b,y0),(b,y1),(a,y1)]]
                for ti,tri in enumerate(triangles):pane(tri,(j+k+ti)%3)
    for p,q in edges.values():
        d=Vector((q[0]-p[0],q[1]-p[1]));d.normalize();n=Vector((-d.y,d.x))*.018
        band=[tuple(Vector(p)+n),tuple(Vector(q)+n),tuple(Vector(q)-n),tuple(Vector(p)-n)]
        start=len(lv);lv.extend(pos(p) for p in band);lf.append(tuple(range(start,len(lv))))
    if gf:
        g=mesh(name+'_glass',gv,gf,glass[0],floor_,collision='none',part=part)
        for m in glass[1:]:g.data.materials.append(m)
        for face,mi in zip(g.data.polygons,gm):face.material_index=mi
        g['rmmo_tinted_glass']={'version':1,'materials':GLASS_SPECS}
    if lf:mesh(name+'_lead',lv,lf,lead,floor_,collision='none',part=part)

def doorway(o,name,axis,fixed,u,bottom,width,height,pointed=False):
    poly=arch(u,bottom,width,height) if pointed else [(u-width/2,bottom),(u+width/2,bottom),(u+width/2,bottom+height),(u-width/2,bottom+height)]
    cut(o,poly,axis,fixed,1.6,name)
    return poly

def door(name,axis,fixed,u,bottom,width,height,side=-1,angle=95,part='main'):
    hinge=(u+side*width/2,bottom,fixed) if axis=='z' else (fixed,bottom,u+side*width/2)
    objects=[]
    def bc(n,cu,cy,w,h,dep,mat,offs=0):
        c=(cu,cy,fixed+offs) if axis=='z' else (fixed+offs,cy,cu);sz=(w,h,dep) if axis=='z' else (dep,h,w)
        objects.append(box(name+n,c,sz,mat,part=part,bevel=.01))
    dm=doorwood if name.startswith('Main_door') else wood
    bc('_oak_core',u,bottom+height/2,width-.025,height-.035,.10,dm)
    for du in [-width/2+.075,width/2-.075]:bc('_stile_'+str(du),u+du,bottom+height/2,.15,height,.26,dm)
    for dy in [.08,height*.35,height*.52,height-.08]:bc('_rail_'+str(dy),u,bottom+dy,width,.14,.26,dm)
    # Reference: one tall upper panel, one horizontal middle panel, one lower panel.
    for dy,ph in [(height*.185,height*.255),(height*.435,height*.095),(height*.755,height*.36)]:
        pw=width-.30
        bc('_recessed_panel_'+str(dy),u,bottom+dy,pw,ph,.115,dm)
        for side_ in [-1,1]:
            bc('_panel_frame_v_'+str((dy,side_)),u+side_*(pw-.05)/2,bottom+dy,.05,ph,.205,dm)
            bc('_panel_frame_h_'+str((dy,side_)),u,bottom+dy+side_*(ph-.05)/2,pw,.05,.205,dm)
        if ph>height*.15:bc('_raised_panel_'+str(dy),u,bottom+dy,pw*.62,ph*.64,.16,dm)
    for dy in [height*.17,height*.83]:
        bc('_hidden_hinge_strap_'+str(dy),u+side*.07,bottom+dy,width*.72,.07,.025,iron,-.10)
        bc('_hinge_barrel_'+str(dy),hinge[0] if axis=='z' else hinge[2],bottom+dy,.06,.24,.07,iron,-.08)
    bc('_long_brass_handle',u-side*width*.34,bottom+height*.385,.045,height*.252,.05,brass,.19)
    for dy in [height*.271,height*.499]:bc('_brass_handle_mount_'+str(dy),u-side*width*.34,bottom+dy,.085,.085,.11,brass,.14)
    for obj in objects:
        # One mesh per complete leaf; origin is the actual hinge in engine axes.
        pass
    leaf=join(objects,name)
    shift=Vector(coord(hinge))
    for v in leaf.data.vertices:v.co-=shift
    leaf.location=shift
    leaf['rmmo_hinge']={'id':name,'pivot':[0,0,0],'angle':angle,'open':0.0}
    leaf['church_role']='door';leaf['rmmo_part']={'floor':0,'floor_y':.3,'role':'door','part':part}
    return leaf

def join(objs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join()
    dst=objs[0];dst.name=name;dst['uuid']='church_'+hashlib.sha256(name.encode()).hexdigest()[:24]
    for o in objs[1:]:
        if o in OBJECTS:OBJECTS.remove(o)
    return dst

def gable_roof(name,cx,z0,z1,half,eave,ridge,part='main'):
    for side in [-1,1]:
        x=cx+side*half
        pts=[(cx,ridge,z0),(x,eave,z0),(x,eave,z1),(cx,ridge,z1)]
        verts=pts+[(p[0],p[1]-.18,p[2]) for p in pts]
        ob=mesh(name+'_slope_'+str(side),verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],roofmat,role='roof',part=part)
        ob.data.materials.append(clay);ob.data.materials.append(wood);ob['roof_ridge_x']=cx;ob['roof_ridge_y']=ridge
        for face in ob.data.polygons:
            if face.index!=0:face.material_index=2 if face.index==1 else 1
        for z in [z0+.04,z1-.04]:beam(name+'_barge_'+str((side,z)),(cx,ridge+.025,z),(x,eave+.025,z),.16,.22,trim,role='roof',part=part)
        beam(name+'_eave_'+str(side),(x,eave-.09,z0),(x,eave-.09,z1),.17,.22,wood,role='roof',part=part)
    # Segmented convex ridge caps make a real roof silhouette without all-tile geometry.
    length=z1-z0
    for i in range(math.ceil(length/.42)):
        a=z0+i*.42;b=min(z1,a+.435);n=10;r=.16
        verts=[(cx+r*math.cos(t*math.pi/n),ridge-.01+r*math.sin(t*math.pi/n),z) for z in [a,b] for t in range(n+1)]
        faces=[(k,k+1,n+2+k,n+1+k) for k in range(n)]
        mesh(name+'_ridge_cap_'+str(i),verts,faces,clay,role='roof',collision='none',part=part)

# Main wall envelope. Corners overlap only inside solid masonry, never fill openings.
main_front=prism('Nave_front_masonry',[(-5,.3),(5,.3),(5,10.8),(0,17.6),(-5,10.8)],'z',11,.48,stone)
main_back=prism('Nave_rear_masonry',[(-5,.3),(5,.3),(5,10.8),(0,17.6),(-5,10.8)],'z',-11,.48,stone)
left=box('Nave_left_masonry',(-5,5.55,0),(.48,10.5,21.52),stone,bevel=0)
right=box('Nave_right_masonry',(5,5.55,0),(.48,10.5,21.52),stone,bevel=0)
box('Nave_flagstone_floor',(0,.14,0),(10.48,.32,22.48),floor,role='floor',collision='walk')
doorway(main_front,'main_door_opening','z',11,0,.3,2.4,3.25)
door('Main_door_left','z',11.08,-.6,.3,1.2,3.25,-1,100)
door('Main_door_right','z',11.08,.6,.3,1.2,3.25,1,-100)
window(main_front,'Main_transom','z',11,0,3.65,2.38,.46,False)
for x in [-3.3,3.3]:window(main_front,'Front_lower_'+str(x),'z',11,x,1.35,.85,1.85,False)
for x,w,h in [(0,1.65,4.4),(-2.4,.90,2.6),(2.4,.90,2.6)]:window(main_front,'Front_lancet_'+str(x),'z',11,x,11.1,w,h)
for z in [-7.5,-3.75,0,3.75,7.5]:window(right,'Nave_east_'+str(z),'x',5,z,3.1,1.15,3.3,True,outward=1)
for z in [-1.5,4.4,8.2]:window(left,'Nave_clerestory_'+str(z),'x',-5,z,7.5,1.05,2.6,True,outward=-1)
for x in [-2.6,0,2.6]:window(main_back,'Rear_lancet_'+str(x),'z',-11,x,4.2,1.25,4.0,True,outward=-1)
portal=doorway(left,'side_hall_connection','x',-5,.3,.3,2.0,3.5,True)
arch_trim('Side_hall_interior_portal',portal,'x',-4.7,2,3.5,.3,.3)

# Low side chapel: its right boundary is the nave's actual thick shared wall.
ann_front=prism('Side_chapel_front',[(-10.6,.3),(-5,.3),(-5,4.8),(-7.8,7.6),(-10.6,4.8)],'z',8,.44,stone,part='side_hall')
ann_left=box('Side_chapel_west',(-10.6,2.55,2.05),(.44,4.5,11.9),stone,part='side_hall',bevel=0)
box('Side_chapel_floor',(-7.8,.14,2.05),(5.6,.32,11.9),floor,role='floor',collision='walk',part='side_hall')
for x in [-9.15,-6.45]:window(ann_front,'Chapel_front_'+str(x),'z',8,x,1.2,.75,1.7,False,part='side_hall')
for z in [-1.7,2.0,5.7]:window(ann_left,'Chapel_west_'+str(z),'x',-10.6,z,1.2,.8,1.8,False,part='side_hall',outward=-1)
gable_roof('Side_chapel_roof',-7.8,-4.05,8.5,3.0,4.68,7.68,'side_hall')
# A continuous lead wall-abutment flashing sits on the low roof's east eave.
box('Side_chapel_abutment_flashing',(-5.02,4.99,2.13),(.14,.30,12.40),lead,role='roof',collision='none',part='side_hall',bevel=.008)

# Tower, five stone stages plus top lantern-room walls. Solid walls split by floor.
TOWER=[]
levels=[.3,3.3,6.3,9.3,12.3,15.3,17.6]
for f,(lo,hi) in enumerate(zip(levels[:-1],levels[1:])):
    walls={}
    for axis,fixed,span,c in [('z',-3.9,5.6,-7.8),('z',-9.5,5.6,-7.8),('x',-10.6,5.12,-6.7),('x',-5,5.12,-6.7)]:
        # The nave already supplies this shared wall; do not overlay a second skin.
        lower=lo
        if axis=='x' and fixed==-5:
            if hi<=10.8:continue
            lower=max(lo,10.8)
        cen=(c,(lower+hi)/2,fixed) if axis=='z' else (fixed,(lower+hi)/2,c)
        siz=(span,hi-lower,.48) if axis=='z' else (.48,hi-lower,span)
        o=box('Tower_f'+str(f)+'_'+axis+str(fixed),cen,siz,stone,f,part='tower',bevel=0);walls[(axis,fixed)]=o
    TOWER.append(walls)
box('Tower_ground_floor',(-7.8,.14,-6.7),(5.6,.32,5.6),floor,role='floor',collision='walk',part='tower')
doorway(TOWER[0][('z',-3.9)],'tower_to_chapel','z',-3.9,-6.05,.3,1.4,2.95)
# Side exterior opening is aligned with the level entry landing, not a stair flight.
side_poly=doorway(TOWER[0][('x',-10.6)],'tower_external_entry','x',-10.6,-4.85,.3,1.55,2.95,True)
arch_trim('Tower_side_portal_arch',side_poly,'x',-10.9,1.55,2.95,-4.85,.3,part='tower')
side_leaf=prism('Tower_side_door',arch(-4.85,.32,1.51,2.90),'x',-10.63,.13,wood,role='door',part='tower')
hinge=Vector(coord((-10.63,.3,-5.625)))
for v in side_leaf.data.vertices:v.co-=hinge
side_leaf.location=hinge;side_leaf['rmmo_hinge']={'id':'Tower_side_door','pivot':[0,0,0],'angle':-100,'open':0.0}
side_hardware=[]
for y in [.85,1.65]:
    side_hardware.append(box('Tower_door_hinge_'+str(y),(-10.74,y,-5.61),(.07,.22,.07),iron,role='door',part='tower',bevel=.005))
    side_hardware.append(box('Tower_door_strap_'+str(y),(-10.72,y,-5.28),(.03,.07,.66),iron,role='door',part='tower',bevel=.004))
side_hardware.append(box('Tower_door_brass_pull',(-10.78,1.52,-4.36),(.055,.42,.045),brass,role='door',part='tower',bevel=.007))
side_leaf=join([side_leaf]+side_hardware,'Tower_side_door')
for axis,fixed,u in [('z',-3.9,-7.8),('z',-9.5,-7.8),('x',-10.6,-6.7),('x',-5,-6.7)]:
    # Windows fit completely between floors; low nave-facing windows are omitted
    # where the nave wall actually occludes the tower elevation.
    for f,bottom,h in [(2,6.65,2.15),(4,12.55,4.6)]:
        if axis=='x' and fixed==-5 and f<4:continue
        outward=1 if fixed in [-3.9,-5] else -1
        width=.95 if f==2 else 1.35
        window(TOWER[f][(axis,fixed)],'Tower_lancet_'+str((axis,fixed,f)),axis,fixed,u,bottom,width,h,True,f,'tower',outward)
        if f==4:cut(TOWER[5][(axis,fixed)],arch(u,bottom,width,h),axis,fixed,1.6,'Tower_upper_continuous_'+str((axis,fixed)))

# Internal U stairs: each storey 3m, two 1.5m rises, 9 risers / flight.
# 0.1667m rise x 0.27m tread, 1.35m clear width; 1m level landing at both ends.
for f in range(5):
    base=.3+3*f
    for side,x in [('left',-8.95),('right',-6.65)]:
        for i in range(9):
            top=base+(i+1)/6+(1.5 if side=='right' else 0)
            z=-5.34-(i+.5)*.27 if side=='left' else -7.77+(i+.5)*.27
            box('Tower_step_'+str((f,side,i)),(x,top-.075,z),(1.35,.15,.285),wood,f,role='stairs',collision='walk',part='tower',bevel=.007)
        z0,z1=(-5.34,-7.77) if side=='left' else (-7.77,-5.34)
        y0,y1=(base,base+1.5) if side=='left' else (base+1.5,base+3)
        for dx in [-.59,.59]:beam('Tower_stringer_'+str((f,side,dx)),(x+dx,y0-.10,z0),(x+dx,y1-.10,z1),.12,.20,wood,f,part='tower')
        # Both flight edges are guarded: neither is directly against the wall.
        for dx in [-.72,.72]:
            beam('Tower_handrail_'+str((f,side,dx)),(x+dx,y0+1.05,z0),(x+dx,y1+1.05,z1),.065,.065,wood,f,collision='block',part='tower')
            for t in [0,.25,.5,.75,1]:
                z=z0+(z1-z0)*t;y=y0+(y1-y0)*t
                box('Tower_baluster_'+str((f,side,dx,t)),(x+dx,y+.52,z),(.055,1.04,.055),wood,f,part='tower',bevel=0)
    box('Tower_half_landing_'+str(f),(-7.8,base+1.5-.09,-8.43),(4.6,.18,1.32),wood,f,role='floor',collision='walk',part='tower')
    box('Tower_upper_landing_'+str(f),(-7.8,base+3-.09,-4.87),(4.6,.18,1.06),wood,f+1,role='floor',collision='walk',part='tower')
    # Back landing side rails protect the open centre while keeping flight entries.
    beam('Tower_landing_guard_'+str(f),(-8.20,base+2.55,-7.80),(-7.39,base+2.55,-7.80),.06,.06,wood,f,collision='block',part='tower')
    for x in [-8.20,-7.39]:box('Tower_half_landing_guard_post_'+str((f,x)),(x,base+2.025,-7.8),(.06,1.05,.06),wood,f,part='tower',bevel=0)
    span=(-10.08,-7.39) if f==4 else (-8.20,-7.39)
    beam('Tower_front_landing_guard_'+str(f),(span[0],base+4.05,-5.40),(span[1],base+4.05,-5.40),.06,.06,wood,f+1,collision='block',part='tower')
    for k in range(math.ceil((span[1]-span[0])/.40)+1):
        x=span[0]+(span[1]-span[0])*k/math.ceil((span[1]-span[0])/.40)
        box('Tower_front_landing_guard_post_'+str((f,k)),(x,base+3.525,-5.4),(.055,1.05,.055),wood,f+1,part='tower',bevel=0)
for f,y in enumerate([3.3,6.3,9.3,12.3,15.3]):
    for axis,fixed,u,span in [('z',-3.9,-7.8,5.83),('z',-9.5,-7.8,5.83),('x',-10.6,-6.7,5.82),('x',-5,-6.7,5.82)]:
        c=(u,y-.08,fixed) if axis=='z' else (fixed,y-.08,u);s=(span,.19,.67) if axis=='z' else (.67,.19,span)
        box('Tower_stringcourse_'+str((f,axis,fixed)),c,s,trim,f+1,part='tower',collision='none')
for x in [-10.53,-5.07]:
    for z in [-9.44,-3.96]:
        for f,(lo,hi) in enumerate(zip(levels[:-1],levels[1:])):box('Tower_quoin_'+str((x,z,f)),(x,(lo+hi)/2,z),(.28,hi-lo,.28),trim,f,part='tower',collision='none')

# Four triangular sloping roof faces over a solid square tower roof deck.
cx,cz=-7.8,-6.7;corners=[(-10.95,17.63,-9.85),(-4.65,17.63,-9.85),(-4.65,17.63,-3.55),(-10.95,17.63,-3.55)];top=(cx,24.8,cz)
for i in range(4):
    a,b=corners[i],corners[(i+1)%4]
    ob=mesh('Tower_pyramid_roof_'+str(i),[a,b,top,(a[0],a[1]-.18,a[2]),(b[0],b[1]-.18,b[2]),(cx,24.62,cz)],[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],roofmat,5,'roof','block','tower')
    ob.data.materials.append(clay)
    for face in ob.data.polygons:
        if face.index!=0:face.material_index=1
    beam('Tower_hip_cap_'+str(i),a,top,.12,.14,clay,5,'roof','none','tower')
    beam('Tower_eave_'+str(i),a,b,.2,.23,wood,5,'roof','none','tower')
beam('Tower_spire_finial',top,(cx,25.45,cz),.055,.055,brass,5,'roof','none','tower')
gable_roof('Nave_roof',0,-11.5,11.5,5.5,10.20,17.68)
for o in list(OBJECTS):
    if o.name=='Nave_roof_slope_-1':
        # Roof abuts the tower wall, never projects inside its stairwell.
        cut(o,[(-11.2,9.9),(-5.23,9.9),(-5.23,18.1),(-11.2,18.1)],'z',-6.7,5.6,'tower_roof_abutment')
beam('Front_gable_finial',(0,17.66,11.48),(0,19.05,11.48),.048,.048,brass,role='roof')

# Façade courses and corner pilasters, real cornice thickness, base plinths.
for z in [-11.27,11.27]:
    for y,h,w in [(10.67,.24,10.52),(10.39,.11,10.32),(.48,.32,10.52)]:
        # Ground stringcourse avoids the doorway, leaving the real threshold open.
        if z>0 and y<1:
            for x in [-3.2,3.2]:box('Front_plinth_'+str(x),(x,y,z),(3.6,h,.22),trim,collision='none')
        else:box('Nave_end_course_'+str((z,y)),(0,y,z),(w,h,.24),trim,collision='none')
for x in [-4.9,4.9]:
    for z in [-11.25,11.25]:box('Nave_corner_pilaster_'+str((x,z)),(x,5.55,z),(.32,10.5,.30),trim,collision='none')
for z in [-8,-3,2,7]:
    # Discrete shallow buttresses on the exposed long nave side carry roof thrust.
    box('East_buttress_'+str(z),(5.28,3.7,z),(.56,6.8,.48),stone,bevel=.025)
    box('East_buttress_weathering_'+str(z),(5.29,7.13,z),(.58,.13,.52),trim,collision='none')

# Portal mouldings and projecting hood carried by two small corbels.
for x in [-1.37,1.37]:
    box('Main_portal_pier_'+str(x),(x,2.25,11.31),(.30,3.9,.43),trim)
    box('Main_portal_foot_'+str(x),(x,.42,11.34),(.42,.24,.54),trim)
    beam('Main_portal_corbel_'+str(x),(x,3.91,11.25),(x,4.3,11.82),.26,.27,trim,collision='none')
box('Main_portal_lintel',(0,4.25,11.36),(3.18,.22,.52),trim)
box('Main_portal_hood',(0,4.49,11.55),(3.62,.24,1.02),trim)
for i in range(2):box('Main_entrance_step_'+str(i),(0,(i+1)*.15/2,12.2-i*.37),(3.6,(i+1)*.15,1.9-i*.74),floor,role='floor',collision='walk')
box('Side_door_threshold',(-10.9,.15,-4.85),(.7,.30,2),floor,role='floor',collision='walk',part='tower')

# Exposed oak trusses, not a solid ceiling blocking the high interior volume.
for z in [-8.5,-4.25,0,4.25,8.5]:
    beam('Nave_tie_'+str(z),(-4.68,10.25,z),(4.68,10.25,z),.24,.28,wood,role='roof')
    for side in [-1,1]:
        beam('Nave_rafter_'+str((z,side)),(side*4.7,10.65,z),(0,17.30,z),.20,.23,wood,role='roof')
        beam('Nave_brace_'+str((z,side)),(side*4.4,10.3,z),(side*1.4,15.4,z),.15,.18,wood,role='roof')
    beam('Nave_kingpost_'+str(z),(0,10.25,z),(0,17.30,z),.20,.20,wood,role='roof')
beam('Nave_ridge_purlin',(0,17.34,-10.8),(0,17.34,10.8),.24,.26,wood,role='roof')

# Interior basic furnishings: six pew rows, a broad centre aisle and sanctuary.
for row,z in enumerate([6.0,3.8,1.6,-.6,-2.8,-5.0]):
    for side in [-1,1]:
        x=side*2.95;part='pew_'+str((row,side))
        box(part+'_seat',(x,.82,z),(2.65,.12,.48),wood,part=part)
        box(part+'_back',(x,1.17,z+.22),(2.65,.68,.10),wood,part=part)
        for dx in [-1.15,1.15]:box(part+'_leg'+str(dx),(x+dx,.56,z),(.16,.53,.49),wood,part=part)
box('Sanctuary_step_lower',(0,.375,-8.78),(8.7,.15,3.6),floor,role='floor',collision='walk')
box('Sanctuary_step_upper',(0,.525,-9.0),(8.3,.15,3.15),floor,role='floor',collision='walk')
box('Altar_tabletop',(0,1.57,-9.0),(2.7,.23,1.05),trim,part='altar')
for x in [-.9,.9]:box('Altar_pier_'+str(x),(x,1.02,-9),(.42,.90,.74),trim,part='altar')
box('Altar_plinth',(0,.70,-9),(2.5,.20,1.0),trim,part='altar')
box('Lectern_foot',(-3.2,.66,-7.7),(.70,.12,.60),wood,part='lectern')
box('Lectern_stem',(-3.2,1.12,-7.7),(.18,.84,.18),wood,part='lectern')
beam('Lectern_sloped_desk',(-3.2,1.55,-7.95),(-3.2,1.36,-7.35),.75,.09,wood,part='lectern')

# Side wing supplementary functional plan: a continuous 1.65m corridor links
# nave and tower, with service rooms opening off it. No invented religious emblem.
service_wall=box('Service_corridor_partition',(-6.94,1.95,2.05),(.14,3.3,11.8),wood,part='service',bevel=0)
for z in [-1.8,1.95,5.8]:
    doorway(service_wall,'Service_doorway_'+str(z),'x',-6.94,z,.3,1.30,2.85)
    door('Service_door_'+str(z),'x',-6.94,z,.3,1.28,2.82,-1,-95,'service')
for z in [.1,3.75]:box('Service_cross_partition_'+str(z),(-8.66,1.95,z),(3.3,3.3,.14),wood,part='service')
for z in [-1.7,2.0,5.7]:box('Service_room_ceiling_'+str(z),(-8.66,3.65,z),(3.3,.14,3.5),wood,role='ceiling',part='service')
# Staff rest bay: bed and storage, kept clear of its door and the corridor.
linen=material('Church unbleached linen',(.64,.60,.49),0,.91)
box('Rest_bed_frame',(-9.4,.55,-1.7),(1.25,.32,2.05),wood,part='staff_rest')
box('Rest_mattress',(-9.4,.81,-1.7),(1.18,.25,1.98),linen,part='staff_rest',bevel=.07)
box('Rest_pillow',(-9.4,1.0,-2.40),(.75,.18,.42),linen,part='staff_rest',bevel=.06)
# Office desk, chair and book shelving; all self-contained reusable nodes.
box('Office_desk_top',(-9.10,1.12,1.70),(1.75,.10,.78),wood,part='office_desk')
for x in [-9.83,-8.37]:
    for z in [1.43,1.97]:box('Office_desk_leg_'+str((x,z)),(x,.69,z),(.09,.78,.09),wood,part='office_desk')
box('Office_chair_seat',(-8.8,.80,2.50),(.52,.10,.52),wood,part='office_chair')
box('Office_chair_back',(-8.8,1.1,2.74),(.52,.65,.08),wood,part='office_chair')
for x in [-9.0,-8.6]:
    for z in [2.3,2.7]:box('Office_chair_leg_'+str((x,z)),(x,.55,z),(.07,.45,.07),wood,part='office_chair')
for y in [.45,1.05,1.65,2.25]:box('Office_shelf_'+str(y),(-10.19,y,2.9),(.30,.07,1.3),wood,part='office_shelf')
for z in [2.24,3.56]:box('Office_shelf_post_'+str(z),(-10.19,1.37,z),(.30,1.95,.07),wood,part='office_shelf')
# Reception/alms counter and waiting bench in front room.
box('Reception_counter_top',(-9.15,1.30,6.25),(1.8,.12,.7),wood,part='reception_counter')
box('Reception_counter_panel',(-9.15,.83,6.54),(1.75,.85,.08),wood,part='reception_counter')
for x in [-9.96,-8.34]:box('Reception_counter_leg_'+str(x),(x,.80,6.25),(.12,.94,.58),wood,part='reception_counter')
box('Reception_waiting_bench',(-9.2,.77,4.3),(1.8,.12,.43),wood,part='reception_bench')
for x in [-9.9,-8.5]:box('Reception_waiting_leg_'+str(x),(x,.52,4.3),(.12,.45,.40),wood,part='reception_bench')
# Wash/linen cabinet sits beside the staff bed: hollow cupboard, movable doors,
# and an actual open bowl. This is a washstand, not a modern plumbed bathroom.
for x in [-8.18,-7.24]:box('Wash_cabinet_side_'+str(x),(x,.84,-3.20),(.08,1.08,.58),wood,part='washstand')
for y in [.34,1.38]:box('Wash_cabinet_slab_'+str(y),(-7.71,y,-3.2),(1.02,.08,.58),wood,part='washstand')
box('Wash_cabinet_back',(-7.71,.86,-3.48),(.94,1.04,.05),wood,part='washstand')
door('Wash_cabinet_door','z',-2.91,-7.71,.38,.90,.94,-1,95,'washstand')
verts=[];faces=[];profile=[(.0,1.435),(.16,1.445),(.27,1.52),(.31,1.67),(.285,1.68),(.245,1.54),(.145,1.48),(.0,1.47)]
for r,y in profile:
    for i in range(32):a=math.tau*i/32;verts.append((-7.71+r*math.cos(a),y,-3.20+r*math.sin(a)))
for j in range(len(profile)-1):
    for i in range(32):k=j*32+i;n=j*32+(i+1)%32;faces.append((k,n,n+32,k+32))
mesh('Washstand_open_stone_basin',verts,faces,trim,collision='none',part='washstand')

def lantern(name,x,y,z,outward=1,yaw=0,indoor=False):
    parent=bpy.data.objects.new(name,None);SC.collection.objects.link(parent);parent.parent=ROOT_OBJ
    parent['rmmo_light_socket']={'position':[x,y,z],'color':[1,.91,.78],'range':4.5,'energy':.65,'flame':False,'indoor':indoor}
    members=[]
    members.append(box(name+'_mount',(x,y-.08,z-outward*.26),(.18,.48,.10),brass,collision='none',part=name))
    # Reference scroll bracket: curved arm meets lantern underside and wall plate.
    arm=[]
    for i in range(17):
        t=i/16;arm.append((x,y-.34-.20*math.sin(t*math.pi),z-outward*(.27-.27*t)))
    for i in range(len(arm)-1):members.append(beam(name+'_scroll_arm_'+str(i),arm[i],arm[i+1],.045,.045,brass,part=name))
    for dx in [-.18,.18]:
        for dz in [-.14,.14]:members.append(box(name+'_frame_'+str((dx,dz)),(x+dx,y,z+dz),(.035,.62,.035),brass,collision='none',part=name))
    members.append(box(name+'_base',(x,y-.33,z),(.44,.06,.35),brass,collision='none',part=name))
    members.append(prism(name+'_canopy',[(x-.24,y+.30),(x+.24,y+.30),(x,y+.52)],'z',z,.39,brass,collision='none',part=name))
    verts=[(x-.155,y-.28,z-.13),(x+.155,y-.28,z-.13),(x+.155,y+.28,z-.13),(x-.155,y+.28,z-.13),(x-.155,y-.28,z+.13),(x+.155,y-.28,z+.13),(x+.155,y+.28,z+.13),(x-.155,y+.28,z+.13)]
    pane=mesh(name+'_clear_glass',verts,[(0,1,2,3),(4,7,6,5),(0,3,7,4),(1,5,6,2)],clear,collision='none',part=name)
    # Thin neutral transmission plus dielectric reflection; no milky alpha-lit face.
    pane['rmmo_tinted_glass']={'version':1,'materials':{clear.name:{'transmittance':[.97,.985,.98],'roughness':.10}}}
    members.append(pane)
    verts=[(x,y+.18,z),(x,y-.18,z),(x-.075,y,z),(x+.075,y,z),(x,y,z-.075),(x,y,z+.075)]
    diamond=mesh(name+'_floating_diamond',verts,[(0,2,4),(0,4,3),(0,3,5),(0,5,2),(1,4,2),(1,3,4),(1,5,3),(1,2,5)],glow_facets[0],collision='none',part=name)
    for m in glow_facets[1:]:diamond.data.materials.append(m)
    for i,face in enumerate(diamond.data.polygons):face.material_index=[0,1,3,2,1,2,0,3][i]
    members.append(diamond)
    transform=Matrix.Translation(Vector(coord((x,y,z)))) @ Matrix.Rotation(math.radians(yaw),4,'Z') @ Matrix.Translation(-Vector(coord((x,y,z))))
    for m in members:
        m.parent=parent
        if yaw:m.data.transform(transform);m.data.update()
    hardware=[m for m in members if m.data.materials[0] not in [clear,glow]+glow_facets]
    if len(hardware)>1:
        hardware_merged=join(hardware,name+'_brass_frame');hardware_merged.parent=parent
for x in [-1.91,1.91]:lantern('Portal_lantern_'+str(x),x,2.7,11.55)
for x in [-4.49,4.49]:
    for z in [-6.5,5.8]:lantern('Nave_lantern_'+str((x,z)),x,3.7,z,1,90 if x<0 else -90,True)

# UVs generated by measured world metres. Roof UV follows true slope distance.
for o in list(OBJECTS):
    if o.type!='MESH':continue
    uv=o.data.uv_layers.new(name='MetresUV')
    for face in o.data.polygons:
        normal=godot(face.normal);mi=face.material_index;m=o.data.materials[mi] if len(o.data.materials)>mi else None
        coords=[godot(o.matrix_world@o.data.vertices[o.data.loops[i].vertex_index].co) for i in face.loop_indices]
        roof_face=m==roofmat
        if roof_face:
            # U follows a horizontal contour, V points uphill along this roof face.
            uphill=Vector((0,1,0))-normal*normal.y;uphill.normalize()
            across=uphill.cross(normal).normalized()
            for li,p in zip(face.loop_indices,coords):uv.data[li].uv=(p.dot(across)/3,p.dot(uphill)/2.16)
        else:
            tile=(.8,2.4) if m==wood else (2,2) if m in [stone,floor] else (1,1)
            for li,p in zip(face.loop_indices,coords):
                if abs(normal.y)>.7:a,b=p.x,p.z
                elif abs(normal.x)>abs(normal.z):a,b=p.z,p.y
                else:a,b=p.x,p.y
                uv.data[li].uv=(a/tile[0],b/tile[1])

# Merge only compatible static pieces. Floor/role, furniture identity, optics,
# and every complete moving leaf remain independently editable.
groups={}
for o in list(OBJECTS):
    if o.get('rmmo_hinge') or o.parent!=ROOT_OBJ:continue
    optics='glass' if o.get('rmmo_tinted_glass') else 'opaque'
    key=(int(o['church_floor']),str(o['church_role']),str(o['rmmo_collision']),str(o['church_part']),optics)
    groups.setdefault(key,[]).append(o)
for key,obs in groups.items():
    name='Church_'+('_'.join(map(str,key))).replace(' ','')
    ob=join(obs,name) if len(obs)>1 else obs[0]
    if key[-1]=='glass':ob['rmmo_tinted_glass']={'version':1,'materials':GLASS_SPECS}

for o in OBJECTS:
    if o.type!='MESH':continue
    # Explicit triangulation before export binds audit numbers to the actual file.
    bpy.context.view_layer.objects.active=o
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8);bm.to_mesh(o.data);bm.free()
    mod=o.modifiers.new('Game triangulation','TRIANGULATE');mod.quad_method='BEAUTY';mod.ngon_method='BEAUTY';bpy.ops.object.modifier_apply(modifier=mod.name)
    PARTS.append({'name':o.name,'uuid':o['uuid'],'floor':int(o['church_floor']),'role':str(o['church_role']),'part':str(o['church_part']),'collision':str(o['rmmo_collision']),'triangles':len(o.data.polygons),'hinge':o['rmmo_hinge'].to_dict() if o.get('rmmo_hinge') else None})

regions=[{'id':'nave','floor':0,'min':[-4.75,.3,-10.75],'max':[4.75,10.5,10.75]},{'id':'side_hall','floor':0,'min':[-10.35,.3,-3.65],'max':[-5.25,4.6,7.75]}]
regions += [{'id':'tower_'+str(f),'floor':f,'min':[-10.35,levels[f],-9.25],'max':[-5.25,levels[f+1],-4.15]} for f in range(6)]
ROOT_OBJ['rmmo_building']={'version':1,'regions':regions}
SC.render.engine='CYCLES';SC.cycles.device='CPU'
blend=OUT/'axel_church_master.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
glb=OUT/'axel_church.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=False,export_extras=True,export_yup=True,export_apply=False,export_animations=False,export_tangents=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
shutil.copy2(__file__,OUT/'build_blender_axel_church_20261016.py')
data=glb.read_bytes();n=struct.unpack_from('<I',data,12)[0];gltf=json.loads(data[20:20+n]);bin_start=28+n;blob=data[bin_start:]
def accessor(i):
    a=gltf['accessors'][i];v=gltf['bufferViews'][a['bufferView']];dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];stride=v.get('byteStride',np.dtype(dtype).itemsize*dim)
    return np.ndarray((a['count'],dim),dtype=dtype,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(stride,np.dtype(dtype).itemsize)).copy()
stats={'triangles':0,'vertices':0,'zero_area_triangles':0,'missing_uv_primitives':0,'missing_tangent_pbr_primitives':0,'finite':True,'meshes':len(gltf.get('meshes',[])),'materials':len(gltf.get('materials',[])),'mesh_primitives':0}
for mesh_ in gltf.get('meshes',[]):
    for p in mesh_['primitives']:
        stats['mesh_primitives']+=1;pos=accessor(p['attributes']['POSITION']);inds=accessor(p['indices']).ravel();stats['triangles']+=len(inds)//3;stats['vertices']+=len(pos)
        triangles=pos[inds.reshape(-1,3)];areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)
        stats['zero_area_triangles']+=int(np.count_nonzero(areas<1e-10));stats['finite']&=bool(np.isfinite(pos).all())
        stats['missing_uv_primitives']+=int('TEXCOORD_0' not in p['attributes'])
        mat=gltf['materials'][p['material']]
        stats['missing_tangent_pbr_primitives']+=int('normalTexture' in mat and 'TANGENT' not in p['attributes'])
mins=np.array([1e10]*3);maxs=-mins
for o in OBJECTS:
    for v in o.data.vertices:
        p=np.array(godot(o.matrix_world@v.co));mins=np.minimum(mins,p);maxs=np.maximum(maxs,p)
textures=[]
for im in gltf.get('images',[]):
    v=gltf['bufferViews'][im['bufferView']];b=blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
    textures.append({'name':im.get('name',''),'mime':im.get('mimeType'),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
manifest={'asset_id':'axel_church','label':'阿克塞尔教会 · 方塔与低侧厅','version':ARGS.version,'source':{'blend':str(blend),'blend_sha256':sha(blend),'blend_bytes':blend.stat().st_size,'glb':str(glb),'sha256':sha(glb),'bytes':len(data),'builder_sha256':sha(__file__)},'axes':{'up':'+Y','front':'+Z'},'bounds':{'min':mins.tolist(),'max':maxs.tolist(),'size':(maxs-mins).tolist()},'entrances':[{'id':'main','position':[0,.3,11.24],'outward':[0,0,1],'clear_width':2.4,'clear_height':3.25},{'id':'tower_side','position':[-10.84,.3,-4.85],'outward':[-1,0,0],'clear_width':1.55,'clear_height':2.95}],'parts':PARTS,'regions':regions,'opening_count':len(OPENINGS),'openings':OPENINGS,'geometry':stats,'images':textures,'inputs':INPUTS,'semantics_status':'Explicit floor/role/regions retained; root integrator adding generic imported-building consumption; no guild stage spoof','review':{'resource':'CPU candidate audited; runtime pending','visual':'PENDING_ROOT_GPU_REVIEW','pipeline':'PENDING_ROOT_IMPORT_SAVE_REOPEN','formal_library':'NOT_PUBLISHED','formal_map':'NOT_IN_SCOPE'},'design_scope':'Exterior based on exact church reference; rear elevation, nave, pews, sanctuary, side chapel and tower stairs are project supplemental design. No bell copied or inferred from unseen reference.','optimization':'Static compatible mesh groups per floor/role/part, modest bevels, 2K shared project PBR, real openings; no destructive decimation. LOD decision pending actual near/mid/far inspection.','map_modified':False}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(REVIEW/'cpu_audit.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'source':manifest['source'],'bounds':manifest['bounds'],'geometry':stats,'manifest':str(OUT/'manifest.json')},ensure_ascii=False))
if not stats['finite'] or stats['missing_tangent_pbr_primitives'] or stats['zero_area_triangles']:raise RuntimeError('CPU geometry gate failed; retain rejected candidate')
