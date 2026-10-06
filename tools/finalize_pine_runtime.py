"""Declare clipped, double-sided foliage explicitly for portable glTF import."""
import json,struct,sys
from pathlib import Path
out=Path('D:/code/rmmo_runtime/assets/baltic_pine_dense_v3')
if '--fine-clusters' in sys.argv:out=out.with_name(out.name+'_fine')
if '--game-cards' in sys.argv:out=out.with_name(out.name+'_game')
for row in json.loads((out/'manifest.json').read_text(encoding='utf-8')):
 p=Path(row['file']);raw=p.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
 for mat in doc.get('materials',[]):
  mat['name']=mat.get('name','Material').replace('|','_')
  if 'needle_volume' in mat.get('name','') or 'needle volume' in mat.get('name',''):
   mat['alphaMode']='MASK';mat['alphaCutoff']=.45;mat['doubleSided']=True
   mat.setdefault('pbrMetallicRoughness',{})['roughnessFactor']=.57
   if 'normalTexture' in mat:mat['normalTexture']['scale']=1.
 if '--fine-clusters' in sys.argv or '--game-cards' in sys.argv:
  for node in doc.get('nodes',[]):
   if 'mesh' not in node:continue
   primitives=doc['meshes'][node['mesh']]['primitives']
   strengths=[.14 if 'needle_volume' in doc['materials'][p['material']].get('name','') and 'LOD2' not in doc['materials'][p['material']].get('name','') else 0. for p in primitives]
   if any(strengths):node.setdefault('extras',{})['rmmo_leaf_backlight']=strengths
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 p.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
 print('MASK_READY',p.name,p.stat().st_size)
