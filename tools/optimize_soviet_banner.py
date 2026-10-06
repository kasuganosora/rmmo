"""Rebuild the approved Soviet banner on a regular 24 x 84 cloth grid.

Requires build_soviet_swallowtail.py output. Leaves that master untouched.
Review preview/emblem_detail against the parent images before publishing.
"""
from pathlib import Path
import shutil
import subprocess

BASE = Path('D:/code/rmmo_runtime/art_sources/wall_guild_banners/soviet_variant')
OUT = BASE / 'optimized'
OUT.mkdir(exist_ok=True)
shutil.copy2(BASE / 'emblem_mask.png', OUT / 'emblem_mask.png')
script = (BASE / 'build_blender.py').read_text(encoding='utf8')
script = script.replace(f"OUT=Path('{BASE.as_posix()}')", f"OUT=Path('{OUT.as_posix()}')")
script = script.replace('BASE=OUT.parent', 'BASE=OUT.parent.parent')
source = (Path(__file__).parent / 'build_wall_guild_banners.py').read_text(encoding='utf8')
body = source[source.index('def body('):source.index('assets=[]')]
replacement = body + '''
old=cloth
spec=dict(id='soviet_swallowtail_tall',width=1.15,height=7.2,cut=.72,top=7.5,pattern='compass',mat=m)
cloth=body(spec,24,84)
parts.remove(old);parts.append(cloth);bpy.data.objects.remove(old,do_unlink=True)
'''
script = script.replace('cam=sc.camera;', replacement + '\ncam=sc.camera;')
target = OUT / 'build_blender.py'
target.write_text(script, encoding='utf8')
with (OUT / 'build.log').open('w', encoding='utf8') as log:
    result = subprocess.run(['C:/Program Files/Blender Foundation/Blender 4.5/blender.exe', '-b', '--python', str(target)], stdout=log, stderr=subprocess.STDOUT)
raise SystemExit(result.returncode)
