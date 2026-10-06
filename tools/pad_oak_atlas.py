"""Normalize two-sided baked leaf normals and pad RGB without growing alpha."""
from pathlib import Path
import shutil,json
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
root=Path('D:/code/rmmo_runtime/assets/street_oak_game')
backup=root/'unprocessed_bake';backup.mkdir(exist_ok=True)
rows=[]
for path in root.glob('*_cluster_color.png'):
 normal=path.with_name(path.name.replace('_color','_normal'))
 for f in [path,normal]:
  if not (backup/f.name).exists():shutil.copy2(f,backup/f.name)
 c=np.array(Image.open(backup/path.name).convert('RGBA'));n=np.array(Image.open(backup/normal.name).convert('RGBA'));alpha=c[:,:,3].copy()
 valid=alpha>127;back=valid&(n[:,:,2]<128)
 # Baking can hit the underside of a disconnected two-sided leaf. Orient its
 # tangent normal into the receiver's hemisphere; retain the real curvature.
 n[back,:3]=255-n[back,:3]
 for y in range(0,c.shape[0],128):
  for x in range(0,c.shape[1],128):
   a=c[y:y+128,x:x+128];b=n[y:y+128,x:x+128];mask=a[:,:,3]>127
   if not mask.any():continue
   nearest=distance_transform_edt(~mask,return_distances=False,return_indices=True)
   a[:,:,:3]=a[nearest[0],nearest[1],:3];b[:,:,:3]=b[nearest[0],nearest[1],:3]
 assert np.array_equal(alpha,c[:,:,3])
 Image.fromarray(c).save(path);Image.fromarray(n).save(normal)
 rows.append({'file':path.name,'reoriented_normal_pixels':int(back.sum()),'alpha_unchanged':True})
(root/'normal_padding.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
