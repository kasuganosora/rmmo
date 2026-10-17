"""Read-only final GLB audit and per-model identity/cost data."""
import json,struct,hashlib,io,math
from pathlib import Path
from PIL import Image
import numpy as np
ART=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013')
DEST=Path('D:/code/rmmo_runtime/review_artifacts/required_street_assets_20261013')
def sha(b):return hashlib.sha256(b).hexdigest()
def glb(p):
    b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0]
    return json.loads(b[20:20+n]),b[28+n:]
def accessor(d,b,i):
    a=d['accessors'][i];v=d['bufferViews'][a['bufferView']]
    dt={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
    k={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];start=v.get('byteOffset',0)+a.get('byteOffset',0)
    stride=v.get('byteStride',np.dtype(dt).itemsize*k)
    return np.ndarray((a['count'],k),dtype=dt,buffer=b,offset=start,strides=(stride,np.dtype(dt).itemsize)).copy()

def main():
    manifest=json.loads((ART/'manifest.json').read_text(encoding='utf-8'));rows=[];global_images={}
    for row in manifest['assets']:
        p=Path(row['path']);d,b=glb(p);errors=[];images=[];tris=0
        if sha(p.read_bytes())!=row['sha256']:errors.append('source SHA changed')
        for im in d.get('images',[]):
            v=d['bufferViews'][im['bufferView']];data=b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
            pic=Image.open(io.BytesIO(data));w,h=pic.size
            meta={'name':im.get('name'),'sha256':sha(data),'pixel_rgba_sha':sha(pic.convert('RGBA').tobytes()),'width':w,'height':h,'encoded_bytes':len(data),'decoded_rgba_bytes':w*h*4,'rgba_full_mips_budget':sum(max(1,w>>i)*max(1,h>>i)*4 for i in range(int(math.log2(max(w,h)))+1))}
            images.append(meta);global_images[meta['sha256']]=meta
        geometries=[]
        for m in d.get('meshes',[]):
            t=0
            for prim in m['primitives']:
                t+=d['accessors'][prim['indices']]['count']//3
                a=prim['attributes']
                for name in ['POSITION','NORMAL','TEXCOORD_0']:
                    if name not in a:errors.append('missing '+name);continue
                    values=accessor(d,b,a[name])
                    if not np.all(np.isfinite(values)):errors.append('nonfinite '+name)
            tris+=t;geometries.append({'name':m.get('name'),'triangles':t,'surfaces':len(m['primitives'])})
        nodes=[];visible_ranges={}
        for n in d['nodes']:
            if 'camera' in n or 'KHR_lights_punctual' in n.get('extensions',{}):errors.append('unexpected scene camera/light')
            if 'mesh' not in n:continue
            e=n.get('extras',{});g=geometries[n['mesh']]
            entry={'name':n.get('name'),'mesh':n['mesh'],'triangles':g['triangles'],'collision':e.get('rmmo_collision'),'wind':e.get('rmmo_wind'),'lod':e.get('rmmo_visibility_range'),'component_id':e.get('component_id')};nodes.append(entry)
            if entry['collision'] not in ['walk','block','none']:errors.append('missing collision semantics')
        runtime=json.loads((DEST/row['id']/'report.json').read_text(encoding='utf-8'))
        review_current=runtime['identity']['sha256']==row['sha256']
        result={'id':row['id'],'sha256':row['sha256'],'source_bytes':p.stat().st_size,'mother':row['source_blend'],'mother_sha256':sha(Path(row['source_blend']).read_bytes()),'bounds':row['bounds_godot'],'stored_triangles':tris,'mesh_count':len(geometries),'material_count':len(d.get('materials',[])),'images':images,'nodes':nodes,'geometry_validation_errors':errors,'review_current':review_current,'native_bytes':runtime.get('native_bytes'),'native_sha':runtime.get('native_sha'),'footprint':runtime.get('footprint_stats'),'conservative_admission':runtime.get('conservative_estimate'),'generator':runtime['generator'],'measured_individual_rss_vram':None}
        rows.append(result)
    summary={'assets':rows,'unique_encoded_images':len(global_images),'unique_image_encoded_bytes':sum(v['encoded_bytes'] for v in global_images.values()),'shared_rgba_mips_budget':sum(v['rgba_full_mips_budget'] for v in global_images.values()),'budget_note':'Estimated texture budget only, not measured VRAM/RSS; cross-file byte identity alone does not prove runtime sharing.','production_map_modified':False}
    (DEST/'resource_audit.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps([{'id':r['id'],'tris':r['stored_triangles'],'errors':r['geometry_validation_errors'],'current':r['review_current']} for r in rows],indent=2))
if __name__=='__main__':main()
