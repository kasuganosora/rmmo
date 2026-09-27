"""Bake local skin occlusion and joint warmth from the existing body, not clothes.

Leaves editable meshes, UVs, bones and morphs untouched. The sidecar is matched
by quantized rest positions, so glTF seam duplication does not alter the data.
Run with Blender --background --python-exit-code 1 --python this_script.
"""
import bpy, json, math, sys, struct, zlib
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path

def key(p):
    # glTF is Y-up. Match Godot roundi (away from zero at a tie).
    return ','.join(str(math.floor(x*10000+.5) if x>=0 else math.ceil(x*10000-.5)) for x in (p.x,p.z,-p.y))

def png(path, rgb):
    """Write exact channel values; data maps must not get a display transform."""
    rgb=np.uint8(np.clip(rgb*255+.5,0,255))[::-1]
    def chunk(name,data):
        return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data)&0xffffffff)
    h,w,_=rgb.shape
    raw=b''.join(b'\0'+row.tobytes() for row in rgb)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b''))

def bake_maps(body,points,data,output):
    size=2048
    atlas=np.zeros((size,size,3),dtype=np.float32);occupied=np.zeros((size,size),dtype=bool)
    values=np.array([data[key(p)]+[math.sin(p.x*17+p.z*11)*math.sin(p.z*13-p.y*19)] for p in points],dtype=np.float32)
    uv=body.data.uv_layers.active.data;body.data.calc_loop_triangles()
    for tri in body.data.loop_triangles:
        coords=np.array([uv[i].uv[:] for i in tri.loops])*size
        a,b,c=coords;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-7:continue
        lo=np.maximum(0,np.floor(coords.min(axis=0)).astype(int));hi=np.minimum(size,np.ceil(coords.max(axis=0)).astype(int))
        if np.any(hi<=lo):continue
        yy,xx=np.mgrid[lo[1]:hi[1],lo[0]:hi[0]];xx=xx+.5;yy=yy+.5
        u=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
        v=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w=1-u-v
        inside=(u>=-1e-5)&(v>=-1e-5)&(w>=-1e-5)
        region=atlas[lo[1]:hi[1],lo[0]:hi[0]];weighted=u[...,None]*values[tri.vertices[0]]+v[...,None]*values[tri.vertices[1]]+w[...,None]*values[tri.vertices[2]]
        region[inside]=weighted[inside];occupied[lo[1]:hi[1],lo[0]:hi[0]]|=inside
    coverage=float(occupied.mean())
    # Seam padding in UV space for mipmaps, without changing the source UVs.
    for _ in range(16):
        for axis,shift in [(0,1),(0,-1),(1,1),(1,-1)]:
            adjacent=np.roll(occupied,shift,axis);take=~occupied&adjacent
            atlas[take]=np.roll(atlas,shift,axis)[take];occupied[take]=True
    ao=np.where(occupied,atlas[:,:,0],1);warmth=np.where(occupied,atlas[:,:,1],0);variation=atlas[:,:,2]*.008
    base=np.ones((size,size,3),dtype=np.float32)*np.array([1,234/255,219/255])
    base*=1+variation[:,:,None]
    base[:,:,1]*=1-warmth*.034;base[:,:,2]*=1-warmth*.046
    yy,xx=np.mgrid[:size,:size].astype(np.float32)
    # Subtle pore-scale breakup. Kept small, mipmapped, and separate from
    # anatomical form; it cannot invent details missing from the body mesh.
    grain=np.sin(xx*.61+np.sin(yy*.21))*np.sin(yy*.73+np.sin(xx*.17))
    roughness=np.clip(.48+warmth*.055+variation*2+grain*.018,.4,.6)
    dx=np.cos(xx*.61+np.sin(yy*.21))*np.sin(yy*.73+np.sin(xx*.17))*.012
    dy=np.sin(xx*.61+np.sin(yy*.21))*np.cos(yy*.73+np.sin(xx*.17))*.012
    normal=np.stack((-dx,-dy,np.sqrt(1-dx*dx-dy*dy)),axis=-1)*.5+.5
    png(output/'skin_basecolor.png',base)
    png(output/'skin_orm.png',np.stack((ao,roughness,np.zeros_like(ao)),axis=-1))
    png(output/'skin_normal.png',normal)
    mat=bpy.data.materials.new('Shared generated skin PBR');mat.use_nodes=True
    nodes=mat.node_tree.nodes;bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED');links=mat.node_tree.links
    for channel in ['basecolor','normal','orm']:
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(output/f'skin_{channel}.png'),check_existing=False)
        tex.image.colorspace_settings.name='sRGB' if channel=='basecolor' else 'Non-Color'
        if channel=='basecolor':links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        elif channel=='normal':
            normal_node=nodes.new('ShaderNodeNormalMap');normal_node.inputs['Strength'].default_value=.65
            links.new(tex.outputs['Color'],normal_node.inputs['Color']);links.new(normal_node.outputs['Normal'],bsdf.inputs['Normal'])
        else:
            separate=nodes.new('ShaderNodeSeparateColor');links.new(tex.outputs['Color'],separate.inputs['Color']);links.new(separate.outputs['Green'],bsdf.inputs['Roughness'])
    bsdf.inputs['Metallic'].default_value=0;body.data.materials.clear();body.data.materials.append(mat)
    for polygon in body.data.polygons:polygon.material_index=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'editable/skin_material.blend'),copy=True)
    (output/'skin_material.json').write_text(json.dumps({'version':1,'size':size,'uv_coverage':coverage,'basecolor_space':'sRGB','normal_space':'linear tangent +Y','orm':'R=occlusion G=roughness B=metallic(0)','source':'Existing shared Body mesh; generated local AO, joint warmth and microdetail; no reference textures copied.'},indent=2),encoding='utf-8')
    print('SKIN_MAPS',output,'coverage',round(coverage,3),flush=True)

