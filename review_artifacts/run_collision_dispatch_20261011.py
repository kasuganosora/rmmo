import subprocess
import sys

for label, first in [('b1',True),('b2',True),('a2',False)]:
    name=f'loading_collision_dispatch_{label}_20261011'
    command=[sys.executable,'tools/profile_load_hardware.py','--timeout','600',
             '--log',f'review_artifacts/{name}.log','--hardware',f'review_artifacts/{name}.hardware.json','--',
             'D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path','D:/code/rmmo',
             '--script','res://tools/profile_game_entry.gd','--',
             '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
             f'--output=D:/code/rmmo_runtime/review_artifacts/{name}.json','--spawn=321.2,0.9,160.3',
             '--monitor','--with-collision-first','--with-no-collision-proof','--collision-scheduler-profile',
             '--dispatch-before-collision-installation' if first else '--dispatch-after-collision-installation']
    print('Start dispatch '+label,flush=True)
    code=subprocess.run(command,cwd='D:/code/rmmo').returncode
    if code:sys.exit(code)
print('Dispatch comparison complete',flush=True)
