"""Read a downloaded official Worlds SDK without installing or executing it."""
import bpy, json, re, sys
from pathlib import Path
from mathutils import Vector
args=sys.argv[sys.argv.index('--')+1:]
sdk=Path(args[0]);output=Path(args[1])
assets=sdk/'Samples/UdonExampleScene/SampleAssetsSet'
fbx=assets/'SampleAssetsSet_V1.fbx'
meta=fbx.with_suffix('.fbx.meta').read_text()
global_scale=float(re.search(r'globalScale: ([\d.]+)',meta).group(1))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(fbx))
report={'sdk':json.loads((sdk/'package.json').read_text())['version'],
        'unity_import_global_scale':global_scale,'use_file_scale':bool(re.search(r'useFileScale: 1',meta)),
        'references':{}}
for name in ['VRC_cube_A','VRC_cube_B']:
    obj=bpy.data.objects[name]
    points=[obj.matrix_world@Vector(v) for v in obj.bound_box]
    size=[max(p[i] for p in points)-min(p[i] for p in points) for i in range(3)]
    prefab=(assets/'Prefabs'/f'{name}_matte.prefab').read_text()
    collider=[float(v) for v in re.search(r'm_Size: \{x: ([\d.e-]+), y: ([\d.e-]+), z: ([\d.e-]+)\}',prefab).groups()]
    scale=[float(v) for v in re.search(r'm_LocalScale: \{x: ([\d.e-]+), y: ([\d.e-]+), z: ([\d.e-]+)\}',prefab).groups()]
    report['references'][name]={'blender_fbx_bounds_m':size,'unity_prefab_scale':scale,'unity_box_collider_size':collider}
    assert all(abs(size[i]*global_scale-collider[i])<.00001 for i in range(3)),name+' import compensation differs from prefab bounds'
assert all(abs(v-1)<.00001 for v in report['references']['VRC_cube_B']['unity_box_collider_size'])
output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
