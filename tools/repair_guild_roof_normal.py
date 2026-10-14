"""One normal-image-only roof repair of the e24b window-repaired master.

Run in Blender background. No geometry, UV, colour/roughness/AO or other
material changes are permitted. Direct GLB image replacement preserves every
other bufferView byte, including textures and mesh attributes.
"""
import hashlib,json,shutil,struct,sys
from pathlib import Path
import bpy,numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from axel_guild_reference_exterior_materials import _fishscale_relief_normal

ROOT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
BACKUP=ROOT/'rollback_before_roof_normal_20261013'
REPORT=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/roof_normal_repair')
EXPECTED='e24b27bea05a283b3518f659f017f18868336117812674d3ee725eb8008fb7a7'
NAME='Guild PBR | terracotta | reference 20261013'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def parse(path):
    raw=Path(path).read_bytes();magic,version,length=struct.unpack_from('<III',raw)
    assert magic==0x46546c67 and version==2 and length==len(raw)
    size,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
    doc=json.loads(raw[20:20+size]);count,kind=struct.unpack_from('<II',raw,20+size);assert kind==0x004e4942
    return doc,raw[28+size:28+size+count]

def main():
    source=ROOT/'axel_guild_repaired.glb';master=ROOT/'axel_guild_repaired.blend'
    manifest_path=ROOT/'repair_manifest.json'
    target=ROOT/'materials/guild_fishscale_large_repeat_normal.png'
    assert sha(source)==EXPECTED,'Only run against the current window-repaired master'
    others={str(p):sha(p) for p in list((ROOT/'library').glob('*.glb'))+[ROOT/'guild_alarm_tower.glb',ROOT/'guild_alarm_tower.blend']}
    other_maps={str(p):sha(p) for p in (ROOT/'materials').glob('*.png') if p!=target}
    BACKUP.mkdir(exist_ok=True);REPORT.mkdir(parents=True,exist_ok=True)
    for p in [source,master,manifest_path,target]:
        dest=BACKUP/p.name
        if dest.exists():assert sha(dest)==sha(p),'Immutable rollback already differs'
        else:shutil.copyfile(p,dest)
    doc,binary=parse(source)
    mi=next(i for i,m in enumerate(doc['materials']) if m.get('name')==NAME)
    mat=doc['materials'][mi];ti=mat['normalTexture']['index'];ii=doc['textures'][ti]['source'];bi=doc['images'][ii]['bufferView']
    assert (mi,ti,ii,bi)==(135,178,54,3637)
    assert [i for i,img in enumerate(doc['images']) if img.get('bufferView')==bi]==[ii]
    assert all(a.get('bufferView')!=bi for a in doc['accessors'])
    bpy.ops.wm.open_mainfile(filepath=str(master))
    bm=bpy.data.materials[NAME]
    principled=next(n for n in bm.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    normal_node=principled.inputs['Normal'].links[0].from_node
    assert normal_node.type=='NORMAL_MAP'
    image_node=normal_node.inputs['Color'].links[0].from_node;im=image_node.image
    assert im.name.startswith('guild_fishscale_large_repeat_normal') and tuple(im.size)==(2048,2048)
    normal=_fishscale_relief_normal(2048)
    rgba=np.ones((2048,2048,4),np.float32);rgba[:,:,:3]=normal
    im.colorspace_settings.name='Non-Color';im.pixels.foreach_set(np.flipud(rgba).ravel())
    candidate_map=target.with_name(target.stem+'_candidate.png')
    im.filepath_raw=str(candidate_map);im.file_format='PNG';im.save();im.pack()
    png=candidate_map.read_bytes();assert png.startswith(b'\x89PNG\r\n\x1a\n')
    im.filepath_raw=str(target);normal_node.inputs['Strength'].default_value=1.0
    candidate_master=ROOT/'axel_guild_roof_normal_candidate.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(candidate_master),compress=True)
    # Splice the one image bufferView; retain all other binary regions exactly.
    view=doc['bufferViews'][bi];start=view['byteOffset'];length=view['byteLength'];end=start+(length+3)//4*4
    payload=png+b'\x00'*(-len(png)%4);delta=len(payload)-(end-start)
    for i,v in enumerate(doc['bufferViews']):
        if i==bi:continue
        st=v.get('byteOffset',0);en=st+v['byteLength']
        assert en<=start or st>=end,'Unexpected shared image region'
    changed=binary[:start]+payload+binary[end:]
    old_views=[dict(v) for v in doc['bufferViews']]
    view['byteLength']=len(png)
    for i,v in enumerate(doc['bufferViews']):
        if i!=bi and v.get('byteOffset',0)>=end:v['byteOffset']+=delta
    doc['buffers'][0]['byteLength']+=delta
    mat['normalTexture']['scale']=1.0
    unchanged=[]
    for i,(before,after) in enumerate(zip(old_views,doc['bufferViews'])):
        if i==bi:continue
        old=binary[before.get('byteOffset',0):before.get('byteOffset',0)+before['byteLength']]
        new=changed[after.get('byteOffset',0):after.get('byteOffset',0)+after['byteLength']]
        assert old==new,f'Other bufferView changed: {i}'
        unchanged.append(i)
    encoded=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    candidate_glb=ROOT/'axel_guild_roof_normal_candidate.glb'
    candidate_glb.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(changed))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(changed),0x004e4942)+changed)
    nd,nb=parse(candidate_glb);assert nb==changed
    bpy.ops.wm.open_mainfile(filepath=str(candidate_master))
    check=bpy.data.materials[NAME]
    node=next(n for n in check.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Normal'].links[0].from_node
    assert node.inputs['Strength'].default_value==1.0
    assert sum(o.get('window_reveal_revision')=='20261013_lip12mm' for o in bpy.context.scene.objects)==140
    assert all(sha(p)==h for p,h in others.items()) and all(sha(p)==h for p,h in other_maps.items())
    newsha=sha(candidate_glb);candidate_map.replace(target);candidate_master.replace(master);candidate_glb.replace(source)
    manifest=json.loads(manifest_path.read_text(encoding='utf8'));manifest['final_sha256']=newsha
    manifest['roof_normal_revision']={'before_sha256':EXPECTED,'normal_image':ii,'material':mi,'normal_scale':1.0,'rollback':str(BACKUP),'generator':'metre gradient, 3x2.16m repeat, 5mm transverse camber and rounded overlap lip; shading only'}
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    decoded=normal*2-1;angles=np.degrees(np.arccos(np.clip(decoded[:,:,2],-1,1)))
    report={'source_sha256_before':EXPECTED,'source_sha256_after':newsha,'source':str(source),'rollback':str(BACKUP),'material_index':mi,'material_name':NAME,'normal_texture_index':ti,'image_index':ii,'buffer_view_index':bi,'normal_scale_before':.800000011920929,'normal_scale_after':1.0,'normal_image_sha256':sha(target),'normal_image_bytes':len(png),'normal_size':[2048,2048],'repeat_metres':[3,2.16],'normal_convention':'OpenGL +Y; array row-down derivative is positive green; original owned DX grain converted once','angle_percentiles_degrees':np.percentile(angles,[10,50,90,95,99,100]).tolist(),'all_other_buffer_views_byte_identical':unchanged,'all_other_external_material_maps_unchanged':other_maps,'unrelated_assets_unchanged':others,'window_reveal_140_revision_preserved':True,'allowed_json_differences':['materials/135/normalTexture/scale','bufferViews/3637/byteLength','bufferViews/*/byteOffset (after image54)','buffers/0/byteLength'],'geometry_uv_color_roughness_ao_unchanged':True,'limitations':'Normal shading relief only. No displacement, parallax, silhouette change or cast contact shadow is claimed.','native_and_visual_status':'pending new-source roof checks'}
    (REPORT/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('ROOF_NORMAL_REPAIRED',newsha,report['angle_percentiles_degrees'],flush=True)

if __name__=='__main__':main()
