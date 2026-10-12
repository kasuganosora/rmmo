"""Synchronize four inner lining apertures with the established exterior openings."""
import bpy

APERTURES = [
    ('203 TWIN side.001', (31.45,31.70,2.95,4.05,5.48,7.28)),
    ('204 TWIN side.001', (31.45,31.70,5.95,7.05,5.48,7.28)),
    ('05 WASHROOM side.001', (31.45,31.70,10.05,11.15,5.48,7.28)),
    ('05 WASHROOM end.001', (28.95,30.05,13.45,13.65,5.48,7.28)),
]

def cut_box(obj, bounds):
    x0,x1,y0,y1,z0,z1=bounds
    bpy.ops.mesh.primitive_cube_add(size=1,location=((x0+x1)/2,(y0+y1)/2,(z0+z1)/2))
    cutter=bpy.context.object
    cutter.dimensions=(x1-x0,y1-y0,z1-z0)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    bpy.context.view_layer.objects.active=obj
    modifier=obj.modifiers.new('Window through inner lining','BOOLEAN')
    modifier.operation='DIFFERENCE';modifier.solver='EXACT';modifier.object=cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    obj['window_lining_repaired']=True

def repair():
    result=[]
    for name,bounds in APERTURES:
        obj=bpy.data.objects[name]
        cut_box(obj,bounds)
        result.append({'name':name,'opening_world_blender':bounds,'closed_reveal_surfaces':True})
    return result
