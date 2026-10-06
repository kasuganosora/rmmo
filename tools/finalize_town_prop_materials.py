"""Technical glTF channel packing: explicit leaf masks and portable game glass."""
import json,struct,io
from pathlib import Path
from PIL import Image
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'assets/town_props_20261006'
source=ROOT/'art_sources/town_planters/sources/boxwood_rjepadp2'
color=Image.open(source/'Boxwood_rjepadp2_4K_BaseColor.jpg').convert('RGBA')
color.putalpha(Image.open(source/'Boxwood_rjepadp2_4K_Opacity.jpg').convert('L'))
png=io.BytesIO();color.save(png,format='PNG');rgba=png.getvalue()
changed=[]
for row in json.loads((OUT/'manifest.json').read_text()):
    path=Path(row['file']);raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=bytearray(raw[28+size:]);dirty=False
    for mat in doc.get('materials',[]):
        if 'Quixel Boxwood' in mat.get('name',''):
            if mat.get('extras',{}).get('rmmo_opacity_packed'):continue
            binary.extend(b'\0'*((-len(binary))%4));offset=len(binary);binary.extend(rgba)
            view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(rgba)})
            index=len(doc['images']);doc['images'].append({'bufferView':view,'mimeType':'image/png','name':'Boxwood_RGBA'})
            previous=doc['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]
            texture=dict(previous);texture['source']=index;ti=len(doc['textures']);doc['textures'].append(texture)
            mat['pbrMetallicRoughness']['baseColorTexture']['index']=ti;mat['alphaMode']='MASK';mat['alphaCutoff']=.45;mat['doubleSided']=True
            mat.setdefault('extras',{})['rmmo_opacity_packed']=True;dirty=True
        transmission=mat.get('extensions',{}).get('KHR_materials_transmission',{}).get('transmissionFactor',0)
        if transmission and mat.get('name')!='Slightly aged lantern glass':
            mat['alphaMode']='BLEND';mat['doubleSided']=True
            pbr=mat['pbrMetallicRoughness'];base=pbr.setdefault('baseColorFactor',[1,1,1,1]);base[3]=1-.65*transmission
            mat['extensions'].pop('KHR_materials_transmission',None);dirty=True
        if mat.get('name')=='Slightly aged lantern glass' and (transmission or mat.get('alphaMode')!='BLEND'):
            mat['alphaMode']='BLEND';mat['doubleSided']=True;mat['pbrMetallicRoughness']['baseColorFactor']=[.83,.88,.81,.16]
            mat.pop('extensions',None);dirty=True
        if 'Hanging_pennant' in mat.get('name','') and 'normalTexture' in mat and mat['normalTexture'].get('scale',1)!=.18:
            mat['normalTexture']['scale']=.18;dirty=True
    for node in doc.get('nodes',[]):
        if 'mesh' not in node:continue
        extras=node.setdefault('extras',{});soft=extras.get('rmmo_wind',{}).get('profile') in ['foliage','cloth'] or extras.get('rmmo_small_wall_lantern',False)
        if soft and extras.get('rmmo_collision')!='none':extras['rmmo_collision']='none';dirty=True
    if not dirty:continue
    doc['buffers'][0]['byteLength']=len(binary);binary.extend(b'\0'*((-len(binary))%4))
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    blob=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
    path.write_bytes(blob);changed.append(row['id'])
(OUT/'material_fix_report.json').write_text(json.dumps({'changed':changed,'leaf_alpha':'source opacity packed without changing RGB','glass':'portable alpha blend','flag_normal_scale':.18},indent=2))
print('MATERIALS_FINALIZED',changed)
