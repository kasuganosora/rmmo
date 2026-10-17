"""Inspect the preserved guild whitebox without changing it."""
import bpy,json,hashlib
from pathlib import Path
ROOT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v12')
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_materials_20261011')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'axel_guild_whitebox.blend'))
rows=[]
for o in bpy.data.objects:
    if o.type!='MESH':continue
    rows.append({'name':o.name,'mesh':o.data.name,'parent':o.parent.name if o.parent else None,
        'group':o.get('semantic_group',''),'vertices':len(o.data.vertices),'polygons':len(o.data.polygons),
        'uv':len(o.data.uv_layers),'materials':[m.name if m else '' for m in o.data.materials],
        'properties':{k:str(o[k]) for k in o.keys()},'dimensions':list(o.dimensions)})
report={'source_sha256':hashlib.sha256((ROOT/'axel_guild_whitebox.blend').read_bytes()).hexdigest(),
        'objects':rows,'roots':[{'name':o.name,'properties':{k:str(o[k]) for k in o.keys()}} for o in bpy.data.objects if o.type=='EMPTY']}
(OUT/'readiness_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('READINESS_AUDIT',len(rows),'meshes;',sum(r['uv']==0 for r in rows),'without UV')
