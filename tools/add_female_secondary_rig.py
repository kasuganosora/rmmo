"""Blender: add reusable breast bones and smoothly transfer existing skin weights."""
import bpy, math, sys
from mathutils import Vector
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path

def add_secondary_rig(gender='female'):
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    inverse=rig.matrix_world.inverted()
    for side,sign in [('Left',1),('Right',-1)]:
        name='SecondaryBreast'+side
        bone=rig.data.edit_bones.get(name) or rig.data.edit_bones.new(name)
        bone.parent=rig.data.edit_bones['mixamorig:Spine2']
        bone.use_connect=False;bone.use_deform=True
        bone.head=inverse@Vector((sign*(.099 if gender=='male' else .085),-.075,1.772 if gender=='male' else 1.71))
        bone.tail=inverse@Vector((sign*(.099 if gender=='male' else .085),-.19,1.772 if gender=='male' else 1.71))
    bpy.ops.object.mode_set(mode='OBJECT')
    if gender=='male':return
    for name in ['Body','Clothing1','BaseTop']:
        obj=bpy.data.objects[name]
        # Reject duplicate weight transfer; rerun the full builder from its clean source.
        previous=[obj.vertex_groups.get('SecondaryBreast'+s) for s in ['Left','Right']]
        if any(previous):
            raise RuntimeError('Secondary rig weights already exist; rebuild from the clean source')
        left=obj.vertex_groups.new(name='SecondaryBreastLeft')
        right=obj.vertex_groups.new(name='SecondaryBreastRight')
        affected=0
        for vertex in obj.data.vertices:
            x,y,z=obj.matrix_world@vertex.co
            t=max(0,min(1,(-y-.03)/.08));front=t*t*(3-2*t)
            weight=.92*math.exp(-((abs(x)-.085)/.115)**4-((z-1.70)/.15)**4)*front
            if weight<.0001:continue
            original=[(g.group,g.weight) for g in vertex.groups]
            total=sum(w for _,w in original)
            if total<=0:continue
            for index,w in original:obj.vertex_groups[index].add([vertex.index],w/total*(1-weight),'REPLACE')
            # Blend through the center line; the two sides remain independent.
            split=max(0,min(1,(x+.025)/.05));split=split*split*(3-2*split)
            if split>0:left.add([vertex.index],weight*split,'REPLACE')
            if split<1:right.add([vertex.index],weight*(1-split),'REPLACE')
            affected+=1
        print('SECONDARY_WEIGHTS',name,affected,flush=True)

if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    gender='male' if '--male' in sys.argv else 'female'
    output=art_path(f'characters/imported/{gender}')
    bpy.ops.wm.open_mainfile(filepath=str(output/'editable/character.blend'))
    add_secondary_rig(gender)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'editable/character.blend'))
    bpy.ops.export_scene.gltf(filepath=str(output/'character.glb'),export_format='GLB',export_animations=False,export_yup=True)
