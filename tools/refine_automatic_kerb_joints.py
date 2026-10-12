"""Rebake the existing Blender stone material with readable recessed joints.

The original scanned maps and material master remain unchanged. All relief and
colour changes are shader-node authoring, baked together into matching PBR maps.
"""
from pathlib import Path
import json
import bpy

root = Path('D:/code/rmmo_runtime')
out = root / 'art_sources/automatic_kerb/stone_joints_v2'
source = Path(__file__).with_name('build_automatic_kerb_material.py').read_text(encoding='utf8')
source = source[:source.index('bpy.data.objects.remove(plane,do_unlink=True)')]
source = source.replace("out=root/'art_sources/automatic_kerb'", "out=root/'art_sources/automatic_kerb/stone_joints_v2'")
source = source.replace("mask=mathnode('LESS_THAN',fract,.018)", "mask=mathnode('LESS_THAN',fract,.030)")
source = source.replace("(.22,.20,.165,1)", "(.052,.046,.038,1)")
source = source.replace("bump.inputs['Distance'].default_value=.004;bump.inputs['Strength'].default_value=.65", "bump.inputs['Distance'].default_value=.005;bump.inputs['Strength'].default_value=.8")
source = source.replace("nt.links.new(original_color,mix.inputs[1])", """cell=mathnode('FLOOR',mathnode('MULTIPLY',sep.outputs['X'],4),0)
vary=mathnode('ADD',.94,mathnode('MULTIPLY',mathnode('SINE',mathnode('MULTIPLY',cell,2.13),0),.1))
tone=nt.nodes.new('ShaderNodeMixRGB');tone.blend_type='MULTIPLY';tone.inputs[0].default_value=1
nt.links.new(original_color,tone.inputs[1]);nt.links.new(vary,tone.inputs[2]);nt.links.new(tone.outputs[0],mix.inputs[1])""")
exec(compile(source, str(Path(__file__)), 'exec'))
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'material_master_v2.blend'))
original = json.loads((root / 'packs/default/assets/materials/paving/automatic_limestone_kerb/material.json').read_text(encoding='utf8'))
original['material']['name'] = '自动路缘·浅石灰岩·清晰石缝'
original['usage'] = '既有连续路缘的清晰石缝版本；1.76米重复四块石材，约13毫米凹缝。'
original['source']['process'] = 'Blender shader rebake from the original owned limestone: recessed darker joints and subtle block tone variation; original master retained.'
(out / 'material/material.json').write_text(json.dumps(original, ensure_ascii=False, indent=2), encoding='utf8')
print('KERB_JOINTS_V2_COMPLETE', str(out))
