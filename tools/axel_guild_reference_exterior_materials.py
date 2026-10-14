"""Portable exterior PBR corrections; no reference image is altered or sampled.

Call after geometry changes. Writes only newly authored material maps below
repair_v3/materials by default; does not save the mother or export the scene.
The historical materials remain available for rollback in the input mother.
"""
from pathlib import Path
import math
import bpy
import numpy as np
from mathutils import Vector

DEFAULT_OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
CLAY_SOURCE=Path('D:/code/rmmo_runtime/packs/default/assets/materials/walls/natural_red_brick')


def _principled(mat):
    return next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')


def _map(out,name,pixels,color=False):
    pixels=np.asarray(pixels,np.float32)
    if pixels.ndim==2:pixels=np.repeat(pixels[:,:,None],3,axis=2)
    h,w=pixels.shape[:2]
    rgba=np.ones((h,w,4),np.float32);rgba[:,:,:3]=np.clip(pixels,0,1)
    image=bpy.data.images.new(name,width=w,height=h,alpha=False)
    image.colorspace_settings.name='sRGB' if color else 'Non-Color'
    image.pixels.foreach_set(np.flipud(rgba).ravel())
    image.filepath_raw=str(out/(name+'.png'));image.file_format='PNG';image.save();image.pack()
    return image


def _link(mat,image,socket,strength=.2):
    nt=mat.node_tree;p=_principled(mat)
    for link in list(p.inputs[socket].links):nt.links.remove(link)
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='REPEAT'
    if socket=='Normal':
        nm=nt.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=strength
        nt.links.new(tex.outputs['Color'],nm.inputs['Color']);nt.links.new(nm.outputs['Normal'],p.inputs[socket])
    else:nt.links.new(tex.outputs['Color'],p.inputs[socket])


def _copy_replace(name):
    old=bpy.data.materials.get(name)
    if old is None:return None,[]
    new=old.copy();new.name=name+' | reference 20261013'
    new['reference_revision']='20261013';new['reference_material_design']='Measured-looking technical PBR variation; no official measured material claim'
    changed=[]
    for mesh in bpy.data.meshes:
        slots=[i for i,m in enumerate(mesh.materials) if m==old]
        if not slots:continue
        for i in slots:mesh.materials[i]=new
        changed.append((mesh,slots))
    return new,changed


def _normal(height,amount):
    dx=(np.roll(height,-1,1)-np.roll(height,1,1))*amount
    dy=(np.roll(height,-1,0)-np.roll(height,1,0))*amount
    normal=np.stack([-dx,dy,np.ones_like(dx)],axis=2)
    normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    return normal*.5+.5


def _fishscale_relief_normal(n=2048,clay_normal=None):
    """OpenGL tangent normals from a metre-scaled, periodic roof heightfield.

    The tile ownership/mask is exactly the colour map's original fishscale
    layout. Heights only describe shading relief; no displacement is exported.
    Array row-down becomes tangent +V-up when the PNG is saved by _map.
    """
    yy,xx=np.mgrid[0:n,0:n].astype(np.float32)
    x=xx/n*12;y=yy/n*18
    height=np.zeros((n,n),np.float32)
    sample_u=np.zeros_like(height);sample_v=np.zeros_like(height)
    sample_variant=np.zeros((n,n),np.int32)
    for row in range(19,-3,-1):
        shift=(row%2)*.5;col=np.floor(x-shift+.5);dx=x-shift-col
        tip=row+.55+np.sqrt(np.maximum(0,.25-dx*dx))*1.50
        mask=(y>=row-.6)&(y<=tip)
        # Fired clay: 5mm transverse camber, a shallow downslope lift and
        # a rounded 4mm lip. Unlike the previous arbitrary-pixel gradient,
        # this has broad face response as well as a narrow joint response.
        progress=np.clip((y-row+.6)/1.9,0,1)
        camber=.005*np.maximum(0,1-(2*dx)**2)
        lip=.004*np.exp(-((tip-y)/.14)**2)
        rim_m=np.minimum((.5-np.abs(dx))*.25,np.maximum(0,tip-y)*.12)
        bevel=np.clip(rim_m/.004,0,1);bevel=bevel*bevel*(3-2*bevel)
        h=.012+.012*progress+camber+lip-.004*(1-bevel)
        height[mask]=h[mask]
        sample_u[mask]=(dx+.5)[mask]
        sample_v[mask]=progress[mask]
        sample_variant[mask]=(col.astype(np.int32)+row*3)[mask]
    # A tiny periodic reconstruction filter gives the overlap a finite edge
    # width at 2K; it avoids an unphysical one-pixel 90-degree normal spike.
    for axis in (0,1):
        height=(np.roll(height,1,axis)+2*height+np.roll(height,-1,axis))*.25
    sx=(np.roll(height,-1,1)-np.roll(height,1,1))/(2*3.0/n)
    sy=(np.roll(height,-1,0)-np.roll(height,1,0))/(2*2.16/n)
    slope=np.stack([-sx,sy],axis=2)
    # Fine mineral normals are already converted from DX once by the sampler.
    if clay_normal is None:
        _,_,clay_normal=_sample_clay(sample_u,sample_v,sample_variant)
    grain=clay_normal*2-1
    slope+=grain[:,:,:2]/np.maximum(grain[:,:,2:3],.35)*.30
    magnitude=np.linalg.norm(slope,axis=2,keepdims=True)
    slope*=np.minimum(1,1.60/np.maximum(magnitude,1e-8))
    normal=np.concatenate([slope,np.ones((n,n,1),np.float32)],axis=2)
    normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    return normal*.5+.5