for gender in (['female'] if '--female-only' in sys.argv else ['male'] if '--male-only' in sys.argv else ['female','male']):
    bpy.ops.wm.open_mainfile(filepath=str(art_path(f'characters/imported/{gender}/editable/character.blend')))
    body=bpy.data.objects['Body']
    points=[body.matrix_world@v.co for v in body.data.vertices]
    surface=BVHTree.FromPolygons(points,[list(p.vertices) for p in body.data.polygons])
    normals={}
    for v,p in zip(body.data.vertices,points):
        k=key(p);normals[k]=normals.get(k,Vector())+body.matrix_world.to_3x3()@v.normal
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    joints=[]
    for bone in rig.data.bones:
        if bone.name.endswith(('ForeArm','Leg','Hand','Foot')):
            joints.append((rig.matrix_world@bone.head_local,.10 if 'Leg' in bone.name else .065))
    data={}
    for p in points:
        k=key(p)
        if k in data:continue
        n=normals[k].normalized();t=n.cross(Vector((0,0,1)))
        if t.length<.01:t=n.cross(Vector((0,1,0)))
        t.normalize();b=n.cross(t)
        occluded=0.
        for i in range(48):
            r=math.sqrt((i+.5)/48);phi=i*2.3999632297
            direction=t*(r*math.cos(phi))+b*(r*math.sin(phi))+n*math.sqrt(1-r*r)
            hit,_,_,distance=surface.ray_cast(p+n*.0015,direction,.14)
            if hit is not None:occluded+=1-distance/.14
        ao=1-min(.48,occluded/48*.85)
        warmth=max((math.exp(-((p-center).length/radius)**2) for center,radius in joints),default=0.)
        data[k]=[round(ao,5),round(warmth,5)]
    output=art_path(f'characters/imported/{gender}/skin_detail.json')
    output.write_text(json.dumps({'version':1,'position_quantization':10000,'samples':data},separators=(',',':')),encoding='utf-8')
    bake_maps(body,points,data,output.parent)
    print('SKIN_DETAIL',gender,len(data),'ao_range',min(v[0] for v in data.values()),max(v[0] for v in data.values()),flush=True)
