"""Read-only trace analysis; writes only a separate audit report."""
import collections
import json
from pathlib import Path

ROOT = Path('D:/code/rmmo')
TRACE = Path('D:/code/rmmo_runtime/review_artifacts/loading_collision_none_warm_20261011.json')
SELECTION = ROOT / 'review_artifacts/house_audit_selection_20261011.json'
report = json.loads(TRACE.read_text(encoding='utf-8-sig'))
selection = json.loads(SELECTION.read_text(encoding='utf8'))
assert report['map_sha'] == selection['map_sha']
events = report['monitor']['trace']['events']
house_ids = {row['uuid'] for row in selection['house_rows']}
texture_keys = sorted({key for row in selection['house_rows'] for key in row['prefab_textures']})
texture_paths = {key.removesuffix('|flip_y') for key in texture_keys}
images = [event for event in events if event['label'] == 'texture.image' and event['details']['path'] in texture_paths]
uploads = [event for event in events if event['label'] == 'paint.texture.upload' and event['details']['path'] in texture_paths]

def stages(label):
    rows = [event for event in events if event['label'] == label and event.get('details', {}).get('uuid') in house_ids]
    top = []
    for event in sorted(rows, key=lambda value: value['duration_us'], reverse=True)[:6]:
        enclosed = [part for part in events if part['label'] in ('texture.image', 'paint.texture.upload', 'paint.material') and part['thread_id'] == event['thread_id'] and part['start_us'] >= event['start_us'] and part['end_us'] <= event['end_us']]
        top.append({'event': event, 'enclosed_texture_material_events': enclosed})
    return {'recorded_count': len(rows), 'recorded_sum_us': sum(event['duration_us'] for event in rows), 'top': top}

