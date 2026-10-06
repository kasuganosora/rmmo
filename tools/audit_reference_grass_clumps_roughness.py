import bpy,hashlib,struct,json
from pathlib import Path
ROOT=Path('D:/code/rmmo_runtime')
def audit(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));h=hashlib.sha256();links=[]
 for o in sorted(bpy.data.objects,key=lambda o:o.name):
  if o.type!='MESH':continue
  h.update(o.name.encode())
  for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
 for mat in bpy.data.materials:
  if not mat.use_nodes:continue
  for p in mat.node_tree.nodes:
   if p.type=='BSDF_PRINCIPLED' and p.inputs['Roughness'].is_linked:
    link=p.inputs['Roughness'].links[0];links.append({'material':mat.name,'node':link.from_node.type,'channel':link.from_socket.name})
 return {'path':str(path),'geometry_sha256':h.hexdigest(),'roughness_links':links}
rows=[]
for family,path in [('reference_grass_clumps',ROOT/'art_sources/reference_grass_clumps/reference_grass_clumps.blend'),('town_grass',ROOT/'art_sources/bridge_street_kit/town_grass/town_grass_masters.blend')]:
 original=audit(path.with_name(path.stem+'_before_roughness_fix.blend'));fixed=audit(path);assert original['geometry_sha256']==fixed['geometry_sha256'];assert all(l['channel']=='Red' for l in fixed['roughness_links']);rows.append({'family':family,'original':original,'repaired':fixed,'geometry_unchanged_from_original':True,'corrected_roughness_links':len(fixed['roughness_links'])})
(ROOT/'review_artifacts/reference_grass_clumps/roughness_fix.json').write_text(json.dumps(rows,indent=2),encoding='utf8');print('ORIGINAL_VS_REPAIRED_GEOMETRY_PASS',[(r['family'],r['corrected_roughness_links']) for r in rows])
