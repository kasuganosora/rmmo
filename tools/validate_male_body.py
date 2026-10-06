"""Blender regression check against a pre-edit male .blend backup.

Run with --python-exit-code 1 --python tools/validate_male_body.py -- BASELINE.
This complements, and does not replace, runtime visual inspection.
"""
import sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from art_paths import art_path

def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    face=bpy.data.objects['Face'].data
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    return {
        'face':{s.name:[tuple(v.co) for v in s.data] for s in face.shape_keys.key_blocks},
        'bones':{b.name:(b.parent.name if b.parent else '',[tuple(row) for row in b.matrix_local]) for b in rig.data.bones},
        'body_vertices':len(bpy.data.objects['Body'].data.vertices),
    }

baseline=snapshot(Path(sys.argv[sys.argv.index('--')+1]))
gender='female' if '--female' in sys.argv else 'male'
current=snapshot(art_path(f'characters/imported/{gender}/editable/character.blend'))
assert baseline['face']==current['face'], 'Facial expression coordinates changed'
assert len(current['face'])==57, 'Expected original 57 expression shapes'
assert baseline['bones']==current['bones'], 'Shared skeleton or rest pose changed'
assert baseline['body_vertices']==current['body_vertices'], 'Body topology count changed'
for name in ['Body','Clothing1','Clothing2','Stockings','BaseBottom','Belt']:
    obj=bpy.data.objects.get(name)
    if obj is None:continue
    for v in obj.data.vertices:
        total=sum(g.weight for g in v.groups)
        assert abs(total-1)<.002, (name,v.index,'unnormalized skin weights',total)
print('PASS: identical shared rest skeleton, 57 unchanged facial shapes, body vertex count and normalized garment/body weights')