def _noise(n,seed,sigma):
    rng=np.random.default_rng(seed)
    frequency=np.fft.fftfreq(n).astype(np.float32)
    kernel=np.exp(-2*math.pi**2*sigma**2*(frequency[:,None]**2+frequency[None,:]**2))
    field=np.fft.ifft2(np.fft.fft2(rng.normal(size=(n,n)))*kernel).real.astype(np.float32)
    return np.clip(field/(field.std()*3),-1,1)


def _metre_uv(ob,face,tile=(1,1),slope=False):
    """Use an actual face-plane basis, never collapsed inherited side UVs."""
    matrix=ob.matrix_world;normal=(matrix.to_3x3().inverted().transposed()@face.normal).normalized()
    if slope:
        u=Vector((1,0,0)) if abs(normal.y)>=abs(normal.x) else Vector((0,1,0))
        v=normal.cross(u).normalized()
        if v.z<0:v=-v
    else:
        axis=Vector((1,0,0)) if abs(normal.x)<.85 else Vector((0,1,0))
        u=(axis-normal*axis.dot(normal)).normalized();v=normal.cross(u).normalized()
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new(name='GuildReferenceMetreUV')
    for li in face.loop_indices:
        co=matrix@ob.data.vertices[ob.data.loops[li].vertex_index].co
        uv.data[li].uv=(co.dot(u)/tile[0],co.dot(v)/tile[1])


def _read_owned_clay(name):
    image=bpy.data.images.load(str(CLAY_SOURCE/name),check_existing=False)
    # Numeric sampling preserves authored channels; colour is used only as a
    # relative mineral variation, not reclassified as a measured roof scan.
    image.colorspace_settings.name='Non-Color'
    pixels=np.empty(image.size[0]*image.size[1]*4,np.float32);image.pixels.foreach_get(pixels)
    array=np.flipud(pixels.reshape(image.size[1],image.size[0],4)[:,:,:3]).copy()
    bpy.data.images.remove(image)
    return array


def _sample_clay(u,v,variant):
    # Brick interior only: explicitly exclude all mortar and shaped brick edges.
    # This reuses the owned fired-clay grain, not the masonry layout, on roof clay.
    uu=np.where((variant%2)==0,u,1-u);vv=np.where((variant%3)==0,v,1-v)
    cx=np.clip((np.mod(variant,4)*.25+.025+uu*.195)*2048,0,2047).astype(np.int32)
    cy=np.clip((.014+vv*.055)*2048,0,2047).astype(np.int32)
    color=_read_owned_clay('texture.png')[cy,cx]
    rough=_read_owned_clay('roughness.png')[cy,cx].mean(axis=2)
    normal=_read_owned_clay('normal.png')[cy,cx]
    normal[:,:,1]=1-normal[:,:,1] # Original owned Unreal map is DirectX.
    return color,rough,normal


