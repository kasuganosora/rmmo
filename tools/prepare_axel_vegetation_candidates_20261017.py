"""Prepare four isolated exact-data candidates; never publish or overwrite sources."""
import contextlib
import json
from pathlib import Path
import audit_axel_reused_vegetation_20261017 as audit

OUTPUT = audit.RUNTIME / 'art_sources/axel_vegetation_optimization_20261017/grass_exact01'
LABELS = ('arch_grass_a', 'arch_grass_b', 'arch_grass_c', 'short_grass_a')
EXPECTED = (
    '117f47a0c7206cd03bdf3fcecc3f0a0a2b9ecd64d8f96709c558c3b49be2994f',
    'c9c641df3c4c6f79a5d907f429a447317cf58704e2ad3dcf4b80445153363994',
    '2abd3fe0f222d1e7cf69fa26eb5a6f05e21aca2cf041beb7301bd1847bd16c15',
    '308166ed85d0b11149c120eab53211d90f90e8fee569c434d58a920b289dcd2b',
)


def guard_extras(document):
    """Only this inspected grammar is safe under resource table remapping."""
    allowed = {'rmmo_collision', 'rmmo_grass', 'rmmo_leaf_backlight', 'rmmo_visibility_range', 'rmmo_wind', 'source_fab'}

    def walk(value, path=()):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == 'extras':
                    assert len(path) == 2 and path[0] == 'nodes', ('Unreviewed extras owner', path)
                    assert not set(item) - allowed, ('Unknown metadata', path)
                    assert item['rmmo_collision'] == 'none' and item['rmmo_grass'] is True
                    assert all(isinstance(n, (int, float)) for n in item['rmmo_leaf_backlight'])
                    r = item['rmmo_visibility_range']
                    assert set(r) == {'begin', 'end', 'bounds'} and len(r['bounds']) == 6
                    assert all(isinstance(n, (int, float)) for n in [r['begin'], r['end']] + r['bounds'])
                    if 'rmmo_wind' in item:
                        w = item['rmmo_wind']
                        assert set(w) == {'amplitude', 'anchor', 'mesh', 'profile', 'shelter', 'stiffness'}
                        assert w['mesh'] == '*' and w['profile'] == 'foliage' and w['anchor'] == 'bottom'
                        assert isinstance(w['shelter'], bool)
                        assert all(isinstance(w[k], (int, float)) for k in ['amplitude', 'stiffness'])
                    if 'source_fab' in item:
                        assert item['source_fab'] == '70b6ac17-a842-48d9-81e4-41f80fe160d9'
                else:
                    walk(item, path + (key,))
        elif isinstance(value, list):
            for i, child in enumerate(value):
                walk(child, path + (i,))
    walk(document)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    catalog_path = audit.ASSETS / 'library.json'
    map_before, catalog_before = audit.sha(audit.MAP), audit.sha(catalog_path)
    baseline = audit.read(audit.OUT / 'audit01.json')
    audit.graph.OUT = OUTPUT
    reports = []
    with (OUTPUT / 'build.log').open('w', encoding='utf-8') as log, contextlib.redirect_stdout(log):
        for label, digest in zip(LABELS, EXPECTED):
            row = next(x for x in baseline['models'] if x['sha256'] == digest)
            source = audit.Glb(Path(row['path']))
            try:
                audit.graph.guard_graph(source.j)
                guard_extras(source.j)
            finally:
                source.close()
            audit.graph.compact({'path': row['path'], 'source_sha256': digest}, label)
            report_path = OUTPUT / (label + '_audit.json')
            report = audit.read(report_path)
            candidate = audit.audit(Path(report['candidate']))
            assert candidate['active_rgba8_mip_budget_bytes'] == row['active_rgba8_mip_budget_bytes']
            assert candidate['stats']['unique_mesh_triangles'] == row['stats']['unique_mesh_triangles']
            assert candidate['nodes_fingerprint'] == row['nodes_fingerprint']
            assert candidate['stats']['unreferenced_view_bytes'] == 0
            model_review = {
                'label': label, 'source_master': audit.identity(Path(row['path'])),
                'candidate': audit.identity(Path(report['candidate'])),
                'resource_audit': 'passed_exact_resolved_graph_and_direct_referenced_bytes',
                'visual_quality': 'pending_new_same_camera_light_wind_alpha_shadow_comparison',
                'runtime_pipeline': 'pending_isolated_native_import_save_reopen_current_generator',
                'formal_integration': 'not_published',
                'source_bytes_saved': report['saved_bytes'],
                'active_rgba8_mip_budget_bytes': candidate['active_rgba8_mip_budget_bytes'],
                'gpu_memory_savings_claimed': False,
                'no_decimation_no_texture_reencode_no_resize': True,
                'all_declared_meshes_including_lod_preserved': True,
                'wind_collision_visibility_extras_preserved': True,
                'metadata_dependency_grammar_checked': True,
                'exact_data_report': audit.identity(report_path),
                'candidate_inventory': candidate,
                'baseline_current_map_direct_records': row['formal_map_direct_record_count'],
                'optimization_need': 'Remove unreachable image/accessor history. Retain existing three authored LOD meshes and all active image bytes.',
            }
            destination = OUTPUT / (label + '_model_review.json')
            destination.write_text(json.dumps(model_review, ensure_ascii=False, indent=2), encoding='utf-8')
            reports.append({'label': label, 'candidate': model_review['candidate'], 'review': audit.identity(destination), 'saved_bytes': report['saved_bytes']})
    assert map_before == audit.sha(audit.MAP) and catalog_before == audit.sha(catalog_path)
    delivery = {
        'scope': 'CPU candidate preparation only; not visually accepted or published',
        'models': reports, 'saved_source_bytes_total': sum(r['saved_bytes'] for r in reports),
        'baseline_source_bytes_total': sum(r['bytes'] for r in baseline['models'] if r['sha256'] in EXPECTED),
        'candidate_source_bytes_total': sum(r['candidate']['bytes'] for r in reports),
        'all_originals_retained': True, 'formal_map_sha256': map_before, 'formal_map_unchanged': True,
        'formal_catalog_sha256': catalog_before, 'formal_catalog_unchanged': True,
        'gpu_runs': 0, 'native_cache_writes': 0,
        'remaining': ['Isolated native import/save/reopen', 'Fixed-camera/light/exposure near/medium/far and alpha-edge/shadow comparison at fixed wind times', 'Current LOD transition and editor picking contract', 'Publication only after required acceptance'],
    }
    (OUTPUT / 'delivery.json').write_text(json.dumps(delivery, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(delivery, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
