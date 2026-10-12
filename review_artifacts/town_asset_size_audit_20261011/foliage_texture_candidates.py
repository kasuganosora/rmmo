"""Two unpublished texture profiles; geometry and material semantics unchanged."""
import copy
import hashlib
import importlib.util
import io
import json
import math
import struct
from pathlib import Path
from PIL import Image

REPO=Path('D:/code/rmmo')
OUT=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/foliage')
REVIEW=REPO/'review_artifacts/town_asset_size_audit_20261011'
module=importlib.util.spec_from_file_location('exact',REPO/'tools/optimize_bridge_pennant_glb.py')
exact=importlib.util.module_from_spec(module);module.loader.exec_module(exact)
cache={}

def sha(raw):return hashlib.sha256(raw).hexdigest()

def coverage(channel,cutoff):
    histogram=channel.histogram();threshold=math.ceil(cutoff*255)
    return sum(histogram[threshold:])/sum(histogram)

def preserved_alpha(channel,target,cutoff):
    histogram=channel.histogram();threshold=math.ceil(cutoff*255);count=sum(histogram)
    # For 8-bit alpha, each attainable mask count is determined by a threshold
    # in the original resized alpha histogram. Exhaust all those count changes.
    scales={1.0}
    for value in range(1,256):
        edge=(threshold-.5)/value
        scales.update([max(0.,edge-1e-9),edge+1e-9])
    best=None
    for scale in scales:
        lut=[min(255,int(math.floor(value*scale+.5)))for value in range(256)]
        actual=sum(n for value,n in enumerate(histogram)if lut[value]>=threshold)/count
        score=(abs(actual-target),abs(math.log(max(scale,1e-12))))
        if best is None or score<best[0]:best=(score,scale,lut,actual)
    return channel.point(best[2]),{'uniform_alpha_scale':best[1],'target_coverage':target,'after_coverage':best[3],
        'absolute_coverage_error':best[3]-target,'relative_coverage_error':(best[3]-target)/target if target else 0.,
        'cutoff':cutoff,'eight_bit_pass_threshold':threshold,'alpha_operation':'round(original_resized_alpha * uniform_scale), clamp [0,255]',
        'rgb_gain_applied':False,'discrete_histogram_optimum':True}

def transformed(raw,role,profile,cutoff):
    key=(sha(raw),role,profile,cutoff)
    if key in cache:return cache[key]
    with Image.open(io.BytesIO(raw))as original:
        original.load();rgba=original.convert('RGBA')
        assert rgba.size==(4096,4096)
        info={'source_encoded_sha256':sha(raw),'source_dimensions':list(rgba.size),'role':role}
        if role=='albedo' and profile=='pbr2k_albedo4k':
            info.update({'changed':False,'output_dimensions':list(rgba.size),'output_encoded_sha256':sha(raw),'filter':'none; original encoded bytes preserved'})
            cache[key]=(raw,info);return cache[key]
        channels=[ch.resize((2048,2048),Image.Resampling.BOX)for ch in rgba.split()]
        info.update({'changed':True,'output_dimensions':[2048,2048],'filter':'independent-channel 2x2 BOX average; no color-gain or gamma conversion'})
        if role=='albedo':
            target=coverage(rgba.getchannel('A'),cutoff)
            info['box_alpha_coverage_before_compensation']=coverage(channels[3],cutoff)
            rgb_before=[sha(ch.tobytes())for ch in channels[:3]]
            channels[3],compensation=preserved_alpha(channels[3],target,cutoff)
            info['alpha_coverage_compensation']=compensation
            assert rgb_before==[sha(ch.tobytes())for ch in channels[:3]]
        elif role=='normal':
            info['normal_policy']='Encoded XYZ channel BOX mean; no renormalization, sharpening, green inversion or strength change; constant alpha retained'
        elif role=='orm':
            assert all(rgba.getchannel(ch).getextrema()==(255,255)for ch in 'RBA')
            info['orm_policy']='Only G roughness has varying content; R/B/A remain exactly 255; metallicFactor unchanged at 0'
        destination=Image.merge('RGBA',channels)
        stream=io.BytesIO();destination.save(stream,format='PNG',compress_level=6,optimize=False)
        encoded=stream.getvalue()
        info['output_encoded_sha256']=sha(encoded)
        info['output_decoded_rgba_sha256']=sha(destination.tobytes())
        info['output_alpha_sha256']=sha(channels[3].tobytes())
        info['output_channel_ranges']=dict(zip('RGBA',destination.getextrema()))
    cache[key]=(encoded,info);return cache[key]