def _stone(out):
    mat,meshes=_copy_replace('Guild PBR | cut limestone trim')
    if mat is None:return None
    n=1024;y,x=np.mgrid[0:n,0:n].astype(np.float32)/n
    # Fine mineral variation and chisel abrasion, without copying wall mortar
    # seams onto monolithic cut stone or introducing geometric displacement.
    grain=_noise(n,3101,1.0)*.3+_noise(n,3102,9)*.3+_noise(n,3103,42)*.4
    tool=np.sin(math.tau*(91*y+.06*np.sin(math.tau*13*x)))
    variance=grain*.06+tool*.002
    color=np.array([.48,.445,.355],np.float32)[None,None,:]*(1+variance[:,:,None])
    rough=np.clip(.79+grain*.035+tool*.01,.70,.9)
    for image,socket in [(_map(out,'guild_cut_limestone_mineral_color',color,True),'Base Color'),
                         (_map(out,'guild_cut_limestone_roughness',rough),'Roughness'),
                         (_map(out,'guild_cut_limestone_micro_normal',_normal(grain*.09+tool*.004,.5)),'Normal')]:
        _link(mat,image,socket,.18)
    p=_principled(mat);p.inputs['Base Color'].default_value=(1,1,1,1);p.inputs['Metallic'].default_value=0
    projected=0;seen=set()
    for ob in bpy.data.objects:
        if ob.type!='MESH' or ob.data.as_pointer() in seen:continue
        slots={i for i,m in enumerate(ob.data.materials) if m==mat}
        if not slots:continue
        seen.add(ob.data.as_pointer())
        for face in ob.data.polygons:
            if face.material_index in slots:_metre_uv(ob,face,(1,1));projected+=1
    return {'material':mat.name,'meshes':len(meshes),'metre_uv_faces':projected,'tile_m':[1,1],
            'basis':'U19 pale warm cut-stone surround; subtle mineral/chisel grain, no masonry joints','tile_maps':1024}


