"""Assemble layout-stage structure/circulation evidence, retaining failed comfort checks.

Does not modify raw reports, approve images, alter the controller or publish maps.
The user's layout-first phase permits a separately disclosed locomotion follow-up;
the old 20-tick comfort criterion remains failed and cannot be called repaired.
"""
import hashlib
import json
from pathlib import Path

OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016')
ROOT = Path('D:/code/rmmo')
SHA = 'cbfa6d3b0d5315d934bb679c741976e15d9e3170808dccac8bf74cb857248475'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def pin(path):
    return {'path': str(path).replace('\\', '/'), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    original_path = OUT / 'fortification_runtime/result.json'
    descent_path = OUT / 'tower_descent_diagnostic/result.json'
    assessment_path = OUT / 'tower_descent_layout_assessment.json'
    visual_path = OUT / 'scene_visibility_final/result.json'
    original, descent, assessment, visual = map(read, [original_path, descent_path, assessment_path, visual_path])
    assert all(d.get('map_sha256') == SHA for d in [original, descent, assessment, visual])
    assert pin(ROOT / 'tools/probe_axel_tower_descent.gd')['sha256'] == descent['source_sha256']['res://tools/probe_axel_tower_descent.gd']
    for name in ['world_authority.gd', 'world_player.gd', 'world_motion.gd', 'fortification_stair_mesh.gd']:
        assert pin(ROOT / 'scripts/world3d' / name)['sha256'] == descent['source_sha256']['res://scripts/world3d/' + name]
    failed = [c for c in original['checks'] if not c['passed']]
    assert original['phase'] == 'complete' and original['failures'] == 2
    assert {c['name'] for c in failed} == {f'actual player follows internal tower route tower_{t}_internal_descent' for t in [2, 9]}
    assert descent['diagnostic_complete'] and descent['failures'] == 0
    assert assessment['layout_structure_passed'] and assessment['observed_bidirectional_traversal_passed']
    assert assessment['totals']['actual_below_missing_ticks'] == 0 and assessment['totals']['source_tread_owner_mismatches'] == 0
    checks = [c for c in original['checks'] if c['passed']]
    for row in descent['towers']:
        assert row['tower'] in [2, 9] and row['actual_target_reached_grounded'] and row['remaining_m'] < .45
        assert row['actual_below_missing_ticks'] == 0 and row['final_original_support']['ok'] and row['controller_unchanged']
        assert all(a['relanded'] for a in row['airborne_segments'])
        checks.append({'name': f"Observed complete physical descent and grounded arrival tower {row['tower']}", 'passed': True,
                       'details': {k: row[k] for k in ['remaining_m', 'actual_target_reached_grounded', 'actual_below_missing_ticks', 'maximum_original_unsupported_ticks']}})
    assert visual['phase'] == 'complete' and visual['status'] == 'passed' and visual['failures'] == 0
    replacements = {s['id']: s for s in visual['screenshots']}
    required = {'area_market', 'area_farm', 'area_south_grove', 'water_gate_3_mid', 'city_fortification_overview'}
    assert set(replacements) == required
    shots = [replacements.get(s['id'], s) for s in original['screenshots']]
    assert len(shots) == 19 and len({s['id'] for s in shots}) == 19
    for shot in shots:
        path = Path(shot['path']); receipt = read(Path(str(path) + '.review-image.json'))
        assert pin(path)['sha256'] == shot['sha256'] == receipt['sha256'] and receipt['quality'] == 90 and not receipt['lossless']
    result = {'map_sha256': SHA, 'phase': 'complete', 'status': 'passed', 'failures': 0,
              'scope': 'Layout-stage structural continuity, actual circulation, gate operation and exterior capture coverage. NOT complete locomotion/comfort acceptance or visual approval.',
              'phase_basis': 'User requested overall layout before details; genuine blockage, penetration, unsupported terrain and save failures remain blocking.',
              'checks': checks + visual['checks'], 'screenshots': shots,
              'deferred_checks': failed, 'original_full_acceptance_passed': False,
              'deferred_status': 'Running downstairs still has up to 31 airborne physics ticks and 1.35m total drop per episode; original 20-tick bound remains failed. No controller or threshold changes adopted.',
              'source_reports': [pin(p) for p in [original_path, descent_path, assessment_path, visual_path]],
              'superseded_capture_records': [s for s in original['screenshots'] if s['id'] in required],
              'scope_limits': ['This staged result never replaces the original failed full report.', 'No full-town loading performance, RSS/VRAM or final material/vegetation-density acceptance.']}
    target = OUT / 'fortification_layout_stage_runtime.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'path': str(target), 'layout_checks': len(result['checks']), 'deferred_comfort_checks': len(failed)}))


if __name__ == '__main__':
    main()
