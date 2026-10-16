"""Summarize accepted realism publication and real HTTP evidence; no model/map writes.

Requires root-owned visual acceptance and separately viewed final production
thumbnails. Catalog validation uses the four current entry identities, allowing
unrelated assets to be added after publication. All old reports remain untouched.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

RUNTIME = Path('D:/code/rmmo_runtime')
ART = RUNTIME / 'art_sources/axel_market_realism_20261016'
REVIEW = RUNTIME / 'review_artifacts/axel_market_realism_20261016'
FORMAL = RUNTIME / 'packs/default/assets'
IDS = {'pottery', 'scroll', 'potion', 'ore'}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identity(path):
    path = Path(path)
    return {'path': path.as_posix(), 'sha256': sha(path), 'bytes': path.stat().st_size}


def require(value, message):
    if not value:
        raise ValueError(message)


def canonical(value):
    path = Path(value)
    return path.resolve() if path.is_absolute() else (FORMAL / path).resolve()


def expanded_entry(value):
    """Match AssetLibrary's relative-on-disk, absolute-in-memory path contract."""
    result = dict(value)
    for key in ('asset_path', 'prefab_path', 'thumbnail_path'):
        if isinstance(result.get(key), str):
            result[key] = canonical(result[key]).as_posix()
    return result