def _roof(out):
    mat,meshes=_copy_replace('Guild PBR | terracotta')
    if mat is None:return None
    n=2048;rows=18;cols=12
    yy,xx=np.mgrid[0:n,0:n].astype(np.float32);x=xx/n*cols;y=yy/n*rows
    height=np.zeros((n,n),np.float32);variation=np.zeros_like(height);edge=np.zeros_like(height)
    sample_u=np.zeros_like(height);sample_v=np.zeros_like(height);sample_variant=np.zeros((n,n),np.int32)
    rng=np.random.default_rng(19102026);tile_var=rng.uniform(-1,1,(rows,cols)).astype(np.float32)
    for row in range(rows+1,-3,-1):
        shift=(row%2)*.5;col=np.floor(x-shift+.5);dx=x-shift-col
        tip=row+.55+np.sqrt(np.maximum(0,.25-dx*dx))*1.50
        mask=(y>=row-.6)&(y<=tip)
        rim=np.minimum(.5-np.abs(dx),(tip-y)*.6);chamfer=np.clip(rim/.021,0,1)
        h=(.35+.20*np.clip(y-row,0,1.3))*chamfer
        var=tile_var[row%rows,np.mod(col.astype(np.int32),cols)]
        height[mask]=h[mask];variation[mask]=var[mask];edge[mask]=chamfer[mask]
        sample_u[mask]=(dx+.5)[mask];sample_v[mask]=np.clip((y-row+.6)/1.9,0,1)[mask]
        sample_variant[mask]=(col.astype(np.int32)+row*3)[mask]
    u=xx/n;v=yy/n
    mineral=_noise(n,1911,.7)*.4+_noise(n,1912,5)*.3+_noise(n,1913,22)*.3
    clay_color,clay_rough,clay_normal=_sample_clay(sample_u,sample_v,sample_variant)
    clay_ratio=np.clip(clay_color/(clay_color.mean(axis=(0,1))[None,None,:]+1e-6),.75,1.30)
    color=np.array([.44,.178,.083],np.float32)[None,None,:]*(1+variation[:,:,None]*.09+mineral[:,:,None]*.045)
    color*=.3+.7*clay_ratio
    color*=(.56+.44*edge)[:,:,None]
    rough=np.clip(.77+(clay_rough-clay_rough.mean())*.5+mineral*.045+variation*.025,.64,.91)
    normal=_fishscale_relief_normal(n,clay_normal)
    for image,socket in [(_map(out,'guild_fishscale_large_repeat_color',color,True),'Base Color'),
                         (_map(out,'guild_fishscale_large_repeat_roughness',rough),'Roughness'),
                         (_map(out,'guild_fishscale_large_repeat_normal',normal),'Normal')]:
        _link(mat,image,socket,1.0)
    _principled(mat).inputs['Base Color'].default_value=(1,1,1,1)
    # Thickness edges and curved ridge caps do not expose a stretched roof plan.
    clay=mat.copy();clay.name='Guild baked clay edge and ridge | reference 20261013'
    clay['reference_revision']='20261013'
    yy,xx=np.mgrid[0:512,0:512].astype(np.float32)/511
    ec,er,en=_sample_clay(xx,yy,np.zeros((512,512),np.int32))
    ec=np.array([.44,.178,.083])[None,None,:]*np.clip(ec/(ec.mean(axis=(0,1))[None,None,:]+1e-6),.75,1.30)
    for image,socket in [(_map(out,'guild_baked_clay_plain_color',ec,True),'Base Color'),
                         (_map(out,'guild_baked_clay_plain_roughness',np.clip(.8+(er-er.mean())*.5,.65,.93)),'Roughness'),
                         (_map(out,'guild_baked_clay_plain_normal',en),'Normal')]:_link(clay,image,socket,.40)
    affected=0;side_faces=0;seen=set()
    for ob in bpy.data.objects:
        if ob.type!='MESH' or ob.data.as_pointer() in seen:continue
        slots={i for i,m in enumerate(ob.data.materials) if m==mat}
        if not slots:continue
        seen.add(ob.data.as_pointer());ob.data.materials.append(clay);clay_index=len(ob.data.materials)-1
        for face in ob.data.polygons:
            if face.material_index not in slots:continue
            normal=(ob.matrix_world.to_3x3().inverted().transposed()@face.normal).normalized()
            if abs(normal.z)<.3 or ('roof_join_' in ob.name and ob.name.endswith('_trim')):
                face.material_index=clay_index;_metre_uv(ob,face,(.28,.20));side_faces+=1
            else:_metre_uv(ob,face,(3,2.16),slope=True)
            affected+=1
    return {'material':mat.name,'uv_faces':affected,'old_repeat_m':[1,.72],'new_repeat_m':[3,2.16],
            'tile_width_m':.25,'course_m':.12,'map_px':2048,'plain_clay_edge_ridge_faces':side_faces,
            'normal_revision':'20261013 metre-gradient rounded fishscale overlap',
            'normal_scale':1.0,'normal_profile_metres':{'transverse_camber':.005,'slope_lift':.012,'lip_rounding':.004},
            'normal_scope':'Lighting relief only; no geometry displacement, parallax or added cast shadow',
            'clay_grain_source':str(CLAY_SOURCE/'material.json'),
            'clay_grain_adaptation':'Owned fired brick interior mineral/roughness; no mortar transferred; DX normal green converted once. Project roof design, not measured roof scan.',
            'fix':'Fishscale overlap relief + restrained fired-clay grain, explicit metre UV on slopes and plain clay thickness/ridge faces'}


