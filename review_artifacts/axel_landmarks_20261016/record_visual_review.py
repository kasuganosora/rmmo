"""Record explicitly completed human/model image inspections; never infer visual pass from renderer exit."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def update(asset, version, accepted, notes):
    path = ROOT / asset / version / 'gpu' / 'report.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    data['pipeline_passed'] = bool(data.get('physics_completed') and data.get('engine_error_free') and not data.get('failures'))
    data['visual_accepted'] = accepted
    data['passed'] = bool(accepted and data['pipeline_passed'])
    data['image_review_status'] = f"actual_all_{len(data['screenshots'])}_images_viewed"
    data['visual_review'] = {
        'reviewer': 'blender_church',
        'method': 'Every listed original-size lossy Q90 WebP viewed through view_image; compared to user references and previous rejected candidate.',
        'viewed': [{'name': s['name'], 'sha256': s['sha256']} for s in data['screenshots']],
        'notes': notes,
        'scope': 'Candidate geometry/material appearance and native roundtrip only. Real editor capsule traversal and formal publication remain separate.'
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

update('watermill', 'v10', True, [
    'All 17 images viewed. Neutral clear panes show interior and background; opaque milkiness removed.',
    'Roof and porch undersides now use timber boarding rather than exterior roof tiles.',
    'Warm brushed lime plaster no longer has marble-like coarse mottling; stone relief remains visible under grazing light.',
    'Waterwheel, bearing pier and perimeter foundation remain complete. Studio ground exposes foundation; final river terrain fit is a separate map check.',
])
update('church', 'v7', False, [
    'All 22 images viewed. Rounded arch outlines, complete glazing, explicit triangular dividers, deep door panels and magic-stone facet contrast now correct.',
    'Native meshes, active leaf colliders and aperture checks pass, but aperture rays are not capsule traversal.',
    'Root reinspection against C04 identified insufficient green/cyan pane separation against blue sky. Do not publish v7: palette-only v8 and targeted matching-camera review required.',
    'Night uses existing production lamps with low medieval interior illumination; glazing has no intrinsic emission.',
])

design_path = Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church/design.json')
manifest_path = design_path.parent / 'v7' / 'manifest.json'
design = json.loads(design_path.read_text(encoding='utf-8'))
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
design['status'] = 'candidate_v7_native_geometry_passed_palette_v8_pending'
design['source'] = manifest['source']
design['bounds_actual'] = manifest['bounds']
design['formal_import_status'] = 'NOT_PUBLISHED; editor HTTP capsule validation in progress, final palette v8 pending'
design['review'] = {
    'resource': 'CPU 207 checks passed; native compiled/read back with matching source and material identity',
    'visual': 'v7 structure accepted; green/cyan glass palette targeted v8 recheck pending',
    'physics': 'Native collider/hinge/aperture checks passed; actual editor capsule traversal separate',
    'report': str(ROOT / 'church/v7/gpu/report.json'),
}
design_path.write_text(json.dumps(design, ensure_ascii=False, indent=2), encoding='utf-8')
print('Recorded actual watermill v10 all-image acceptance and church v7 palette hold; design source synchronized to v7.')
