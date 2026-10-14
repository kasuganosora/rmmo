"""Apply the S10 grey-brown bark response without touching any mesh or image.

Run in background Blender. The source mother gets the same linear multiply
node as the portable glTF baseColorFactor; original encoded maps stay intact.
"""
from pathlib import Path
import bpy
import hashlib
import json
import shutil
import struct

ART=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2')
FACTOR=(.30,.36,.36,1.)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    manifest_path=ART/'manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    row=next(r for r in manifest['assets'] if r['id']=='s10_redfruit_broadleaf')
    path=Path(row['path']);mother=Path(row['source_blend'])
    before_sha=sha(path)
    assert before_sha==row['sha256']
    unchanged={r['path']:sha(r['path']) for r in manifest['assets'] if r is not row}
    rollback=ART/'rollback/tree_bark_tone_v1';rollback.mkdir(parents=True,exist_ok=True)
    for p in (path,mother,manifest_path):
        if not (rollback/p.name).exists():shutil.copy2(p,rollback/p.name)

    bpy.ops.wm.open_mainfile(filepath=str(mother))
    mats=[m for m in bpy.data.materials if 'bark' in m.name.lower() and m.use_nodes]
    assert len(mats)==1
    for mat in mats:
        p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        socket=p.inputs['Base Color']
        node=mat.node_tree.nodes.get('S10 grey brown bark multiplier')
        if node is None:
            assert socket.is_linked
            previous=socket.links[0].from_socket
            node=mat.node_tree.nodes.new('ShaderNodeMixRGB')
            node.name='S10 grey brown bark multiplier';node.blend_type='MULTIPLY'
            node.inputs[0].default_value=1.
            mat.node_tree.links.new(previous,node.inputs[1])
            mat.node_tree.links.new(node.outputs[0],socket)
        node.inputs[2].default_value=FACTOR
        mat['s10_bark_linear_factor']=list(FACTOR)
        mat['reference_note']='S10 weathered grey-brown bark; image, UV, geometry and normal preserved'
    bpy.ops.wm.save_as_mainfile(filepath=str(mother),compress=True)

    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);tail=raw[20+length:]
    old_doc=json.loads(raw[20:20+length]);edited=[]
    for index,mat in enumerate(doc['materials']):
        if 'bark' not in mat.get('name','').lower():continue
        mat['pbrMetallicRoughness']['baseColorFactor']=list(FACTOR);edited.append(index)
    assert len(edited)==1
    comparable=json.loads(json.dumps(doc))
    for index in edited:
        if 'baseColorFactor' in old_doc['materials'][index]['pbrMetallicRoughness']:
            comparable['materials'][index]['pbrMetallicRoughness']['baseColorFactor']=old_doc['materials'][index]['pbrMetallicRoughness']['baseColorFactor']
        else:comparable['materials'][index]['pbrMetallicRoughness'].pop('baseColorFactor')
    assert comparable==old_doc
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
    row.update(sha256=sha(path),source_bytes=path.stat().st_size,review_state='S10 bark tone corrected; current native/GPU review pending')
    manifest['bark_tone_revision']='S10 grey-brown linear multiplier; images and full BIN unchanged'
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    assert all(sha(p)==s for p,s in unchanged.items())
    record={'source_sha_before':before_sha,'source_sha_after':row['sha256'],'mother_sha':sha(mother),'linear_factor':FACTOR,
            'geometry_images_bin_unchanged':True,'other_json_unchanged':True,'unchanged_other_assets':unchanged,
            'observed_reason':'Current-SHA trunk and near views were pale yellow, inconsistent with S10 grey-brown bark; roughness .88 and normal .55 retained.'}
    (ART/'tree_bark_tone_report.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print('BARK_TONE_REPAIRED',row['sha256'],flush=True)

if __name__=='__main__':main()