def frozen_write(path, value):
    if path.exists():
        require(read(path) == value, 'Existing delivery evidence differs; preserve and use a new output name')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publication-take', required=True)
    parser.add_argument('--http-take', required=True)
    args = parser.parse_args()
    for value in (args.publication_take, args.http_take):
        require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value), 'Simple take identifiers required')
    pub_path = REVIEW / 'publication' / args.publication_take / 'publication.json'
    pub_runner_path = pub_path.with_name('runner_result.json')
    http_path = REVIEW / 'formal_http' / args.http_take / 'editor_verification.json'
    http_runner_path = http_path.with_name('runner_result.json')
    thumbs_accept_path = http_path.with_name('thumbnail_visual_acceptance.json')
    publication, pub_runner, http, runner = map(read, (pub_path, pub_runner_path, http_path, http_runner_path))
    require(publication.get('ok') and publication.get('catalog_committed') and publication.get('status') == 'published_maps_unchanged', 'Completed immutable publication required')
    require(pub_runner.get('passed') and pub_runner.get('engine_error_free') and pub_runner.get('returncode') == 0, 'Publication runner must pass without engine errors')
    require(http.get('passed') and http.get('completed') and http.get('failures') == 0 and http.get('verified_count') == 4, 'Four completed real HTTP items required')
    require(runner.get('passed') and runner.get('engine_error_free') and runner.get('returncode') == 0 and runner.get('thumbnail_repair_passed'), 'HTTP engine and real thumbnail generation must pass')
    require(runner.get('report_sha256') == sha(http_path), 'HTTP wrapper report SHA mismatch')
    require(http['formal_map_files_before'] == http['formal_map_files_after'], 'Formal map guard changed')
    require(http['catalog_sha_before'] == http['catalog_sha_after'], 'HTTP modified catalog')
    plan_path = Path(publication['plan_path'])
    require(plan_path.resolve().is_relative_to(ART.resolve()) and sha(plan_path) == publication['plan_sha256'], 'Publication plan is not source-bound')
    plan = read(plan_path)
    accepted_path = REVIEW / publication['review_take'] / 'acceptance.json'
    accepted, thumb_accept = read(accepted_path), read(thumbs_accept_path)
    require(accepted.get('visual_accepted') and accepted.get('intentional_visual_change'), 'Human realism acceptance required')
    require(thumb_accept.get('visual_accepted'), 'Final production thumbnail viewing required')
    require(set(accepted['assets']) == IDS and set(thumb_accept['assets']) == IDS, 'Acceptance must identify four assets exactly')
    require(len(publication['mapping']) == 4 and {m['asset'] for m in publication['mapping']} == IDS, 'Four unique publication mappings required')
    catalog = read(FORMAL / 'library.json')
    helper_path = Path(plan['preview_recipe']['path'])
    require(sha(helper_path) == plan['preview_recipe']['sha256'], 'Preview recipe changed after accepted evidence')
    require(http['thumbnail_repair']['environment_helper_sha256'] == plan['preview_recipe']['sha256'], 'HTTP used another preview recipe')
    source_rows = {row['asset']: row for row in plan['rows']}
    evidence_rows = {row['asset']: row for row in publication['acceptance_asset_evidence']}
    textures = {'baseline': {}, 'candidate': {}}
    output, catalog_projection = [], []
    for mapping in publication['mapping']:
        asset = mapping['asset']
        source, evidence = source_rows[asset], evidence_rows[asset]
        a, b, comparison = map(read, (evidence['baseline_report'], evidence['candidate_report'], evidence['comparison_report']))
        require(a['passed'] and b['passed'] and comparison['passed'], asset + ' failed runtime evidence')
        require(sha(evidence['comparison_report']) == accepted['assets'][asset]['compare_sha256'], asset + ' comparison SHA changed')
        require(sha(mapping['new_glb']) == source['candidate_sha256'] == mapping['candidate_sha256'] == accepted['assets'][asset]['candidate_sha256'], asset + ' new source identity changed')
        require(sha(mapping['new_asset_id']) == mapping['prefab_sha256'], asset + ' prefab changed')
        require(sha(mapping['old_glb']) == source['source_sha256'] and sha(mapping['old_asset_id']) == source['existing_prefab']['prefab_sha256'], asset + ' old source/prefab not retained')
        old_prefab, new_prefab = read(mapping['old_asset_id']), read(mapping['new_asset_id'])
        new_prefab['records'][0]['asset_path'] = old_prefab['records'][0]['asset_path']
        require(new_prefab == old_prefab, asset + ' prefab fields changed beyond source asset path')
        hits = [(i, e) for i, e in enumerate(catalog) if canonical(e.get('prefab_path', '')) == canonical(mapping['new_asset_id'])]
        require(len(hits) == 1, asset + ' formal catalog is missing or duplicated')
        require(not any(canonical(e.get('prefab_path', '')) == canonical(mapping['old_asset_id']) for e in catalog), asset + ' old entry still consumable in catalog')
        require(expanded_entry(hits[0][1]) == expanded_entry(mapping['entry']), asset + ' formal catalog fields changed')
        catalog_projection.append({'asset': asset, 'slot': hits[0][0], 'entry': hits[0][1]})
        native = mapping['formal_native_identity']
        require(sha(native['product']) == native['payload_sha'] and Path(native['product']).stat().st_size == native['bytes'], asset + ' formal native payload changed')
        key = hashlib.sha256(mapping['new_glb'].encode()).hexdigest()
        footprint_path = RUNTIME / f'cache/world3d/compiled_assets_v1/footprints_v1/{key}.json'
        footprint = read(footprint_path)
        require(hashlib.sha256(footprint['body'].encode()).hexdigest() == footprint['sha256'], asset + ' footprint body hash mismatch')
        stats = json.loads(footprint['body'])
        require(stats['source_sha'] == source['candidate_sha256'] and stats['payload_sha'] == native['payload_sha'] and stats['generator'] == native['generator'], asset + ' footprint native/source/generator mismatch')
        h = next(item for item in http['items'] if item['id'] == asset)
        require(h['http_passed'] and all(h[phase]['valid'] for phase in ('native_before', 'native_redo', 'native_reopen')), asset + ' formal native owner verification failed')
        thumb = next(item for item in http['thumbnail_repair']['images'] if item['asset'] == asset)
        ta = thumb_accept['assets'][asset]
        require(sha(thumb['formal_path']) == thumb['after_sha256'] == ta['thumbnail_sha256'] and ta.get('visual_accepted') and ta['source_sha256'] == source['candidate_sha256'], asset + ' final thumbnail was not viewed at current source identity')
        for case in textures:
            expected = source['expected_materials'][case]
            for image in expected['images']:
                if image['index'] in expected['active_image_indices']:
                    image_key = (image['width'], image['height'], image['rgba8_sha256'])
                    textures[case][image_key] = image
        output.append({**mapping, 'catalog_current_slot': hits[0][0], 'old_source_bytes': source['source_bytes'], 'new_source_bytes': source['candidate_bytes'],
            'source_growth_bytes': source['candidate_bytes'] - source['source_bytes'], 'isolated_native_old_bytes': a['native']['native_bytes'], 'isolated_native_new_bytes': b['native']['native_bytes'],
            'formal_footprint': identity(footprint_path), 'formal_footprint_stats': stats['stats'],
            'active_source_image_budget': {case: {key: source['expected_materials'][case][key] for key in ('active_unique_rgba8_bytes', 'active_unique_rgba8_mip_budget_bytes', 'visible_lod0_triangle_instances', 'active_surface_instances')} for case in textures},
            'prepared_mesh_cost': b['prepared_mesh_cost'], 'formal_native_owner_after_reopen': h['native_reopen'], 'thumbnail': thumb,
            'review_evidence': {key: identity(evidence[key]) for key in ('baseline_report', 'candidate_report', 'comparison_report')},
            'status': {'resource': 'PASS', 'visual': 'PASS_SCOPED_HUMAN_ACCEPTANCE', 'runtime_native': 'PASS', 'formal_catalog_and_http': 'PASS', 'formal_map_deployment': 'NOT_PERFORMED_LAYOUT_OWNER'}})
    for master in publication['source_masters']:
        require(sha(master['file']) == master['sha256'], 'Preserved source master changed')
    image_totals = {case: {'unique_decoded_pixel_images': len(images), 'rgba8_bytes': sum(i['rgba8_bytes'] for i in images.values()), 'rgba8_all_mip_budget_bytes': sum(i['rgba8_mip_budget_bytes'] for i in images.values())} for case, images in textures.items()}
    result = {'version': 1, 'scope': 'Intentional realism refinement of four existing market prefabs. New immutable source/native/catalog assets; original map instances and all older sources remain untouched.',
        'status': {'resource': 'PASS', 'visual_scope': 'PASS_WITH_LISTED_REFINEMENTS', 'runtime_pipeline': 'PASS', 'formal_catalog': 'PASS', 'formal_http_and_thumbnails': 'PASS', 'formal_map_deployment': 'NOT_PERFORMED_LAYOUT_OWNER'},
        'visual_scope': accepted.get('scope', 'Scoped realism revision; not final-art approval'),
        'remaining_refinements': accepted['remaining_refinements'],
        'performance_followups': accepted.get('performance_followups', []),
        'supplemental_visual_evidence': accepted.get('supplemental_evidence', []),
        'publication': identity(pub_path), 'publication_runner': identity(pub_runner_path), 'formal_http': identity(http_path), 'formal_http_runner': identity(http_runner_path), 'visual_acceptance': identity(accepted_path), 'thumbnail_visual_acceptance': identity(thumbs_accept_path),
        'formal_http_checks': len(http['checks']), 'formal_http_failures': 0, 'formal_map_files_guarded': len(http['formal_map_files_before']), 'formal_map_modified': False,
        'formal_catalog_at_audit': identity(FORMAL / 'library.json'), 'catalog_projection': catalog_projection, 'catalog_projection_sha256': hashlib.sha256(json.dumps(catalog_projection, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'source_totals': {'old_bytes': sum(r['old_source_bytes'] for r in output), 'new_bytes': sum(r['new_source_bytes'] for r in output)},
        'native_totals': {'isolated_old_bytes': sum(r['isolated_native_old_bytes'] for r in output), 'isolated_new_bytes': sum(r['isolated_native_new_bytes'] for r in output), 'formal_new_bytes': sum(r['formal_native_identity']['bytes'] for r in output)},
        'image_budgets_deduplicated_by_dimensions_and_decoded_sha': image_totals,
        'cost_limits': 'Image RGBA8/mip totals are budgets, not measured RSS or VRAM. Equal pixels across separate native resources do not prove automatic GPU deduplication. Formal native and per-model stats are recorded separately. Actual prepared renderer LOD arrays are retained; no inferred LOD savings.',
        'source_masters': publication['source_masters'], 'preview_recipe': identity(helper_path), 'mapping': output,
        'historical_candidates': 'v1-v5 and all prior review/publication reports retained. v2 UV/native incompatibility, v3 ink/inclusions, actual exported Trim triangle intersections and scroll cut-end smoothing were repaired. Current v6 exact-source evidence supersedes only those affected scopes.'}
    delivery_path = ART / 'delivery.json'
    frozen_write(delivery_path, result)
    frozen_write(REVIEW / 'delivery_status.json', {'status': 'formal_catalog_http_and_thumbnail_review_complete', 'delivery': identity(delivery_path), 'publication': identity(pub_path), 'formal_http': identity(http_path), 'formal_map_modified': False})
    print(json.dumps({'delivery': identity(delivery_path), 'formal_http_checks': len(http['checks']), 'source_totals': result['source_totals'], 'native_totals': result['native_totals']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
