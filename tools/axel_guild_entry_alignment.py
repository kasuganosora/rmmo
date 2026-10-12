"""Fit entrance landing to the existing parapet caps; preserve UV texel scale."""
import bpy
import numpy as np
from mathutils import Vector


def bounds(o):
    ps=[o.matrix_world@v.co for v in o.data.vertices]
    return [[min(p[i] for p in ps) for i in range(3)],[max(p[i] for p in ps) for i in range(3)]]


def align():
    caps=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Entry parapet cap')]
    assert len(caps)==2
    boxes=[bounds(o) for o in caps]
    left=min(b[0][0] for b in boxes);right=max(b[1][0] for b in boxes);front=min(b[0][1] for b in boxes)
    result=[]
    for name,y0,y1 in [('Entry upper step',front,0),('Entry lower step',front-.60,front)]:
        o=bpy.data.objects[name];before=bounds(o);world=o.matrix_world.copy();inv=world.inverted()
        old=[world@v.co for v in o.data.vertices]
        # Each planar face's original UV affine map is retained in world metres.
        uv_maps=[]
        for layer in o.data.uv_layers:
            for face in o.data.polygons:
                ids=list(face.loop_indices)
                xyz=np.array([list(old[o.data.loops[i].vertex_index])+[1] for i in ids])
                uv=np.array([list(layer.data[i].uv) for i in ids])
                uv_maps.append((layer,ids,np.linalg.lstsq(xyz,uv,rcond=None)[0]))
        for v,p in zip(o.data.vertices,old):
            p=p.copy();p.x=left+(p.x-before[0][0])/(before[1][0]-before[0][0])*(right-left)
            p.y=y0+(p.y-before[0][1])/(before[1][1]-before[0][1])*(y1-y0)
            v.co=inv@p
        for layer,ids,mapping in uv_maps:
            for i in ids:
                p=world@o.data.vertices[o.data.loops[i].vertex_index].co
                layer.data[i].uv=np.array(list(p)+[1])@mapping
        o.data.update();after=bounds(o)
        assert abs(after[0][1]-y0)<1e-5 and abs(after[1][1]-y1)<1e-5
        assert abs(after[0][0]-left)<1e-5 and abs(after[1][0]-right)<1e-5
        assert abs(after[0][2]-before[0][2])<1e-5 and abs(after[1][2]-before[1][2])<1e-5
        result.append({'name':name,'before':before,'after':after,'collision_intent':o.get('collision_review'),'uv_world_scale_preserved':True})
    return {'caps':boxes,'platform_front_y':front,'stair_front_y':front-.60,'width':right-left,'lower_tread_depth_m':.60,'riser_m':.16,'changes':result}