def non_image_recipe(j):
    result=copy.deepcopy(j)
    image_views={image['bufferView']for image in result['images']}
    result['buffers']=[{'byteLength':'image-dependent'}]
    for at,view in enumerate(result['bufferViews']):
        view.pop('byteOffset',None)
        if at in image_views:view['byteLength']='image-dependent'
    return result

def build(row,profile):
    path=Path(row['candidate']);source=exact.Glb(path);j=source.j
    source_sha=exact.digest(path);assert source_sha==row['candidate_sha256']
    roles={};cutoffs={}
    for material in j['materials']:
        pbr=material.get('pbrMetallicRoughness',{})
        for slot,role in [(pbr.get('baseColorTexture'),'albedo'),(pbr.get('metallicRoughnessTexture'),'orm'),(material.get('normalTexture'),'normal')]:
            if slot is None:continue
            index=j['textures'][slot['index']]['source']
            assert index not in roles or roles[index]==role
            roles[index]=role
            if role=='albedo':cutoffs[index]=material.get('alphaCutoff',.5)
    assert len(roles)==len(j['images'])==3
    view_replacements={};image_profiles=[]
    for at,image in enumerate(j['images']):
        encoded,info=transformed(source.blob(image['bufferView']),roles[at],profile,cutoffs.get(at,.5))
        view_replacements[image['bufferView']]=encoded
        image_profiles.append({'image':at,'name':image.get('name'),**info})
    revised=copy.deepcopy(j);binary=bytearray()
    for at,view in enumerate(revised['bufferViews']):
        raw=view_replacements.get(at)
        if raw is None:raw=source.blob(at)
        binary.extend(b'\0'*((-len(binary))%4));view['byteOffset']=len(binary);view['byteLength']=len(raw);binary.extend(raw)
    revised['buffers']=[{'byteLength':len(binary)}]
    encoded=json.dumps(revised,separators=(',',':'),ensure_ascii=False).encode('utf8');encoded+=b' '*((-len(encoded))%4)
    binary.extend(b'\0'*((-len(binary))%4))
    destination=path.parent/(row['asset']+'_'+profile+'.glb')
    with destination.open('wb')as file:
        file.write(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary)))
        file.write(struct.pack('<II',len(encoded),0x4e4f534a));file.write(encoded)
        file.write(struct.pack('<II',len(binary),0x004e4942));file.write(binary)
    check=exact.Glb(destination)
    assert non_image_recipe(j)==non_image_recipe(check.j),'Non-image GLB recipe changed'
    image_views=set(view_replacements)
    preserved=[]
    for at in range(len(j['bufferViews'])):
        if at in image_views:continue
        assert source.blob(at)==check.blob(at),'Non-image byte change'
        preserved.append({'view':at,'bytes':len(source.blob(at)),'sha256':sha(source.blob(at))})
    for at,recipe in enumerate(image_profiles):
        actual=check.blob(check.j['images'][at]['bufferView'])
        assert sha(actual)==recipe['output_encoded_sha256']
    assert exact.digest(path)==source_sha
    report={'asset':row['asset'],'profile':profile,'source_lossless':str(path),'source_lossless_sha256':source_sha,
        'original_master':row['source'],'original_master_sha256':row['source_sha256'],'output':str(destination),
        'output_sha256':exact.digest(destination),'source_bytes':path.stat().st_size,'output_bytes':destination.stat().st_size,
        'images':image_profiles,'non_image_buffer_views':preserved,
        'exact_non_image_json_equal':True,'all_non_image_bytes_equal':True,'geometry_nodes_extras_materials_samplers_equal':True,
        'wind_alpha_mode_cutoff_backlight_lod_shadow_semantics_preserved':True,
        'source_unchanged':True,'status':'unpublished 2K candidate; parent GPU/native validation pending'}
    source.close();check.close()
    (destination.with_suffix('.texture_profile.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:report[k]for k in ['asset','profile','output_bytes','output_sha256']}),flush=True)
    return report

def main():
    data=json.loads((OUT/'foliage_manifest.json').read_text(encoding='utf8'))
    results=[build(row,profile)for row in data['assets']for profile in ['pbr2k_albedo4k','all2k_coverage']]
    report={'scope':'Eight unpublished texture-only candidates; source master and exact lossless derivatives preserved; no GPU test',
            'profiles':['pbr2k_albedo4k','all2k_coverage'],'assets':results}
    (OUT/'foliage_2k_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    (REVIEW/'foliage_2k_profiles.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':main()
