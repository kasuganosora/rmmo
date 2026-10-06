import bpy,sys,json
from pathlib import Path
sys.path.insert(0,str(Path('D:/code/rmmo/tools')))
from build_blender_parametric_pine import OUT,nodes,setval
bpy.ops.wm.open_mainfile(filepath=str(OUT/'baltic_pine_parametric.blend'))
col=bpy.data.collections
ng=nodes(col['SOURCE_D | original modules (read only)'],col['SOURCE_D | conservative optimized modules'],col['SOURCE_D | original trunk'],col['SOURCE_D | optimized trunk'])
controllers=[o for o in bpy.data.objects if o.modifiers and o.modifiers[0].type=='NODES']
checks=[]
for o in controllers:
 mod=o.modifiers[0];old=mod.node_group
 vals={s.name:mod.get(s.identifier,s.default_value) for s in old.interface.items_tree if s.item_type=='SOCKET' and s.in_out=='INPUT'}
 mod.node_group=ng
 for name,val in vals.items():setval(o,name,val)
 setval(o,'Leafy branch size',1.6);setval(o,'Bare trunk shortening (m)',.5)
 setval(o,'Optimized',True)
 checks.append({'object':o.name,'branch_scale':1.6,'bare_trunk_shortening_m':.5})
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
tree=bpy.data.objects['BALTIC PINE | editable parameters']
# Verify every rooted branch is translated down by exactly 0.5 m above q=.25.
setval(tree,'Bare trunk shortening (m)',0.);bpy.context.view_layer.update()
def origins():
 return {i.object.original.name:tuple(i.matrix_world.translation) for i in bpy.context.evaluated_depsgraph_get().object_instances if i.is_instance}
a=origins();setval(tree,'Bare trunk shortening (m)',.5);bpy.context.view_layer.update();b=origins()
assert len(a)==len(b)==583
errors=[abs((a[k][2]-b[k][2])-.5) for k in a]
assert max(errors)<.00001,max(errors)
assert all(abs(a[k][axis]-b[k][axis])<.00001 for k in a for axis in [0,1])
report={'passed':True,'objects':checks,'branch_instances':583,'maximum_crown_lowering_error_m':max(errors),'density_method':'Rooted needle-bearing branches scaled 1.0 -> 1.6, preserving geometry and shared instances','game_integration':False}
(OUT/'dense_v2_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
bpy.data.texts['README | BALTIC PINE'].write('\nRevision 2: rooted needle branch size 1.6; bare trunk shortened by 0.50 m. Crown translated down, root stays at ground. Original revision retained in separate blend.\n')
file=OUT/'baltic_pine_dense_v2.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(file),compress=True)
for name,flag in [('master',False),('optimized',True)]:
 setval(tree,'Optimized',flag);sc.render.filepath=str(OUT/f'dense_v2_{name}.png');bpy.ops.render.render(write_still=True)
setval(tree,'Optimized',True)
pr=bpy.data.scenes['PRESETS | compact - mature - windswept'];pr.render.filepath=str(OUT/'dense_v2_three_presets.png')
bpy.ops.render.render(write_still=True,scene=pr.name)
bpy.context.window.scene=sc
bpy.ops.wm.save_as_mainfile(filepath=str(file),compress=True)
bpy.ops.wm.open_mainfile(filepath=str(file));assert all(i.packed_file for i in bpy.data.images if i.source=='FILE')
report['saved_and_reopened']=True;(OUT/'dense_v2_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('DENSE_PINE_V2_COMPLETE',flush=True)