result = {
    'scope': 'Read-only source and historical trace audit. No engine launch, map/resource mutation, or production code edits.',
    'trace': str(TRACE), 'selection': str(SELECTION), 'map_sha': selection['map_sha'],
    'trace_limits': {'minimum_event_us': report['monitor']['trace']['minimum_event_us'], 'dropped': report['monitor']['trace']['dropped'], 'note': 'Recorded spans are elapsed wall time; nested or overlapping spans must not be added as CPU time. Filtered events omit sub-threshold calls. This historical trace is not a new complete-load baseline.'},
    'texture_observation': {
        'house_keys': texture_keys,
        'house_image_count': len(images),
        'image_threads': dict(collections.Counter(event['thread_id'] for event in images)),
        'per_path_counts': dict(collections.Counter(event['details']['path'] for event in images)),
        'image_spans_sum_us': sum(event['duration_us'] for event in images),
        'main_thread_image_count': sum(event['thread_id'] == 1 for event in images),
        'upload_calls': len(uploads), 'upload_call_sum_us': sum(event['duration_us'] for event in uploads),
        'upload_bytes': sum(event['details']['bytes'] for event in uploads),
        'note': '24 house texture keys each prepared once on workers. Upload call duration is CPU/driver submission time, not full GPU completion. No bridge-like missing-image fallback was observed for houses in this trace.'
    },
    'game_mesh': stages('game.mesh'), 'deferred_publication': stages('deferred.publication'),
    'findings': [
        {'status': 'confirmed shared code issue', 'claim': 'Deferred house preparation recomputes geometry hashes already derived by decode, and may prepare CPU arrays even when subsequent main-thread prefab publication hits an existing cached geometry.',
         'evidence': ['scripts/world3d/house_prefab.gd:104', 'scripts/world3d/house_prefab.gd:126', 'scripts/world3d/house_prefab.gd:134', 'scripts/world3d/house_prefab.gd:198', 'scripts/world3d/chunk_reference_preparation.gd:81', 'scripts/world3d/chunk_reference_preparation.gd:96'],
         'detail': 'decode stores immutable geometry_keys under the frozen SHA; prepare_cpu serializes and hashes every mesh again. Chunk task deduplicates SHA only inside its own prefab_cpu dictionary. Cross-group tasks do not share a charged prepared geometry packet. No per-house time saving is inferred from the stone bridge measurement.',
         'plan': 'Reuse sealed immutable geometry identity/data across group tasks with source-generation validation and explicit worker ownership/admission. Retain the final reference/source gate. Measure actual unique house keys and cold/warm CPU work, rather than multiplying bridge milliseconds.'},
        {'status': 'confirmed residency coverage gap, deliberate current limitation', 'claim': 'Buildings are not retired by ordinary model residency, so walking away and hiding them does not prove loaded house geometry/material/texture memory was released.',
         'evidence': ['scripts/world3d/asset_residency.gd:2', 'scripts/world3d/asset_residency.gd:26', 'scripts/world3d/asset_residency.gd:52', 'scripts/world3d/asset_residency.gd:88', 'scripts/world3d/stream_index.gd:144', 'scripts/world3d/stream_index.gd:198'],
         'detail': 'AssetResidency catalogue accepts only spatial rows with empty group_id, then explicitly pins building/house_prefab records; Stream retirement rejects grouped dependencies. Static LRU caps do not bound resources retained by live stream specs. This is not a proven per-frame leak.',
         'plan': 'Add complete-building ownership/leases for retirement, preserving occupied building support, floor cutaway, active doors/windows, collision/navigation and shared texture owners; verify far traversal, return visits and teleport before enabling.'},
        {'status': 'confirmed performance attribution gap and historical long calls', 'claim': 'House game.mesh timings do not reach the frozen house internals; existing trace sees 111 ms initial house work and 24 ms deferred publication without enough internal stages to attribute all cost.',
         'evidence': ['scripts/world3d/world_document.gd:388', 'scripts/world3d/world_document.gd:394', 'scripts/world3d/house_prefab.gd:277', 'scripts/world3d/deferred_asset_loader.gd:280', 'scripts/world3d/deferred_asset_loader.gd:1332', 'scripts/world3d/deferred_asset_loader.gd:1340'],
         'detail': 'world_document._mesh accepts timings but does not pass it to prefab.visual. Initial game.mesh parts_ms are empty. obj_200005 took 111.038 ms, including 63.282 ms castle_rubble texture upload calls. obj_330002 deferred publication took 24.031 ms, with prefab geometry cache hit and 23.775 ms instance creation. Deferred immutable-record mode disables GPU mesh restore in this path; that instance time must not be labelled GPU upload without further probes.',
         'plan': 'Carry existing timing dictionary through prefab.visual, separately record geometry, texture_error, metadata and any painted-mesh generation; then test phased upload or smaller publication units using actual longest stages.'},
        {'status': 'potential shared mechanism, not reproduced for current house trace', 'claim': 'A future deferred house with previously unused textures can synchronously load images on publication while prefab texture preparation remains disabled.',
         'evidence': ['scripts/world3d/deferred_asset_loader.gd:30', 'scripts/world3d/deferred_asset_loader.gd:33', 'scripts/world3d/deferred_asset_loader.gd:893', 'scripts/world3d/surface_materials.gd:237', 'scripts/world3d/surface_materials.gd:240'],
         'detail': 'The same fallback mechanism applies to frozen houses, but all 24 distinct current house texture keys were covered by initial preparation in the analysed trace. No proof of house texture LRU thrashing or per-building repeated decode was found.',
         'plan': 'Extend the shared texture closure/ownership solution planned for bridges to houses, and test a cold far-house texture family plus near-core shared images. Do not assume worker sharing permits skipping source validation.'}
    ],
    'excluded_claims': [
        'No evidence that every house imports an original source GLB: these selected building rows have empty asset_path and frozen data is used.',
        'No evidence that current house texture image decode repeats once per instance; each distinct key appears once on worker threads.',
        'No claim that all 503.793 ms recorded house mesh spans are texture decode or geometry hash, and no conversion of aggregate overlapping spans into entry-time savings.',
        'No claim that whole-house monolithic mesh merging is safe: preserve semantic floor/roof/ceiling/fixture boundaries.'
    ],
    'grok': 'Not rerun: established local managed-policy/auth startup failures were not bypassed. This report is independent source/trace review, not Grok output.'
}
output = ROOT / 'review_artifacts/house_loading_audit_20261011.json'
output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf8')
print(json.dumps({'output': str(output), 'house_textures': len(texture_keys), 'image_threads': result['texture_observation']['image_threads'], 'uploads_us': result['texture_observation']['upload_call_sum_us'], 'uploads_bytes': result['texture_observation']['upload_bytes'], 'game_mesh': {key: value for key,value in result['game_mesh'].items() if key != 'top'}, 'deferred_publication': {key: value for key,value in result['deferred_publication'].items() if key != 'top'}}, ensure_ascii=False))