def _glass(out):
    n=512;y,x=np.mgrid[0:n,0:n].astype(np.float32)/n
    ripple=(np.sin(math.tau*(3*x+2*y))+.45*np.sin(math.tau*(7*x-4*y)))/1.45
    rough=_map(out,'guild_glass_subtle_roughness',.13+ripple*.025)
    normal=_map(out,'guild_glass_subtle_normal',_normal(ripple,1.1))
    result=[]
    specs=[('Guild PBR | window glass',(.74,.84,.84),.20),
           ('Guild PBR | ivory lantern glass',(.86,.85,.77),.055)]
    for name,rgb,alpha in specs:
        mat,meshes=_copy_replace(name)
        if mat is None:continue
        p=_principled(mat)
        p.inputs['Base Color'].default_value=(*rgb,1)
        p.inputs['Alpha'].default_value=alpha;p.inputs['Metallic'].default_value=0
        p.inputs['Roughness'].default_value=.13;p.inputs['IOR'].default_value=1.46
        p.inputs['Coat Weight'].default_value=.12
        # Alpha is supported by the actual current renderer. Do not rely on an
        # ignored transmission extension or turn the entire sheet into a lamp.
        p.inputs['Transmission Weight'].default_value=0
        p.inputs['Emission Color'].default_value=(0,0,0,1);p.inputs['Emission Strength'].default_value=0
        mat.diffuse_color=(*rgb,alpha);mat.surface_render_method='BLENDED';mat.use_backface_culling=False
        _link(mat,rough,'Roughness');_link(mat,normal,'Normal',.09)
        result.append({'material':mat.name,'alpha':alpha,'opaque_before':True,'meshes':len(meshes),'emissive':False})
    tinted={}
    for index in range(5):
        mat,meshes=_copy_replace('Guild stained glass '+str(index))
        if mat is None:continue
        p=_principled(mat)
        # Portable fallback only. Runtime opt-in below performs coloured
        # transmission separately from dielectric reflection, since ordinary
        # alpha mix necessarily washes jewel colours against a bright sky.
        alpha=[.52,.56,.38,.46,.50][index]
        p.inputs['Alpha'].default_value=alpha;p.inputs['Roughness'].default_value=.10
        p.inputs['Coat Weight'].default_value=.25;p.inputs['IOR'].default_value=1.52
        p.inputs['Transmission Weight'].default_value=0
        p.inputs['Emission Color'].default_value=(0,0,0,1);p.inputs['Emission Strength'].default_value=0
        mat.diffuse_color=(*mat.diffuse_color[:3],alpha);mat.surface_render_method='BLENDED';mat.use_backface_culling=False
        _link(mat,rough,'Roughness');_link(mat,normal,'Normal',.20)
        rgb=list(p.inputs['Base Color'].default_value[:3]);peak=max(rgb)
        tinted[mat.name]={'transmittance':[float(v/peak*.8) for v in rgb],'roughness':.13}
        result.append({'material':mat.name,'palette_unchanged':True,'old_alpha':.90,'alpha':alpha,'meshes':len(meshes),'emissive':False,
                       'optics':'Runtime explicit thin-glass multiply-transmission plus dielectric reflection; alpha is portable fallback only'})
    annotated=[]
    for ob in bpy.data.objects:
        if ob.type!='MESH':continue
        used={p.material_index for p in ob.data.polygons}
        configs={m.name:tinted[m.name] for i,m in enumerate(ob.data.materials)
                 if i in used and m is not None and m.name in tinted}
        if configs:
            ob['rmmo_tinted_glass']={'version':1,'materials':configs}
            annotated.append(ob.name)
    result.append({'runtime_tinted_glass_objects':annotated,'material_names':list(tinted),
                   'contract':'rmmo_tinted_glass version 1; exact material-name map, no unused slot indices'})
    return result


def _rose_aperture_audit():
    """Inspect actual source geometry immediately behind the glass, not labels."""
    bpy.context.view_layer.update();candidates=[]
    for ob in bpy.data.objects:
        if ob.type!='MESH':continue
        pts=[ob.matrix_world@Vector(c) for c in ob.bound_box]
        lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
        if hi[0]<14.8 or lo[0]>17.2 or hi[2]<8.2 or lo[2]>10.6 or hi[1]<-.40 or lo[1]>1.2:continue
        candidates.append(ob)
    blockers=[];count=0
    for radius in [.40,.75,1.02]:
        for i in range(16):
            angle=(i+.35)*math.tau/16
            origin=Vector((16+radius*math.cos(angle),-.40,9.4+radius*math.sin(angle)))
            end=origin+Vector((0,1.55,0));count+=1
            for ob in candidates:
                inv=ob.matrix_world.inverted();local_origin=inv@origin;local_end=inv@end;direction=local_end-local_origin
                hit,position,normal,poly=ob.ray_cast(local_origin,direction.normalized(),distance=direction.length)
                if not hit:continue
                if poly<0 or poly>=len(ob.data.polygons):continue
                mi=ob.data.polygons[poly].material_index
                mat=ob.data.materials[mi] if mi<len(ob.data.materials) else None
                label=mat.name.lower() if mat else ''
                if 'glass' in label or 'lead' in label:continue
                blockers.append({'object':ob.name,'material':mat.name if mat else '',
                                 'position':list(ob.matrix_world@position),'radius':radius,'sector':i})
    return {'sampled_pane_rays':count,'opaque_backing_hits':blockers,
            'scope':'Through actual exported-source geometry from just behind front glass to 1.15m behind facade; lead bars excluded',
            'glass_geometry':'Single two-sided pane per coloured cell; no stacked opaque glass sheets authored'}


