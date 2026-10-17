"""Millimetre design values for the entire building descriptor, not geometry."""
import copy,hashlib,json,struct
from pathlib import Path
base=Path('D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017');src=base/'v4/s10_court_shutter_house.glb';dst=base/'v5'/src.name
r=src.read_bytes();jl=struct.unpack_from('<I',r,12)[0];d=json.loads(r[20:20+jl]);original=copy.deepcopy(d);changes=[]
for ni,n in enumerate(d['nodes']):
    extra=n.get('extras',{})
    if 'rmmo_part' in extra:
        p=extra['rmmo_part'];old=p['floor_y'];p['floor_y']=round(old,3)
        if old!=p['floor_y']:changes.append({'node':ni,'field':'rmmo_part.floor_y','old':old,'new':p['floor_y']})
    for region in extra.get('rmmo_building',{}).get('regions',[]):
        for field in ['min','max']:
            for k,old in enumerate(region[field]):
                region[field][k]=round(old,3)
                if old!=region[field][k]:changes.append({'node':ni,'region':region['id'],'field':field,'axis':k,'old':old,'new':region[field][k]})
assert len(changes)==2 and all(x['old']==1.2999999999999998 and x['new']==1.3 for x in changes)
restore=copy.deepcopy(d)
for c in changes:
    rr=next(x for x in restore['nodes'][c['node']]['extras']['rmmo_building']['regions'] if x['id']==c['region']);rr[c['field']][c['axis']]=c['old']
assert restore==original
j=json.dumps(d,ensure_ascii=False,separators=(',',':')).encode();j+=b' '*((-len(j))%4);binary=r[20+jl:]
out=struct.pack('<III',0x46546c67,2,20+len(j)+len(binary))+struct.pack('<II',len(j),0x4e4f534a)+j+binary
assert not dst.exists();dst.parent.mkdir(parents=True);dst.write_bytes(out)
a=json.loads(src.with_name(src.stem+'_authoring.json').read_text(encoding='utf-8'));a.update(path=dst.as_posix(),sha256=hashlib.sha256(out).hexdigest(),source_bytes=len(out),region_revision={'source':src.as_posix(),'source_sha256':hashlib.sha256(r).hexdigest(),'changes':changes,'all_other_json_equal':True,'bin_chunk_sha256':hashlib.sha256(binary).hexdigest()})
dst.with_name(dst.stem+'_authoring.json').write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('S10_FINAL_SOURCE',a['sha256'])
