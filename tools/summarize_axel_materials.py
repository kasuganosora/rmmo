"""Include material work units, not only the now-cheaper final publication."""
import json
from pathlib import Path
import sys
from summarize_axel_publication import summarize, sha


def material_summary(folder):
    row = summarize(folder)
    report = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
    trace = json.loads((folder / 'publication_trace.json').read_text(encoding='utf-8'))
    units = [e for e in trace['events'] if e['label'] in
             ('deferred.material_step', 'deferred.publication')]
    profile = report['region_samples'][-1]['queue_profile']
    row.update(material_slices=report.get('material_slices', False),
               max_combined_unit_ms=max(e['duration_us'] for e in units) / 1000,
               slowest_combined_unit=max(units, key=lambda e: e['duration_us']),
               material_units=profile.get('material_preparation_units', 0),
               max_material_unit_ms=profile.get('max_material_preparation_unit_us', 0) / 1000,
               max_slice_ms=profile['max_publish_us'] / 1000,
               main_thread_budgets=profile['main_thread_budgets'])
    return row


if __name__ == '__main__':
    root = Path(sys.argv[1])
    rows = [material_summary(root / name) for name in sys.argv[2:]]
    controls = [r for r in rows if r['run'] != 'baseline']
    if len(controls) > 1:
        for key in ['publication_sources', 'map_sha256', 'camera_recipe',
                    'render_inventory', 'water', 'subject_ids']:
            assert all(row[key] == controls[0][key] for row in controls), key
        for key in ['models', 'instances', 'specs']:
            assert all(row['counts'][key] == controls[0]['counts'][key] for row in controls), key
    for row in rows:
        assert row['failures'] == 0 and row['region_ready'] and row['trace_dropped'] == 0
        assert not row['shared_prefab_pixels']
        assert all(row['counts'][k] == 0 for k in ['failed_instances', 'failed_paths',
                                                 'total_jobs', 'reserved_bytes'])
    result = {'limits': 'Existing OS/derived caches, same route and bounded trace; not cold startup. '
              'Combined unit includes both material and final scene publication. Slice includes '
              'acceptance and ready scan, not whole frame or GPU duration. Accounted bytes are not RSS/VRAM.',
              'runs': rows}
    target = root / 'material_measurements.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for row in rows:
        print(json.dumps({k: row[k] for k in ['run', 'region_wait_ms', 'max_combined_unit_ms',
                                             'max_slice_ms', 'material_units', 'failures']}))
    print('Evidence SHA256', sha(target))