def _entrance_lanterns(out):
    """User-confirmed four real glass sheets + floating warm-white crystal."""
    roots=[o for o in bpy.data.objects if o.get('asset_id')=='guild_facade_wall_lantern']
    glass=bpy.data.materials['Guild PBR | ivory lantern glass | reference 20261013']
    # Only these cages receive this variation; the existing shared brass for
    # door hardware and standalone gold standards is not overwritten.
    brass=bpy.data.materials['Guild PBR | aged brass'].copy()
    brass.name='Guild facade lantern worked brass | reference 20261013'
    brass['reference_revision']='20261013'
    grain=_noise(512,6712,1.4)*.35+_noise(512,6713,13)*.65
    color=np.array([.42,.29,.11])[None,None,:]*(1+grain[:,:,None]*.07)
    _link(brass,_map(out,'guild_lantern_worked_brass_color',color,True),'Base Color')
    _link(brass,_map(out,'guild_lantern_worked_brass_roughness',np.clip(.35+grain*.055,.27,.43)),'Roughness')
    _link(brass,_map(out,'guild_lantern_worked_brass_micro_normal',_normal(grain,.12)),'Normal',.12)
    _principled(brass).inputs['Base Color'].default_value=(1,1,1,1)
    crystal=bpy.data.materials.get('Guild warm white floating magic stone')
    if crystal is None:
        crystal=bpy.data.materials.new('Guild warm white floating magic stone');crystal.use_nodes=True
        p=_principled(crystal);p.inputs['Base Color'].default_value=(.72,.65,.48,1)
        p.inputs['Roughness'].default_value=.24;p.inputs['Metallic'].default_value=0
        p.inputs['Emission Color'].default_value=(1,.86,.69,1);p.inputs['Emission Strength'].default_value=3
    report=[]
    def mesh(name,vertices,faces,material,root):
        data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.materials.append(material);data.update()
        ob=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(ob);ob.parent=root
        ob['semantic_group']=root['semantic_group'];ob['collision_review']=False;ob['rmmo_collision']='none'
        ob['delivery_stage']='textured_repair_v2';ob['reference_revision']='20261013';ob['whitebox_only']=False
        uv=data.uv_layers.new(name='LampPaneUV')
        for p in data.polygons:
            axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
            for li in p.loop_indices:
                co=data.vertices[data.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
        return ob
    def pane(name,center,width,height,axis,root):
        # One optical face per physical pane, not two stacked parallel alpha
        # sheets. Four small edge strips still expose the 4 mm glass thickness.
        horizontal=Vector((1,0,0)) if axis==1 else Vector((0,1,0))
        normal=Vector((0,1,0)) if axis==1 else Vector((1,0,0))
        vertical=Vector((0,0,1));c=Vector(center)
        front=[c+horizontal*x*width/2+vertical*z*height/2 for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        vertices=front+[v-normal*.004 for v in front]
        return mesh(name,vertices,[(0,1,2,3),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],glass,root)
    bpy.context.view_layer.update()
    for root in roots:
        cage=[o for o in root.children_recursive if o.type=='MESH' and not o.name.startswith('Facade lantern glass')]
        for ob in cage:
            for i,mat in enumerate(ob.data.materials):
                if mat and mat.name=='Guild PBR | aged brass':ob.data.materials[i]=brass
            bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
            bevel=ob.modifiers.new('Worked metal 5mm edge','BEVEL');bevel.width=.005;bevel.segments=3
            bevel.limit_method='ANGLE';bevel.harden_normals=True
            bpy.ops.object.modifier_apply(modifier=bevel.name)
            for polygon in ob.data.polygons:polygon.use_smooth=True
            normal=ob.modifiers.new('Worked metal planar weighted normals','WEIGHTED_NORMAL');normal.keep_sharp=True;normal.weight=50
            bpy.ops.object.modifier_apply(modifier=normal.name)
            ob['reference_revision']='20261013'
        old=[o for o in root.children_recursive if o.type=='MESH' and o.name.startswith('Facade lantern glass')]
        assert len(old)==1,(root.name,'expected one original solid glass body')
        points=[root.matrix_world.inverted()@old[0].matrix_world@v.co for v in old[0].data.vertices]
        lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center=(lo+hi)/2;size=hi-lo
        bpy.data.objects.remove(old[0],do_unlink=True)
        thickness=.004
        for side in [-1,1]:
            pane('Facade lantern clear front-back pane',(center.x,center.y+side*size.y/2,center.z),size.x-.008,size.z,1,root)
            pane('Facade lantern clear side pane',(center.x+side*size.x/2,center.y,center.z),size.y,size.z,0,root)
        # Crystal is smaller than every pane spacing and floats in its centre.
        width=min(size.x,size.y)*.43;height=size.z*.60;r=width/2
        vs=[center+Vector(v) for v in [(0,0,height/2),(r,0,0),(0,r,0),(-r,0,0),(0,-r,0),(0,0,-height/2)]]
        stone=mesh('Facade lantern floating warm white diamond',vs,[(0,1,2),(0,2,3),(0,3,4),(0,4,1),(5,2,1),(5,3,2),(5,4,3),(5,1,4)],crystal,root)
        stone['floating_magic_stone']=True;stone['light_source']='floating_diamond_magic_stone'
        gap=min((size.x-width)/2,(size.y-width)/2,(size.z-height)/2)-thickness/2
        assert gap>.03,(root.name,'crystal intersects glass',gap)
        root['rmmo_light_socket']={'position':[center.x,center.z,-center.y],'color':[1,.86,.69],'range':4.0,'energy':.35,'flame':False,'indoor':False}
        root['light_source']='floating_diamond_magic_stone';root['glass_panels']=4;root['reference_revision']='20261013'
        report.append({'root':root.name,'asset_id':root['asset_id'],'glass_panels':4,'glass_thickness_m':thickness,
                       'optical_faces_per_pane':1,'pane_alpha':.055,'beveled_cage_meshes':len(cage),'cage_bevel_m':.005,
                       'crystal_size_m':[width,width,height],'minimum_glass_clearance_m':gap,
                       'socket_position_godot':list(root['rmmo_light_socket']['position'])})
    return report


def apply(output_directory=None):
    # UVs must cover the delivered shell, including Solidify-generated rims.
    # Export-time Solidify otherwise collapses the narrow side-face UVs to a
    # line even when every source face was correctly projected in metres.
    shell_changes=[]
    shell_materials={'Guild PBR | exterior limestone','Guild PBR | cut limestone trim','Guild PBR | terracotta'}
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH' or not any(m and m.name in shell_materials for m in ob.data.materials):continue
        mods=[m for m in ob.modifiers if m.type=='SOLIDIFY']
        if not mods:continue
        hidden=ob.hide_get();ob.hide_set(False);bpy.context.view_layer.objects.active=ob
        if ob.data.users>1:ob.data=ob.data.copy()
        for mod in mods:
            before=len(ob.data.polygons);name=mod.name
            bpy.ops.object.modifier_apply(modifier=name)
            shell_changes.append({'object':ob.name,'modifier':name,'before_faces':before,'after_faces':len(ob.data.polygons)})
        ob.hide_set(hidden)
    out=Path(output_directory) if output_directory else DEFAULT_OUT
    out.mkdir(parents=True,exist_ok=True)
    assert not any('reference 20261013' in m.name and m.name.startswith('Guild PBR | terracotta') for m in bpy.data.materials),'Already applied'
    result={'solid_shells_before_uv':shell_changes,'roof':_roof(out),'cut_stone':_stone(out),'glazing':_glass(out),'entrance_magic_lanterns':_entrance_lanterns(out),
            'rose_aperture':_rose_aperture_audit(),
            'new_maps_directory':str(out),'source_reference_images_modified':False,
            'affected_asset_ids':['guild_facade_wall_lantern'],
            'unchanged':['scanned wall stone','alarm tower brick/stone/brass','confirmed stained-glass palette','cloth heraldry colour atlas'],
            'limitations':['Entry lantern point-light behavior still needs runtime day/night review; pane emission remains zero.',
                           'Fixed camera PBR quality comparison is required after export; this builder does not establish visual acceptance.']}
    bpy.context.view_layer.update()
    return result
