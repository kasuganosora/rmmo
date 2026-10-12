"""Inspect actual GLB payloads, shared scene meshes and same-camera render pairs."""
import hashlib
import json
import struct
import argparse
from collections import defaultdict
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

parser=argparse.ArgumentParser();parser.add_argument('--set',choices=['furniture','furnishings','textiles_sanitary','guestroom'],default='furniture')
args=parser.parse_args()
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild')/(args.set+'_v1')
WB=OUT.parent/({'furniture':'whitebox_v4','furnishings':'whitebox_v5','textiles_sanitary':'whitebox_v6','guestroom':'whitebox_v7'}[args.set])
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
errors=[];results={}

def check(ok,label):
    if not ok:errors.append(label)

def glb(path):
    data=path.read_bytes();magic,version,size=struct.unpack_from('<III',data)
    assert magic==0x46546c67 and version==2 and size==len(data)
    size,typ=struct.unpack_from('<II',data,12);assert typ==0x4E4F534A
    return json.loads(data[20:20+size])

for kind,item in manifest['assets'].items():
    result={}
    for quality in ['master','game']:
        path=OUT/quality/(item['asset_id']+'.glb');g=glb(path)
        sha=hashlib.sha256(path.read_bytes()).hexdigest()
        tris=sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes'] for p in m['primitives'])
        check(sha==item[quality+'_glb_sha256'],kind+' export SHA')
        check(tris==item['stats'][quality]['triangles'],kind+' triangles')
        check(all('bufferView' in im and 'uri' not in im for im in g.get('images',[])),kind+' embedded maps')
        roots=[n for n in g['nodes'] if n.get('extras',{}).get('asset_id')==item['asset_id']]
        check(len(roots)==1 and roots[0]['extras'].get('independent_prop'),kind+' independent root')
        check(all('TEXCOORD_0' in p['attributes'] for m in g['meshes'] for p in m['primitives']),kind+' UV')
        result[quality]={'triangles':tris,'meshes':len(g['meshes']),'materials':len(g['materials']),
                         'packed_images':len(g.get('images',[])),'sha256':sha}
    a=np.asarray(Image.open(OUT/'preview'/(kind+'.png')).convert('RGB'),dtype=float)
    b=np.asarray(Image.open(OUT/'comparison'/(kind+'_master.png')).convert('RGB'),dtype=float)
    result['comparison']={'mean_abs_rgb_255':float(np.abs(a-b).mean()),
                          'percent_pixels_delta_over_10':float((np.abs(a-b).max(axis=2)>10).mean()*100),
                          'same_camera_light_exposure':True,'pixel_metric_is_not_visual_acceptance':True}
    result['triangle_reduction_percent']=100*(1-result['game']['triangles']/result['master']['triangles'])
    results[kind]=result

g=glb(WB/'axel_guild_whitebox.glb');wm=json.loads((WB/'manifest.json').read_text(encoding='utf8'))
instances=defaultdict(list)
def subtree_meshes(index):
    node=g['nodes'][index]
    return ([node['mesh']] if 'mesh' in node else [])+sum([subtree_meshes(i) for i in node.get('children',[])],[])
for i,node in enumerate(g['nodes']):
    if node.get('extras',{}).get('asset_source','').startswith(('../furniture_v1/','../furnishings_v1/','../textiles_sanitary_v1/','../guestroom_v1/')):
        instances[node['extras']['asset_id']].append(sorted(subtree_meshes(i)))
check(sum(map(len,instances.values()))==len(wm['furniture_instances']),'whitebox instance count')
for name,uses in instances.items():check(all(x==uses[0] for x in uses),name+' same mesh reused')
result={'failures':errors,'assets':results,'whitebox':{
    'sha256':hashlib.sha256((WB/'axel_guild_whitebox.glb').read_bytes()).hexdigest(),
    'instances':{k:len(v) for k,v in instances.items()},'shared_mesh_ids_checked':True},
    'not_tested':['editor catalogue publication','day/night runtime controller','sitting and opening interactions','cross-instance runtime batches']}
(OUT/'delivery_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
sheet=Image.new('RGB',(1600,((len(manifest['assets'])+3)//4)*460),(239,240,235));draw=ImageDraw.Draw(sheet)
for index,(kind,item) in enumerate(manifest['assets'].items()):
    x=index%4*400;y=index//4*460
    im=Image.open(OUT/'preview'/(kind+'.png')).convert('RGB');im.thumbnail((394,394))
    sheet.paste(im,(x+3,y+3));draw.text((x+15,y+400),item['label'],font=font,fill=(35,43,38))
    draw.text((x+15,y+433),f"{results[kind]['game']['triangles']:,} 三角面 · 独立 GLB",font=small,fill=(65,75,67))
sheet.save(OUT/'furniture_contact_sheet.jpg',quality=94)
comparison=Image.new('RGB',(1680,((len(manifest['assets'])+2)//3)*320),(239,240,235));cd=ImageDraw.Draw(comparison)
for index,(kind,item) in enumerate(manifest['assets'].items()):
    x=index%3*560;y=index//3*320
    for column,path in enumerate([OUT/'preview'/(kind+'.png'),OUT/'comparison'/(kind+'_master.png')]):
        im=Image.open(path).convert('RGB');im.thumbnail((278,278));comparison.paste(im,(x+column*280,y+30))
    cd.text((x+8,y+5),item['label']+' · 左游戏 / 右母版',font=small,fill=(35,43,38))
comparison.save(OUT/'master_game_comparison.jpg',quality=95)
print(json.dumps({'errors':errors,'asset_count':len(results),'whitebox_instances':sum(map(len,instances.values())),
                  'game_triangles':sum(r['game']['triangles'] for r in results.values()),
                  'master_triangles':sum(r['master']['triangles'] for r in results.values())}))
raise SystemExit(bool(errors))
