import json
import sys
from pathlib import Path

for name in sys.argv[1:]:
    data = json.loads(Path(name).read_text(encoding='utf-8-sig'))
    route = data.get('town_route', {})
    result = {k: data.get(k) for k in ['entry_ms', 'failures', 'authored_record_count', 'resident_record_count']}
    result.update(file=name, route_ok=route.get('ok'), route_reason=route.get('reason'))
    result['legs'] = []
    for leg in route.get('legs', []):
        row = {k: leg.get(k) for k in ['target', 'reached', 'elapsed_ms', 'position', 'frames', 'blocked', 'path_status', 'navigation_clips']}
        profile = leg.get('deferred', {})
        row['deferred'] = {k: profile.get(k) for k in [
            'active_jobs', 'total_jobs', 'max_total_jobs', 'ready_job_limit', 'reserved_bytes',
            'peak_reserved_bytes', 'dispatch_scan_us', 'max_dispatch_scan_us', 'dispatch_attempts',
            'dispatch_cursor', 'dispatch_paths', 'ready_scan_us', 'max_ready_scan_us',
            'frame_bookkeeping_us', 'priority_retirements', 'admission_drain_path', 'demanded_instances']}
        row['navigation'] = leg.get('navigation')
        result['legs'].append(row)
    print(json.dumps(result, indent=2, ensure_ascii=False))
