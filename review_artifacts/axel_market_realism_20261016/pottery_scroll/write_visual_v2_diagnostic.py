import json,hashlib
from pathlib import Path
root=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/gpu_realism_v2_01')
out=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/visual_v2_diagnostic.json')
seen={'pottery':['goods_detail','goods_raking','near','cloth_detail','cloth_raking'],'scroll':['goods_detail','goods_raking','near','cloth_detail']}
candidate={'pottery':'e7b52bbc50582b3e3add326ca2ba09bdc820169c2422c549335c9c74feb34ca0','scroll':'93f4442914c646cc3601e7affc98fc499b0112658e3739ca259783d23520f61f'}
report={'version':1,'status':'DIAGNOSTIC_ONLY_REJECTED_UV_PIPELINE','visual_accepted':False,'gpu_started_by_reviewer':False,'formal_writes':False,'assets':{}}
for asset,views in seen.items():
 receipts=json.loads((root/asset/'image_upload_receipts.json').read_text());shots=[]
 for case in ['baseline','candidate']:
  for view in views:
   path=root/asset/case/(view+'.webp');row=next(r for r in receipts if Path(r['path'])==path)
   assert row['quality']==90 and row['lossless'] is False and row['dimensions']==[1400,1000]
   assert hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256']
   shots.append({'case':case,'view':view,'path':str(path),'sha256':row['sha256'],'dimensions':row['dimensions'],'quality':90,'lossless':False,'actually_viewed':True})
 report['assets'][asset]={'candidate_sha256':candidate[asset],'visual_accepted':False,'viewed_images':shots,'runtime_report_sha256':hashlib.sha256((root/asset/'candidate.json').read_bytes()).hexdigest()}
report['assets']['pottery']['findings']=[
 {'status':'visible_improvement','scope':'geometry','detail':'Shoulder and circular mouth silhouettes are smoother; open rims/interior remain visible; seven jars rest on the counter. Current sampling is adequate in these views.'},
 {'status':'provisional_visible_improvement','scope':'material','detail':'Four matte clay bodies and three localized honey/green/brown glaze regions are distinguishable; no whole-body plastic varnish. Material acceptance awaits UV0 pipeline correction.'},
 {'status':'needs_final_verification','scope':'cloth','detail':'Large cloth tension folds read under raking illumination. Fine weave is not independently discernible at these pixels; do not claim readable fiber detail solely from channel checks.'}]
report['assets']['scroll']['findings']=[
 {'status':'visible_improvement','scope':'geometry','detail':'Nine thinner rolls are supported on the counter; fine ties replace bulky red rings; flat ink relief and coarse black spirals are removed; open sheet has a thin mildly curled edge.'},
 {'status':'not_passed','scope':'ink','detail':'Normal goods view reads almost as a blank sheet; raking view has faint mottling but no clear quill-stroke pattern. First resolve actual sampled UV, then inspect again without increasing arbitrary emission/contrast.'},
 {'status':'needs_final_verification','scope':'roll_ends','detail':'Roll ends show speckling and tubular hollows. Do not finalize paper material/edge quality until UV0 fixed; do not add thick black spirals to hide it.'}]
report['pipeline_findings']=[{'status':'failed','detail':'Exported materials sample texCoord1 and scroll Structure texCoord2. Current actual-material proof verifies channel pixels but not chosen UV data. Root confirmed unreliable native consumption and is producing immutable v3 normalized UV0 candidates. v2 remains diagnostic, never accepted.'}]
report['not_viewed_or_claimed']=['medium/far/back/structure_detail for either candidate in this diagnostic pass','scroll cloth_raking','animation or temporal stability','formal publication','v3 or later appearance']
out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(str(out));print(hashlib.sha256(out.read_bytes()).hexdigest())
