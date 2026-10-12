"""Read actual GLB dependencies; build byte-preserving candidates only.

No renderer, image conversion, resizing, geometry rewrite, or source mutation.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
from collections import defaultdict
from pathlib import Path
from PIL import Image

REPO = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/foliage')
REVIEW = REPO / 'review_artifacts/town_asset_size_audit_20261011'
PREFIXES = {'47fd0e87':'shrub_spreading', 'afbfc8ac':'shrub_tall', 'ca8df548':'shrub_round', '06d99753':'foliage_boxwood'}
spec = importlib.util.spec_from_file_location('exact_compactor', REPO / 'tools/optimize_bridge_pennant_glb.py')
exact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exact)
pixel_cache = {}

def sha(raw): return hashlib.sha256(raw).hexdigest()

def pixel_info(raw):
    encoded_sha = sha(raw)
    if encoded_sha in pixel_cache: return pixel_cache[encoded_sha]
    with Image.open(io.BytesIO(raw)) as img:
        img.load()
        rgba = img.convert('RGBA')
        channels = rgba.split()
        alpha = channels[3].histogram()
        info = {'dimensions':list(img.size), 'mode':img.mode,
                'decoded_rgba_sha256':sha(rgba.tobytes()),
                'channel_ranges':dict(zip('RGBA', rgba.getextrema())),
                'channel_sha256':{name:sha(ch.tobytes()) for name,ch in zip('RGBA',channels)},
                'alpha_zero_pixels':alpha[0], 'alpha_opaque_pixels':alpha[255],
                'alpha_fractional_pixels':sum(alpha[1:255]),
                'alpha_mask_045_coverage':sum(alpha[115:])/sum(alpha),
                'pixel_count':sum(alpha)}
    pixel_cache[encoded_sha] = info
    return info

def slots(material, path=''):
    if isinstance(material,dict):
        for key,value in material.items():
            current=path+'.'+key if path else key
            if key.endswith('Texture') and isinstance(value,dict) and 'index' in value:
                yield current,value
            else: yield from slots(value,current)
    elif isinstance(material,list):
        for at,value in enumerate(material): yield from slots(value,path+f'[{at}]')

def audit(row):
    source=Path(row['path']);prefix=source.stem[:8];name=PREFIXES[prefix]
    original_sha=exact.digest(source)
    assert original_sha==row['source_sha256']
    glb=exact.Glb(source);j=glb.j
    used_materials={p['material'] for m in j['meshes'] for p in m['primitives'] if 'material' in p}
    usages=defaultdict(list)
    for mat_index in sorted(used_materials):
        for path,slot in slots(j['materials'][mat_index]):
            tex=j['textures'][slot['index']]
            usages[tex['source']].append({'material':mat_index,'slot':path,'texture':slot['index'],'sampler':tex.get('sampler'),'slot_recipe':slot})
    images=[]
    for at,image in enumerate(j['images']):
        raw=glb.blob(image['bufferView'])
        images.append({'index':at,'name':image.get('name'), 'encoded_bytes':len(raw), 'encoded_sha256':sha(raw),
                       'reachable_from_used_materials':at in usages,'usages':usages.get(at,[]),**pixel_info(raw)})
    duplicate_encoded=defaultdict(list);duplicate_pixels=defaultdict(list)
    for image in images:
        duplicate_encoded[image['encoded_sha256']].append(image['index'])
        duplicate_pixels[image['decoded_rgba_sha256']].append(image['index'])
    geometry=[]
    for at,mesh in enumerate(j['meshes']):
        geometry.append({'mesh':at,'name':mesh.get('name'),'materials':[p.get('material')for p in mesh['primitives']],
                         'triangles':sum(j['accessors'][p['indices']]['count']//3 for p in mesh['primitives'])})
    # Existing audited compactor rejects unfamiliar extension/animation graphs,
    # preserves nodes/scenes/meshes, and verifies all dependency bytes resolved.
    dest_dir=OUT/name
    exact.SOURCE=source;exact.OUT=dest_dir;exact.EXPECTED_SOURCE_SHA=original_sha
    captured=io.StringIO()
    with contextlib.redirect_stdout(captured): exact.run()
    candidate=dest_dir/(name+'_lossless.glb')
    temporary=dest_dir/'bridge_long_pennants_lossless.glb'
    if candidate.exists():
        assert exact.digest(candidate)==exact.digest(temporary),'Unexpected previous candidate'
        temporary.unlink()
    else: temporary.rename(candidate)
    clean=json.loads((dest_dir/'lossless_audit.json').read_text())
    clean['output']=str(candidate)
    (dest_dir/'lossless_audit.json').write_text(json.dumps(clean,ensure_ascii=False,indent=2),encoding='utf-8')
    assert exact.digest(source)==original_sha
    output={'asset':name,'source':str(source),'source_sha256':original_sha,'candidate':str(candidate),'candidate_sha256':exact.digest(candidate),
            'original_size':source.stat().st_size,'candidate_size':candidate.stat().st_size,
            'original_tables':{key:len(j.get(key,[]))for key in ['nodes','scenes','meshes','materials','textures','images','accessors','bufferViews']},
            'used_material_indices':sorted(used_materials),'used_image_indices':sorted(usages),
            'unused_image_indices':[at for at in range(len(images)) if at not in usages],
            'duplicate_encoded_groups':[x for x in duplicate_encoded.values() if len(x)>1],
            'duplicate_decoded_groups':[x for x in duplicate_pixels.values() if len(x)>1],
            'materials':j['materials'],'images':images,'geometry':geometry,'nodes':j['nodes'],
            'samplers':j.get('samplers',[]),'native_footprint_from_handoff':row['footprint_stats'],
            'lossless_cleanup':clean,'original_unchanged':True,'gpu_validation':'not run; parent-owned gate'}
    glb.close()
    return output

def main():
    rows=json.loads((REPO/'review_artifacts/town_large_asset_art_handoff_20261011.json').read_text(encoding='utf-8'))['rows']
    results=[]
    for row in rows:
        if Path(row['path']).stem[:8] not in PREFIXES:continue
        result=audit(row);results.append(result)
        print(json.dumps({'asset':result['asset'],'source_bytes':result['original_size'],'candidate_bytes':result['candidate_size'],'used_images':result['used_image_indices'],'sha':result['candidate_sha256']}),flush=True)
    sharing=defaultdict(list)
    for result in results:
        for image in result['images']:
            if not image['reachable_from_used_materials']:continue
            sharing[image['decoded_rgba_sha256']].append({'asset':result['asset'],'image':image['index'],'encoded_sha256':image['encoded_sha256'],'channel_sha256':image['channel_sha256'],'usages':image['usages']})
    report={'scope':'Source-only exact dependency compaction; no image or geometry edits, no game publication.',
            'assets':results,'cross_asset_identical_active_images':[group for group in sharing.values() if len(group)>1],
            'total_source_bytes':sum(r['original_size']for r in results),'total_candidate_bytes':sum(r['candidate_size']for r in results)}
    (REVIEW/'foliage_asset_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'foliage_manifest.json').write_text(json.dumps({'status':'lossless candidates; pending parent visual/native validation; unpublished',
         'assets':[{k:r[k]for k in ['asset','source','source_sha256','candidate','candidate_sha256','original_size','candidate_size']}for r in results]},ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':main()
