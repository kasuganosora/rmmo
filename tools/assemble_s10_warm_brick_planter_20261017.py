"""Replace masonry dependency graph; keep scanned boxwood exact, then compact."""
import argparse,copy,hashlib,importlib.util,json,struct
from pathlib import Path
import optimize_bridge_pennant_glb as ref
P=argparse.ArgumentParser();P.add_argument('--version',default='v1');A=P.parse_args()
BASE=Path('D:/code/rmmo_runtime/art_sources/s10_warm_brick_planter_20261017');OUT=BASE/A.version
SOURCE=Path('D:/code/rmmo_runtime/packs/default/assets/8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a.glb');NAME='s10_warm_redbrick_planter'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):
    r=Path(p).read_bytes();jl=struct.unpack_from('<I',r,12)[0];return json.loads(r[20:20+jl]),r[28+jl:]
def write(p,d,b):
    j=json.dumps(d,ensure_ascii=False,separators=(',',':')).encode();j+=b' '*((-len(j))%4);b+=b'\0'*((-len(b))%4)
    assert not p.exists();p.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(b))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(b),0x004e4942)+b)
d,oldbin=read(SOURCE);part,pb=read(OUT/'brick_structure.glb');original=copy.deepcopy(d)
assert len(d['nodes'])==2 and len(d['meshes'])==2 and d['nodes'][0]['name']=='Structure' and d['nodes'][1]['name']=='Foliage'
assert len(part['meshes'])==1 and not d.get('extensionsUsed') and not part.get('extensionsUsed')
offset={k:len(d.get(k,[])) for k in ['accessors','bufferViews','materials','images','textures','samplers']};binary=oldbin+b'\0'*((-len(oldbin))%4);byte_offset=len(binary)
for v in part['bufferViews']:
    v=copy.deepcopy(v);v['byteOffset']=v.get('byteOffset',0)+byte_offset;d['bufferViews'].append(v)
for a in part['accessors']:
    a=copy.deepcopy(a);a['bufferView']+=offset['bufferViews'];d['accessors'].append(a)
for k in ['samplers','images','textures','materials']:
    for a in part.get(k,[]):
        a=copy.deepcopy(a)
        if k=='images':a['bufferView']+=offset['bufferViews']
        if k=='textures':
            a['source']+=offset['images']
            if 'sampler' in a:a['sampler']+=offset['samplers']
        if k=='materials':
            for slot in ref.texture_slots(a):slot['index']+=offset['textures']
        d.setdefault(k,[]).append(a)
new_mesh=copy.deepcopy(part['meshes'][0]);new_mesh['name']='S10 warm small-brick masonry and soil'
for p in new_mesh['primitives']:
    p['attributes']={k:v+offset['accessors'] for k,v in p['attributes'].items()};p['indices']+=offset['accessors'];p['material']+=offset['materials']
d['meshes'][0]=new_mesh;d['scenes'][0]['name']=NAME;d['buffers']=[{'byteLength':len(binary)+len(pb)}]
d['asset']['generator']='S10 masonry replacement; original boxwood mesh/material/UV/wind bytes preserved'
assembled=OUT/(NAME+'_uncompacted.glb');write(assembled,d,binary+pb)
# Reuse conservative complete static glTF graph compactor. No image re-encoding.
spec=importlib.util.spec_from_file_location('s10_compact',Path('D:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/architecture_lossless.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.OUT=OUT
mod.compact({'path':str(assembled),'source_sha256':sha(assembled)},NAME)
candidate=OUT/(NAME+'_lossless.glb');target=OUT/(NAME+'.glb');assert not target.exists();target.write_bytes(candidate.read_bytes())
before=ref.Glb(SOURCE);after=ref.Glb(target);sb=ref.semantic(before);sa=ref.semantic(after)
assert sb['meshes'][1]==sa['meshes'][1] and original['nodes']==after.j['nodes']
foliage_fingerprint=hashlib.sha256(json.dumps(sb['meshes'][1],sort_keys=True,separators=(',',':')).encode()).hexdigest();before.close();after.close()
recipe=json.loads((OUT/'masonry_recipe.json').read_text(encoding='utf-8'))
author={'id':NAME,'path':target.as_posix(),'sha256':sha(target),'bytes':target.stat().st_size,'master':(OUT/(NAME+'_master.blend')).as_posix(),'master_sha256':None,'source':SOURCE.as_posix(),'source_sha256':sha(SOURCE),'source_unchanged':sha(SOURCE)==SOURCE.stem,'foliage_exact_reuse':{'resolved_graph_sha256':foliage_fingerprint,'node_transform_extras_unchanged':True,'accessor_and_encoded_image_bytes_equal':True,'materials_uv_alpha_wind_unchanged':True},'anchors':{'ground_origin':[0,0,0],'front_axis':'+Z','masonry_center':[-.036979496479034424,0,.01252889633178711],'scale_recommendation':[1,1,1]},'masonry':recipe,'scope':'S10 independent warm red small-brick variant only; original citywide planter and all maps unchanged. Preserve native overall foliage dimensions and collision blocking behavior; physical clay units and recessed joints are project supplementary design.'}
(OUT/(NAME+'_authoring.json')).write_text(json.dumps(author,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('S10_BRICK_VARIANT',author['sha256'],target.stat().st_size,flush=True)
