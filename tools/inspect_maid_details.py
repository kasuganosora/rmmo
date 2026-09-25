import bpy
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
root=Path.cwd();bpy.ops.wm.open_mainfile(filepath=str(art_path('characters/source_models/maid/inspected.blend')))
o=bpy.data.objects['Body'];print('ALLGROUPS',[g.name for g in o.vertex_groups])
for k in [2,3]:
 ids={i for f in o.data.polygons if f.material_index==k for i in f.vertices};ps=[o.matrix_world@o.data.vertices[i].co for i in ids];print('MAT',k,len(ids),[[min(p[j] for p in ps),max(p[j] for p in ps)] for j in range(3)])
