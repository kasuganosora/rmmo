"""Assemble verified independent candidates; never publish into map or cache."""
import hashlib
import json
from pathlib import Path

ROOT = Path('D:/code/rmmo')
ART = Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011')
REVIEW = ROOT / 'review_artifacts/town_asset_size_audit_20261011'
read = lambda p: json.loads(Path(p).read_text(encoding='utf8'))
sha = lambda p: hashlib.file_digest(Path(p).open('rb'), 'sha256').hexdigest()

def result(label, kind):
    folder = ART / 'review' / label
    a, b, comparison = [read(folder / (n + '.json')) for n in ['baseline', 'candidate', 'compare']]
    assert a['passed'] and b['passed'] and comparison['passed']
    assert comparison['nontexture_semantic_exact']
    assert sha(a['original']) == a['original_sha']
    assert sha(b['original']) == b['original_sha']
    if kind == 'lossless':
        assert comparison['semantic_exact'] and all(x['exact'] for x in comparison['images'])
    else:
        assert read(folder / 'shadows/compare.json')['passed']
    def costs(d):
        return {'source_bytes': d['source_bytes'], 'native_bytes': d['native']['native_bytes'],
                'native_stats': d['native']['stats'], 'full_peak_conservative_admission_bytes': d['native']['estimate']['estimated_bytes'],
                'compiled_generator': d['native']['footprint_candidate']['generator'],
                'wind_surface_count': d['wind_surface_count'],
                'render_counts_by_view': [{k: v for k, v in s.items() if k != 'pixels'} for s in d['screenshots']]}
    return {'label': label, 'kind': kind, 'original': a['original'], 'original_sha256': a['original_sha'],
            'candidate': b['original'], 'candidate_sha256': b['original_sha'],
            'baseline': costs(a), 'optimized': costs(b), 'review': str(folder / 'compare.json'),
            'shadows': str(folder / 'shadows/compare.json') if kind != 'lossless' else None,
            'nontexture_semantics_exact': True, 'pixel_exact': all(x['exact'] for x in comparison['images']),
            'art_status': 'isolated_review_passed', 'integration_status': 'pending_combined_game_editor_acceptance',
            'published': False}

def main():
    lossless = read(ART / 'architecture/architecture_lossless_summary.json') + read(ART / 'secondary/secondary_lossless_summary.json')
    labels = [r['label'] for r in lossless] + [r['asset'] for r in read(ART / 'foliage/foliage_manifest.json')['assets']]
    exact = [result(label, 'lossless') for label in labels]
    sized = [result('pennant_quality', 'bounded_texture_optimization')]
    sized += [result(label + '_pbr2k_albedo4k', 'bounded_texture_optimization') for label in ['shrub_spreading', 'shrub_tall', 'shrub_round', 'foliage_boxwood']]
    preferred = [r for r in exact if r['label'] not in ['shrub_spreading','shrub_tall','shrub_round','foliage_boxwood']] + sized
    visual = read(REVIEW / 'selected_visual_review.json')
    assert visual['passed'] and set(visual['approved_labels']) == {r['label'] for r in sized}
    metadata = read(ART / 'editor_picking/editor_picking_manifest.json')
    manifest = {
        'date': '2026-10-11', 'version': 1, 'status': 'independent_candidates_ready_for_combined_validation',
        'production_map_modified': False, 'production_cache_modified': False, 'source_masters_retained': True,
        'preferred_count': len(preferred), 'preferred': preferred, 'exact_fallbacks': exact,
        'lossless_source_saved_bytes': sum(r['baseline']['source_bytes']-r['optimized']['source_bytes'] for r in exact),
        'preferred_source_saved_bytes': sum(r['baseline']['source_bytes']-r['optimized']['source_bytes'] for r in preferred),
        'visual_review': str(REVIEW / 'selected_visual_review.json'),
        'source_cache_invalidation': str(ART / 'review/pennant_quality/candidate_cache_invalidation.json'),
        'optional_editor_picking_manifest': str(ART / 'editor_picking/editor_picking_manifest.json'),
        'optional_editor_picking_count': metadata['summary']['candidate_count'],
        'excluded_experiments': [
            {'label':'pennant_balanced','reason':'Visible close-range fabric/trim response loss; rejected.'},
            {'label':'foliage_all2k_coverage','reason':'Representative spreading shrub loses close leaf detail and changes fine alpha silhouettes. Other variants not promoted.'},
            {'label':'pennant_detail','reason':'No additional visual validation; superseded by conservative quality profile.'},
            {'label':'pennant_shared','reason':'No additional visual validation; superseded by conservative quality profile.'}],
        'integration_requirements': [
            'Keep original source and hash files. Replace references only in the separately authorized integration stage.',
            'Freeze code and resource SHA, regenerate native/footprint in an isolated root with current generator; never relabel older manifests.',
            'Measure program switches and model substitution separately before full game/editor load and save/reopen tests.',
            'Optional editor picking metadata is a separate opt-in experiment; preserve canonical selection/painting and real collision. Run HTTP selection/painting/save-reopen validation.',
            'RGBA image/mip figures are estimates, not measured asset VRAM. Full-peak admission is not RSS.',
            'Per-asset totals must not be multiplied by instances or added as actual VRAM after cross-asset sharing.',
            'Static and matched wind-frame captures do not establish continuous temporal shimmer or every game lighting condition.']}
    assert read(manifest['source_cache_invalidation'])['passed']
    for path in [ART / 'candidate_handoff.json', REVIEW / 'candidate_handoff.json']:
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({k:manifest[k] for k in ['status','preferred_count','lossless_source_saved_bytes','preferred_source_saved_bytes']},indent=2))

if __name__ == '__main__': main()
