import json,hashlib
from pathlib import Path
TAKE=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016/gpu_realism_v3_01')
views=['near','medium','far','back','goods_detail','goods_raking','cloth_detail','cloth_raking','structure_detail']
seen={'pottery':{'baseline':views,'candidate':views},'scroll':{'baseline':['goods_detail','goods_raking'],'candidate':views}}
source={'pottery':'cdeb4d290ebf3c0cafd29c63640c84767f3ac35951ecec5fcdc0f1dec15c2e60','scroll':'335d18902a2dc877c9b36f30407fa27d6426d6b6dbec7c2794dd2bec9c5f7a9d'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
report={'version':1,'take':str(TAKE),'status':'CHANGES_REQUIRED','visual_accepted':False,'gpu_started_by_reviewer':False,'formal_writes':False,
        'same_environment_comparison':'Only v3 A/B pairs; both use the new frozen neutral reflection helper. No v2-to-v3 equal-light claim.',
        'assets':{}}
for asset,cases in seen.items():
    images=[]
    for case,view_names in cases.items():
        for view in view_names:
            p=TAKE/asset/case/(view+'.webp');r=json.loads(Path(str(p)+'.review-image.json').read_text())
            assert sha(p)==r['sha256'] and r['quality']==90 and not r['lossless'] and r['dimensions']==[1400,1000]
            images.append({'case':case,'view':view,'path':str(p),'sha256':r['sha256'],'quality':90,'lossless':False,'dimensions':r['dimensions'],'actually_viewed':True})
    report['assets'][asset]={'candidate_sha256':source[asset],'visual_accepted':False,'viewed_images':images,'runtime_report_sha256':sha(TAKE/asset/'candidate.json')}
report['assets']['pottery']['findings']=[
    {'scope':'GoodsOpaque','status':'accepted_in_inspected_views','detail':'All seven vessels remain supported. Smooth shoulders, thin rolled mouths, open interiors and four bare clay/three localized glaze treatments read correctly in near/detail/raking/back; no need for additional geometry based on these views. Near/mid/far retain the stall silhouette and merchandise identity.'},
    {'scope':'Structure','status':'accepted_in_inspected_views','detail':'Vertical grain on uprights and front boards is clear; side/back support connections remain intact.'},
    {'scope':'CanopyCloth','status':'micro_detail_not_verified','detail':'Broad cloth folds and restrained highlights are visible, but fine woven texture is not discernible at the submitted resolution. Main task explicitly leaves micro-fibre refinement outside this correction round; do not claim that microscopic detail was visually verified.'},
    {'scope':'CanopyTrim','status':'requires_fix','detail':'Back-view binding has dark broken streaks absent from the clean baseline. CPU follow-up confirmed real cloth intersections and mixed-facing ribbon triangles. v4_canopy_trim provides a geometry-only candidate; actual post-fix GPU review is still required.'}]
report['assets']['scroll']['findings']=[
    {'scope':'PaperSheet','status':'requires_fix','detail':'The sheet reads nearly blank in normal near/detail. CPU correlation shows ink was baked but too faint/subpixel. v4_scroll_sheet is an albedo-only delta with unchanged geometry/UV/normal/ORM; no visual acceptance yet.'},
    {'scope':'GoodsOpaque','status':'provisional_geometry_accepted','detail':'Nine thin rolled sheets and fine ties replace thick stylized bands and black spirals; normal view has adequate thin-roll silhouette. Raking view has end-layer dark speckles; concentrated lighting dependence suggests shadow interaction, but this remains a hypothesis pending render diagnosis. No geometry rebuild undertaken solely from those pixels.'},
    {'scope':'CanopyTrim','status':'requires_fix','detail':'Back-view broken binding streaks match pottery. Shared v4_canopy_trim candidate awaits actual rephotography.'},
    {'scope':'CanopyCloth','status':'micro_detail_not_verified','detail':'Broad folds visible; fine weave not independently readable. No claim of microscopic-fibre pass.'}]
report['limits']=['29 images actually viewed (18 pottery + 11 scroll). Other scroll baseline views not claimed.',
                  'No final v4/v5 appearance claimed from CPU proof.','No temporal shimmer/animation, publication, formal HTTP or full-map result claimed.']
OUT=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/visual_v3_review.json')
OUT.write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'path':str(OUT),'sha256':sha(OUT),'actual_images':sum(len(a['viewed_images']) for a in report['assets'].values())}))
