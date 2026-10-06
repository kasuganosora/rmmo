"""Pad color/normal inside each atlas tile WITHOUT expanding alpha coverage.

Run with system Python (Pillow/NumPy/SciPy), after bake and before reuse export.
The saved unpadded input makes this operation deterministic and reversible.
"""
from pathlib import Path
import json, shutil, sys
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT=Path('D:/code/rmmo_runtime/assets/baltic_pine_dense_v3')
TILE=128
if '--game-cards' in sys.argv:ROOT=ROOT.with_name(ROOT.name+'_game');TILE=256
BACKUP=ROOT/'zero_margin_unpadded';BACKUP.mkdir(exist_ok=True)
rows=[]
for path in sorted(ROOT.glob('Branch*_optimized_cluster_color.png')):
 normal=path.with_name(path.name.replace('_color','_normal'))
 for f in (path,normal):
  if not (BACKUP/f.name).exists():shutil.copy2(f,BACKUP/f.name)
 color=np.array(Image.open(BACKUP/path.name).convert('RGBA'))
 norms=np.array(Image.open(BACKUP/normal.name).convert('RGBA'))
 original_alpha=color[:,:,3].copy()
 for y in range(0,color.shape[0],TILE):
  for x in range(0,color.shape[1],TILE):
   c=color[y:y+TILE,x:x+TILE];n=norms[y:y+TILE,x:x+TILE]
   valid=c[:,:,3]>127
   if not valid.any():continue
   nearest=distance_transform_edt(~valid,return_distances=False,return_indices=True)
   c[:,:,:3]=c[nearest[0],nearest[1],:3]
   n[:,:,:3]=n[nearest[0],nearest[1],:3]
 assert np.array_equal(color[:,:,3],original_alpha)
 Image.fromarray(color).save(path);Image.fromarray(norms).save(normal)
 rows.append({'file':path.name,'alpha_unchanged':True,'opaque_pixels':int((original_alpha>127).sum())})
 print('PADDED_RGB_ONLY',path.name,flush=True)
(ROOT/'channel_padding.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
