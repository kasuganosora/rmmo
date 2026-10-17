"""Read-only CPU resource/reference status for the isolated S10/S12 revision."""
import json,hashlib,io,math,sys
from pathlib import Path
import numpy as np
from PIL import Image
import audit_required_street_assets as common

ART=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2')
DEST=Path('D:/code/rmmo_runtime/review_artifacts/required_street_recheck_20261013')

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def surface_rows(doc,binary,word):
    rows=[]
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            if word not in doc['materials'][p['material']]['name'].lower():continue
            attrs=p['attributes'];data=np.concatenate([common.accessor(doc,binary,attrs['POSITION']),common.accessor(doc,binary,attrs['TEXCOORD_0'])],axis=1)
            index=common.accessor(doc,binary,p['indices']).ravel();data=np.round(data[index],6)
            rows.extend(tuple(float(v) for v in row) for row in data)
    return sorted(rows)

def main():
    manifest=json.loads((ART/'manifest.json').read_text(encoding='utf8'));rows=[];global_images={}
    for row in manifest['assets']:
        doc,binary=common.glb(Path(row['path']));issues=[];images=[];triangles=0;surfaces=0;uvs=[]
        if sha(row['path'])!=row['sha256']:issues.append('Candidate SHA differs from manifest')
        for im in doc.get('images',[]):
            bv=doc['bufferViews'][im['bufferView']];data=binary[bv.get('byteOffset',0):bv.get('byteOffset',0)+bv['byteLength']]
            image=Image.open(io.BytesIO(data));w,h=image.size;digest=hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()
            info={'name':im.get('name',''),'pixel_sha256':digest,'width':w,'height':h,'encoded_bytes':len(data),
                  'rgba8_bytes':w*h*4,'rgba8_mip_budget':sum(max(1,w>>i)*max(1,h>>i)*4 for i in range(int(math.log2(max(w,h)))+1))}
            images.append(info);global_images[digest]=info
        for mesh in doc.get('meshes',[]):
            for p in mesh['primitives']:
                surfaces+=1;triangles+=doc['accessors'][p['indices']]['count']//3
                for semantic in ['POSITION','NORMAL','TEXCOORD_0']:
                    if semantic not in p['attributes']:issues.append('Missing '+semantic);continue
                    values=common.accessor(doc,binary,p['attributes'][semantic])
                    if not np.isfinite(values).all():issues.append('Nonfinite '+semantic)
                uv=common.accessor(doc,binary,p['attributes']['TEXCOORD_0'])
                uvs.append({'material':doc['materials'][p['material']]['name'],'uv_span':(uv.max(axis=0)-uv.min(axis=0)).tolist()})
        nodes=[]
        for n in doc['nodes']:
            if 'mesh' not in n:continue
            e=n.get('extras',{});nodes.append({'name':n.get('name',''),'extras':e})
            if e.get('rmmo_collision') not in ['none','block','walk']:issues.append('Missing collision role '+n.get('name',''))
        if row['id'].startswith('s10_'):
            old=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/models')/(row['id']+'.glb')
            olddoc,oldbin=common.glb(old)
            same=surface_rows(doc,binary,'leaf')==surface_rows(olddoc,oldbin,'leaf')
            if not same:issues.append('Leaf atlas geometry/UV changed')
            for item in uvs:
                if 'fruit waxy' in item['material'].lower() and min(item['uv_span'])<.99:issues.append('Fruit skin UV still collapsed')
        else:same=None
        result={'id':row['id'],'sha256':row['sha256'],'baseline_sha256':row['baseline_sha256'],
                'source_bytes':Path(row['path']).stat().st_size,'source_mother':row['source_blend'],'mother_sha256':sha(row['source_blend']),
                'triangles_all_stored_lods':triangles,'surfaces_all_lods':surfaces,'images':images,'uv_spans':uvs,'nodes':nodes,
                'leaf_geometry_uv_exact_at_1e6':same,'issues':issues,
                'status':{'resource_audit':'pass' if not issues else 'fail','visual':'pending current-SHA native gallery','runtime':'pending native save/reopen and affected physical traversal','integration':'not published; temporary HTTP map pending'},
                'reference':'S10/S12 actual user images in docs/references/town_required_shots_20261012; unseen sculpture/installation dimensions are project designs',
                'optimisation':'Existing tree LOD/alpha/wind retained. Small stones/steps need no additional LOD. Arch/sculpture retain arris/foliate detail; no unvalidated decimation.',
                'measured_rss_vram':None}
        folder=DEST/row['id'];folder.mkdir(parents=True,exist_ok=True)
        (folder/'resource_review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');rows.append(result)
    total={'assets':rows,'shared_unique_decoded_rgba8_budget':sum(v['rgba8_bytes'] for v in global_images.values()),
           'shared_unique_rgba8_mip_budget':sum(v['rgba8_mip_budget'] for v in global_images.values()),
           'budget_note':'Conservative image estimate, not measured RSS/VRAM; pixel identity does not establish runtime cross-file sharing',
           'production_map_modified':False}
    (DEST/'resource_audit.json').write_text(json.dumps(total,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps([{'id':r['id'],'issues':r['issues'],'tris':r['triangles_all_stored_lods']} for r in rows]))
    if any(r['issues'] for r in rows):sys.exit(1)

if __name__=='__main__':main()
