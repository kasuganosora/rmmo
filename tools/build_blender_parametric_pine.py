"""Build an editable Geometry Nodes Baltic pine from owned Fab USD modules.

Run in Blender background. Originals are read-only; all output stays in art_sources.
"""
import bpy, bmesh, json, math, sys, time
import numpy as np
from pathlib import Path
from mathutils import Matrix, Vector
from pxr import Usd, UsdGeom

BASE = Path('D:/code/rmmo_runtime')
OUT = BASE/'art_sources/bridge_street_kit/baltic_pine_procedural'
SRC = BASE/'art_sources/bridge_street_kit/sources/baltic_pine'
OUT.mkdir(parents=True, exist_ok=True)

def log(*args): print(*args, flush=True)
def material(name):
    m=bpy.data.materials.new(name); m.use_nodes=True
    return m,m.node_tree,next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')

def materials():
    bark,nt,p=material('Pine | owned Fab bark + rough microstructure')
    p.inputs['Roughness'].default_value=.88
    uv=nt.nodes.new('ShaderNodeTexCoord')
    for file,socket in [('texture.jpg','Base Color'),('normal.png','Normal')]:
        t=nt.nodes.new('ShaderNodeTexImage'); t.image=bpy.data.images.load(str(BASE/'packs/default/assets/materials/wood/outdoor_bark'/file));t.image.pack()
        nt.links.new(uv.outputs['UV'],t.inputs['Vector'])
        if socket=='Normal':
            t.image.colorspace_settings.name='Non-Color'
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.55
            nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs['Normal'],p.inputs[socket])
        else:nt.links.new(t.outputs['Color'],p.inputs[socket])
    leaf,nt,p=material('Pine | waxy needles with fine surface variation')
    p.inputs['Roughness'].default_value=.57
    p.inputs['Subsurface Weight'].default_value=.045
    p.inputs['Subsurface Radius'].default_value=(.3,.65,.15)
    p.inputs['Specular IOR Level'].default_value=.27
    tex=nt.nodes.new('ShaderNodeTexCoord');noise=nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value=17;noise.inputs['Detail'].default_value=3
    nt.links.new(tex.outputs['Object'],noise.inputs['Vector'])
    ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.18;ramp.color_ramp.elements[0].color=(.012,.038,.019,1)
    ramp.color_ramp.elements[1].position=.82;ramp.color_ramp.elements[1].color=(.075,.16,.047,1)
    nt.links.new(noise.outputs['Fac'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],p.inputs['Base Color'])
    micro=nt.nodes.new('ShaderNodeTexNoise');micro.inputs['Scale'].default_value=340;micro.inputs['Detail'].default_value=2
    nt.links.new(tex.outputs['Object'],micro.inputs['Vector'])
    bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.17;bump.inputs['Distance'].default_value=.0003
    nt.links.new(micro.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs[0],p.inputs['Normal'])
    trans=nt.nodes.new('ShaderNodeBsdfTranslucent');nt.links.new(ramp.outputs[0],trans.inputs[0])
    mix=nt.nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=.14
    nt.links.new(p.outputs[0],mix.inputs[1]);nt.links.new(trans.outputs[0],mix.inputs[2]);nt.links.new(mix.outputs[0],next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
    leaf['note']='Procedural needle micro-surface on original needle geometry, not original Quixel texture; no broadleaf veins.'
    return bark,leaf

def usd_mesh(prim,bark,leaf):
    usd=UsdGeom.Mesh(prim);pts=np.asarray(usd.GetPointsAttr().Get(),dtype=np.float32)
    counts=np.asarray(usd.GetFaceVertexCountsAttr().Get(),dtype=np.int32)
    indices=np.asarray(usd.GetFaceVertexIndicesAttr().Get(),dtype=np.int32)
    mesh=bpy.data.meshes.new(prim.GetName()+'_source')
    mesh.vertices.add(len(pts));mesh.vertices.foreach_set('co',pts.ravel())
    mesh.loops.add(len(indices));mesh.loops.foreach_set('vertex_index',indices)
    mesh.polygons.add(len(counts));mesh.polygons.foreach_set('loop_total',counts)
    mesh.polygons.foreach_set('loop_start',np.r_[0,np.cumsum(counts[:-1])])
    mesh.materials.append(bark);mesh.materials.append(leaf)
    mids=np.zeros(len(counts),dtype=np.int32)
    for child in prim.GetChildren():
        if child.IsA(UsdGeom.Subset) and 'TwoSided' in child.GetName():mids[np.asarray(UsdGeom.Subset(child).GetIndicesAttr().Get(),dtype=np.int32)]=1
    mesh.polygons.foreach_set('material_index',mids)
    mesh.polygons.foreach_set('use_smooth',np.ones(len(counts),dtype=bool))
    uv=UsdGeom.PrimvarsAPI(prim).GetPrimvar('st')
    values=np.asarray(uv.ComputeFlattened(),dtype=np.float32)
    assert len(values)==len(indices), (prim.GetName(),len(values),len(indices))
    mesh.uv_layers.new(name='SourceUV').data.foreach_set('uv',values.ravel())
    mesh.update()
    return mesh

def tris(mesh): return sum(len(p.vertices)-2 for p in mesh.polygons)
def matrix(gf):return Matrix(np.asarray(gf,dtype=float).T.tolist())

def sources(bark,leaf):
    stage=Usd.Stage.Open(str(SRC/'Tree_Baltic_Pine_01_D.usd'))
    original=bpy.data.collections.new('SOURCE_D | original modules (read only)')
    optimized=bpy.data.collections.new('SOURCE_D | conservative optimized modules')
    original_trunk=bpy.data.collections.new('SOURCE_D | original trunk')
    optimized_trunk=bpy.data.collections.new('SOURCE_D | optimized trunk')
    conversion=Matrix.Rotation(math.pi/2,4,'X')
    cache={};optcache={};usage={};stats=[]
    def getmesh(p):
        k=str(p.GetPath())
        if k not in cache:cache[k]=usd_mesh(p,bark,leaf)
        return cache[k]
    def add(p,world,name):
        mesh=getmesh(p);o=bpy.data.objects.new(name,mesh);original.objects.link(o);o.matrix_world=conversion@world
        usage[mesh.name]=usage.get(mesh.name,0)+1
    for p in stage.Traverse():
        if p.IsA(UsdGeom.PointInstancer):
            inst=UsdGeom.PointInstancer(p);targets=inst.GetPrototypesRel().GetTargets()
            transforms=inst.ComputeInstanceTransformsAtTime(Usd.TimeCode.Default(),Usd.TimeCode.Default())
            protos=inst.GetProtoIndicesAttr().Get()
            for i,(idx,tf) in enumerate(zip(protos,transforms)):
                root=stage.GetPrimAtPath(targets[idx])
                for child in Usd.PrimRange(root):
                    if child.IsA(UsdGeom.Mesh):add(child,matrix(tf),f'Branch_{i:03d}')
        elif p.IsA(UsdGeom.Mesh) and '/Prototypes/' not in str(p.GetPath()):
            add(p,matrix(UsdGeom.Xformable(p).ComputeLocalToWorldTransform(Usd.TimeCode.Default())),'Trunk_D')
    # Dissolve only effectively coplanar internal edges. Do not remove leaves or
    # weld separate components; preserve UV/material boundaries.
    for mesh in cache.values():
        m=mesh.copy();m.name=mesh.name.replace('_source','_optimized')
        before=tris(m)
        bm=bmesh.new();bm.from_mesh(m)
        bmesh.ops.dissolve_limit(bm,angle_limit=0.01,verts=list(bm.verts),edges=list(bm.edges),delimit={'UV','MATERIAL'})
        bm.to_mesh(m);bm.free();m.update()
        # Only the main woody skeleton uses collapse reduction. Branch modules
        # retain all needle silhouettes and original connected stems.
        if mesh.name.startswith('Tree_Baltic_Pine_01_D'):
            temp=bpy.data.objects.new('TEMP_REDUCTION',m);bpy.context.scene.collection.objects.link(temp)
            bpy.context.view_layer.objects.active=temp;temp.select_set(True)
            mod=temp.modifiers.new('Wood reduction candidate','DECIMATE');mod.ratio=.55
            bpy.ops.object.modifier_apply(modifier=mod.name);m=temp.data
            bpy.data.objects.remove(temp,do_unlink=True)
        optcache[mesh.name]=m
        stats.append({'mesh':mesh.name,'instances':usage[mesh.name],'before_triangles':before,'after_triangles':tris(m)})
        log('OPTIMIZED',stats[-1])
    for o in original.objects:
        n=bpy.data.objects.new(o.name+'_opt',optcache[o.data.name]);optimized.objects.link(n);n.matrix_world=o.matrix_world.copy()
    for col,trunk_col in [(original,original_trunk),(optimized,optimized_trunk)]:
        for obj in list(col.objects):
            if obj.name.startswith('Trunk_'):trunk_col.objects.link(obj);col.objects.unlink(obj)
    return original,optimized,original_trunk,optimized_trunk,stats

def nodes(original,optimized,original_trunk,optimized_trunk):
    ng=bpy.data.node_groups.new('Baltic Pine | continuous crown shaping','GeometryNodeTree')
    def socket(name,kind,default=None,minv=None,maxv=None):
        s=ng.interface.new_socket(name=name,in_out='INPUT',socket_type=kind)
        if default is not None:s.default_value=default
        if minv is not None:s.min_value=minv;s.max_value=maxv
        return s
    socket('Optimized','NodeSocketBool',True)
    socket('Height (m)','NodeSocketFloat',10.0,6.,18.)
    socket('Crown spread','NodeSocketFloat',1.25,.65,1.8)
    socket('Trunk width','NodeSocketFloat',1.45,.8,2.2)
    socket('Leafy branch size','NodeSocketFloat',1.6,.85,2.0)
    socket('Bare trunk shortening (m)','NodeSocketFloat',.5,0.,1.)
    socket('Crown lift (m)','NodeSocketFloat',0.,-1.,1.)
    socket('Lean (m)','NodeSocketFloat',.12,-.6,.6)
    socket('Seed','NodeSocketInt',17,0,10000)
    socket('Irregularity','NodeSocketFloat',.06,0.,.12)
    socket('Twig retention','NodeSocketFloat',1.,.85,1.)
    socket('Wind (m)','NodeSocketFloat',0.,0.,.10)
    ng.interface.new_socket(name='Geometry',in_out='OUTPUT',socket_type='NodeSocketGeometry')
    ns=ng.nodes;ls=ng.links
    def node(kind,label=''):
        n=ns.new(kind);n.label=label;return n
    def link(a,b):ls.new(a,b)
    def mathn(op,a,b=None):
        n=node('ShaderNodeMath');n.operation=op
        for i,x in enumerate([a,b]):
            if x is not None:
                if isinstance(x,(int,float)):n.inputs[i].default_value=x
                else:link(x,n.inputs[i])
        return n.outputs[0]
    gi=node('NodeGroupInput');go=node('NodeGroupOutput')
    infos=[]
    for col in [original,optimized,original_trunk,optimized_trunk]:
        n=node('GeometryNodeCollectionInfo',col.name);n.inputs['Collection'].default_value=col;n.inputs['Separate Children'].default_value=True;infos.append(n.outputs['Instances'])
    sw=node('GeometryNodeSwitch');sw.input_type='GEOMETRY';link(gi.outputs['Optimized'],sw.inputs['Switch']);link(infos[0],sw.inputs['False']);link(infos[1],sw.inputs['True'])
    scale_branch=node('GeometryNodeScaleInstances','Expand rooted leafy twigs without detaching their base')
    link(sw.outputs[0],scale_branch.inputs['Instances']);link(gi.outputs['Leafy branch size'],scale_branch.inputs['Scale'])
    trunk_sw=node('GeometryNodeSwitch');trunk_sw.input_type='GEOMETRY';link(gi.outputs['Optimized'],trunk_sw.inputs['Switch']);link(infos[2],trunk_sw.inputs['False']);link(infos[3],trunk_sw.inputs['True'])
    realize=node('GeometryNodeRealizeInstances');link(trunk_sw.outputs[0],realize.inputs[0])
    # Keep 583 leafy modules instanced. Only the woody skeleton is realized.
    # Retention removes entire rooted twig modules, not arbitrary leaf faces.
    index=node('GeometryNodeInputIndex');rnd=node('FunctionNodeRandomValue');rnd.data_type='FLOAT'
    link(index.outputs[0],rnd.inputs['ID']);link(gi.outputs['Seed'],rnd.inputs['Seed'])
    rnd.inputs['Min'].default_value=0.;rnd.inputs['Max'].default_value=1.
    drop=mathn('GREATER_THAN',rnd.outputs['Value'],gi.outputs['Twig retention'])
    delete=node('GeometryNodeDeleteGeometry');delete.domain='INSTANCE';link(scale_branch.outputs[0],delete.inputs['Geometry']);link(drop,delete.inputs['Selection'])
    pos=node('GeometryNodeInputPosition');sep=node('ShaderNodeSeparateXYZ');link(pos.outputs[0],sep.inputs[0]);x,y,z=[sep.outputs[k] for k in ['X','Y','Z']]
    q=mathn('DIVIDE',z,18.72559928894043);q2=mathn('MULTIPLY',q,q)
    ramp=node('ShaderNodeMapRange');ramp.interpolation_type='SMOOTHSTEP';link(q,ramp.inputs['Value']);ramp.inputs['From Min'].default_value=.12;ramp.inputs['From Max'].default_value=.48
    width=mathn('ADD',gi.outputs['Trunk width'],mathn('MULTIPLY',ramp.outputs[0],mathn('SUBTRACT',gi.outputs['Crown spread'],gi.outputs['Trunk width'])))
    scale=mathn('DIVIDE',gi.outputs['Height (m)'],18.72559928894043)
    width=mathn('MULTIPLY',width,scale)
    noise=node('ShaderNodeTexNoise');noise.noise_dimensions='4D';noise.inputs['Scale'].default_value=.32;noise.inputs['Detail'].default_value=1.
    link(pos.outputs[0],noise.inputs['Vector']);link(gi.outputs['Seed'],noise.inputs['W'])
    wobble=mathn('MULTIPLY',mathn('SUBTRACT',noise.outputs['Fac'],.5),mathn('MULTIPLY',gi.outputs['Irregularity'],q2))
    width=mathn('MULTIPLY',width,mathn('ADD',1.,wobble))
    time_node=node('GeometryNodeInputSceneTime')
    wind=mathn('MULTIPLY',mathn('SINE',mathn('ADD',mathn('MULTIPLY',time_node.outputs['Seconds'],1.2),q)),mathn('MULTIPLY',gi.outputs['Wind (m)'],q2))
    newx=mathn('ADD',mathn('MULTIPLY',x,width),mathn('ADD',mathn('MULTIPLY',gi.outputs['Lean (m)'],q2),wind))
    newy=mathn('MULTIPLY',y,width)
    newz=mathn('ADD',mathn('MULTIPLY',q,gi.outputs['Height (m)']),mathn('MULTIPLY',mathn('SINE',mathn('MULTIPLY',q,math.pi)),gi.outputs['Crown lift (m)']))
    lower=node('ShaderNodeMapRange','Shorten bare trunk; translate entire crown without squashing it')
    lower.interpolation_type='SMOOTHSTEP';link(q,lower.inputs['Value'])
    lower.inputs['From Min'].default_value=0.;lower.inputs['From Max'].default_value=.25
    newz=mathn('SUBTRACT',newz,mathn('MULTIPLY',lower.outputs[0],gi.outputs['Bare trunk shortening (m)']))
    combine=node('ShaderNodeCombineXYZ')
    for key,value in [('X',newx),('Y',newy),('Z',newz)]:link(value,combine.inputs[key])
    setpos=node('GeometryNodeSetPosition');link(realize.outputs[0],setpos.inputs['Geometry']);link(combine.outputs[0],setpos.inputs['Position'])
    # The branch origin follows exactly the skeleton's deformation function.
    # Scale in world axes around that origin, preserving shared twig geometry.
    branchscale=node('ShaderNodeCombineXYZ')
    for key,value in [('X',width),('Y',width),('Z',scale)]:link(value,branchscale.inputs[key])
    scale_instances=node('GeometryNodeScaleInstances');scale_instances.inputs['Local Space'].default_value=False
    link(pos.outputs[0],scale_instances.inputs['Center'])
    link(delete.outputs[0],scale_instances.inputs['Instances']);link(branchscale.outputs[0],scale_instances.inputs['Scale'])
    offset=node('ShaderNodeVectorMath');offset.operation='SUBTRACT';link(combine.outputs[0],offset.inputs[0]);link(pos.outputs[0],offset.inputs[1])
    translate=node('GeometryNodeTranslateInstances');translate.inputs['Local Space'].default_value=False
    link(scale_instances.outputs[0],translate.inputs['Instances']);link(offset.outputs[0],translate.inputs['Translation'])
    join=node('GeometryNodeJoinGeometry');link(setpos.outputs[0],join.inputs[0]);link(translate.outputs[0],join.inputs[0]);link(join.outputs[0],go.inputs[0])
    # Readable node layout by dependency depth, keeping all controls native.
    for i,n in enumerate(ns):n.location=(i%10*210,-(i//10)*230)
    return ng

def setval(obj,name,val):
    mod=obj.modifiers[0]
    s=next(x for x in mod.node_group.interface.items_tree if x.item_type=='SOCKET' and x.in_out=='INPUT' and x.name==name)
    mod[s.identifier]=val;obj.update_tag()

def stage(tree):
    sc=bpy.context.scene;sc.unit_settings.system='METRIC';sc.render.engine='CYCLES'
    sc.cycles.samples=40;sc.cycles.use_denoising=True;sc.cycles.seed=21;sc.cycles.use_animated_seed=False
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
        for device in prefs.devices:device.use=device.type!='CPU'
        if any(d.use for d in prefs.devices):sc.cycles.device='GPU'
    except Exception:pass
    sc.render.resolution_x=1100;sc.render.resolution_y=1100;sc.render.resolution_percentage=100
    sc.world=bpy.data.worlds.new('Neutral daylight');sc.world.use_nodes=True
    next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.55,.68,.88,1)
    next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.32
    sc.view_settings.view_transform='AgX';sc.view_settings.exposure=0.
    bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='REVIEW | ground'
    m,nt,p=material('Review | stone grey ground');p.inputs['Base Color'].default_value=(.23,.245,.22,1);p.inputs['Roughness'].default_value=.9;floor.data.materials.append(m)
    bpy.ops.object.light_add(type='SUN',location=(-8,-6,14));sun=bpy.context.object;sun.name='REVIEW | fixed sun';sun.rotation_euler=(.45,-.5,-.5);sun.data.energy=2.5;sun.data.angle=.06
    bpy.ops.object.camera_add(location=(14,-20,11));cam=bpy.context.object;cam.name='REVIEW | full crown';cam.rotation_euler=(Vector((0,0,5.))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=12.8;sc.camera=cam
    bpy.ops.object.select_all(action='DESELECT');tree.select_set(True);bpy.context.view_layer.objects.active=tree
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_distance=15;area.spaces.active.region_3d.view_location=(0,0,4.4)
                area.spaces.active.clip_end=500
    return sc,cam,sun

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bark,leaf=materials();original,optimized,original_trunk,optimized_trunk,stats=sources(bark,leaf)
    mesh=bpy.data.meshes.new('Procedural controller');tree=bpy.data.objects.new('BALTIC PINE | editable parameters',mesh);bpy.context.scene.collection.objects.link(tree)
    mod=tree.modifiers.new('Baltic Pine | parameters','NODES');mod.node_group=nodes(original,optimized,original_trunk,optimized_trunk)
    sc,cam,sun=stage(tree)
    text=bpy.data.texts.new('README | BALTIC PINE')
    text.write('Select BALTIC PINE and open Modifiers. All controls are native Geometry Nodes.\nHeight: main crown height in metres; Crown spread / Trunk width: relative proportions; Crown lift and Lean: metres.\nLeafy branch size scales rooted needle-bearing modules. Twig retention 1 preserves all 583 modules.\nSeed changes crown irregularity and optional twig retention; it does not invent new botanical topology.\nWind animates when timeline plays. Default 0 for matched optimization comparison.\nOptimized toggles original and reduced modules with identical materials and deformation.\nTwig geometry stays instanced; twig origins follow the same deformation as the trunk.\nOriginal USD files are read-only; source module collections are kept outside the scene.\nNeedle surface rebuilt procedurally; source USD had no texture maps. Bark uses owned Fab material.\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baltic_pine_parametric.blend'),compress=True)
    report={'template':'Quixel Baltic Pine 01 D','source_url':'https://www.fab.com/listings/a2b04e81-5075-479f-a9d2-4940022f330a','modules':stats,'original_evaluated_triangles':sum(s['before_triangles']*s['instances'] for s in stats),'optimized_evaluated_triangles':sum(s['after_triangles']*s['instances'] for s in stats),'optimized_unique_triangles':sum(s['after_triangles'] for s in stats),'leaf_policy':'0.01 radian limited dissolve preserving UV/material boundaries; no whole leaf deletion. Default twig retention 1.0.','instancing':'583 leafy modules retained as shared instances; only skeleton realized','review':'pending','game_integration':False}
    (OUT/'optimization_review.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    log('BUILD_SAVED',report)
    for name,value in [('master',False),('optimized',True)]:
        setval(tree,'Optimized',value);sc.render.filepath=str(OUT/f'{name}_full.png');bpy.ops.render.render(write_still=True)
    # Same camera/light/exposure for the close view and backlit comparison.
    cam.location=(3,-5,2.7);cam.rotation_euler=(Vector((0,0,1.65))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=3.6
    for name,value in [('master',False),('optimized',True)]:
        setval(tree,'Optimized',value);sc.render.filepath=str(OUT/f'{name}_trunk.png');bpy.ops.render.render(write_still=True)
    cam.location=(14,-20,11);cam.rotation_euler=(Vector((0,0,5.))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=12.8
    sun.rotation_euler=(.8,.35,2.8)
    for name,value in [('master',False),('optimized',True)]:
        setval(tree,'Optimized',value);sc.render.filepath=str(OUT/f'{name}_backlight.png');bpy.ops.render.render(write_still=True)
    sun.rotation_euler=(.45,-.5,-.5)
    setval(tree,'Optimized',True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'baltic_pine_parametric.blend'),compress=True)
    log('PINE_REVIEW_RENDERS_COMPLETE')

if __name__=='__main__':main()
