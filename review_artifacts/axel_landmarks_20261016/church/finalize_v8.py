"""Record completed v8 targeted visual acceptance and publish the candidate handoff metadata only."""
import json
from pathlib import Path
ROOT=Path('D:/code/rmmo');REVIEW=ROOT/'review_artifacts/axel_landmarks_20261016/church'
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church')
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def put(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=REVIEW/'v8/gpu/report.json';r=read(p)
assert r['physics_completed'] and r['engine_error_free'] and not r['failures']
assert len(r['screenshots'])==6
r['pipeline_passed']=True;r['visual_accepted']=True;r['passed']=True
r['image_review_status']='actual_all_6_targeted_images_viewed_plus_22_v7_unchanged_structure_views'
r['visual_review']={
 'reviewer':'blender_church; root independently checked glass_inside and portal_closed',
 'viewed':[{'name':s['name'],'sha256':s['sha256']} for s in r['screenshots']],
 'notes':['Green/cyan panes and violet border now distinct against sky without opaque diffuse backing or emission.',
          'Front view still reveals internal timber/rooms; complete round-arched windows retained.',
          'Night glass stays dark naturally; lamp diamond facets remain visible.',
          'All six current Q90 images actually viewed. The prior 22-image v7 set supplies unchanged geometry/non-glass evidence under same sky/camera/exposure.'],
 'reuse_evidence':str(REVIEW/'v7_v8_palette_identity.json'),
 'unchanged_structure_report':str(REVIEW/'v7/gpu/report.json'),
 'limitation':'Formal editor HTTP/resource identity and capsule results remain in the unified review; candidate acceptance is not formal map deployment.'}
r['lod_decision']='No additional simplification LOD for this low-frequency single landmark; see ../lod_decisions.json for actual near/mid/far counters and conservative screen projection. Reassess only on repeated instances or formal-map profile bottlenecks.'
put(p,r)
m_path=BASE/'v8/manifest.json';m=read(m_path)
m['semantics_status']='Generic rmmo_model_components/rmmo_part/rmmo_building and stable UUID consumed and native roundtrip verified; real hinged colliders verified.'
m['review']={'resource':'PASS: source CPU207/0 and actual native footprint',
             'visual':'PASS: all6 targeted v8 Q90 images plus all22 unchanged-geometry v7 images, parent accepted palette',
             'pipeline':'PASS_NATIVE_ROUNDTRIP; final editor HTTP identity pending unified review',
             'formal_library':'NOT_PUBLISHED','formal_map':'NOT_IN_SCOPE',
             'report':str(p),'source_cpu':str(REVIEW/'v8/source_geometry_semantic_checks.json')}
m['native_review']=r['compiled_manifest'];m['native_cost']=r['footprint']['stats']
m['optimization']='No extra destructive decimation/standalone LOD now: single low-frequency landmark, 74902 source tris. Measured near/mid/far in v7 geometry-identical set; preserves real openings, floors, tower stairs and moving doors. Reassess on formal-map geometry bottleneck or repeated instances; shared PBR and surfaces remain independent costs.'
put(m_path,m)
d=read(BASE/'design.json');d['status']='candidate_v8_visual_native_accepted_final_editor_http_pending';d['source']=m['source'];d['bounds_actual']=m['bounds']
d['formal_import_status']='NOT_PUBLISHED; v8 native accepted, final editor HTTP identity pending unified review'
d['review']=m['review'];d['complete_glazing_only']=True;put(BASE/'design.json',d)
put(BASE/'latest_candidate.json',{'version':'v8','path':m['source']['glb'],'sha256':m['source']['sha256'],'manifest':str(m_path),'status':d['status'],'source':m['source'],'bounds':m['bounds'],'review':m['review']})
old=REVIEW/'v5/gpu/report.json'
if old.exists():
    o=read(old);o['passed']=False;o['visual_accepted']=False;o['superseded_by']='v8';o['image_review_status']='partial_actual_visual_review; superseded before all22 images inspected';o['visual_rejection']='Pointed arch shape and flat overbright diamond fixed in v7; weak glass palette fixed v8.';put(old,o)
print('Church v8 source/design/latest/manifest and actual visual report synchronized; no catalog or map changed.')
