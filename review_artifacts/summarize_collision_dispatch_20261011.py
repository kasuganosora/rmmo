"""Dispatch order comparison; no changes to collision gates or byte budgets."""
import json
import statistics
import sys
from pathlib import Path

here=Path(__file__).resolve().parent
reports=Path('D:/code/rmmo_runtime/review_artifacts')
rows=[]
for label in sys.argv[1:]:
    name=f'loading_collision_dispatch_{label}_20261011'
    p=json.loads((reports/(name+'.json')).read_text(encoding='utf-8-sig'))
    stats=p['entry_collision_profile']
    core=p['world_profile']['entry_core_resources_ready_us']
    events=p['monitor']['trace']['events']
    row={'label':label,'dispatch_first':stats['dispatch_before_installation'],
         'entry_ms':p['entry_ms'],'core_ms':p['entry_core_ready_ms'],
         'failures':p['failures'],'cache_candidate':p['cache_candidate'],
         'idle_budget_frames':stats.get('dispatch_budget_idle_frames',0),
         'eligible_budget_frames':stats.get('dispatch_budget_eligible_frames',0),
         'none_accepted_at_entry':stats.get('none_accepted',0),
         'max_main_us':stats['max_main_us'],'peak_workers':stats['peak_workers'],
         'prepare_peak_bytes':stats['preparing']['peak_bytes'],
         'first_10s_frame_ms':p['monitor']['phase_frame_percentiles_ms'].get('playable_background')}
    for field in ['collision_dependencies_ready','scope_ready','landing_visual_ready']:
        yes=[e for e in events if e['label']=='entry.geometry_gate' and e['details'].get(field) is True]
        row[field+'_after_core_ms']=(yes[0]['start_us']-core)/1000 if yes else None
    accepted=[e for e in events if e['label']=='collision.none.accept']
    row['first_none_after_core_ms']=(accepted[0]['start_us']-core)/1000 if accepted else None
    rows.append(row)
result={'notes':['Same collision-first and no-collision proofs; only dispatch order differs.',
                 'Frame/byte/worker budgets unchanged. Diagnostic stop reason enabled in both modes.',
                 'Fresh process warm derived caches; OS/driver caches not flushed.'], 'runs':rows}
for mode in [False,True]:
    group=[r for r in rows if r['dispatch_first']==mode and r['failures']==0]
    if group:result['dispatch_before_installation' if mode else 'dispatch_after_installation']={'count':len(group),'mean':{k:statistics.mean(r[k] for r in group) for k in ['entry_ms','core_ms','idle_budget_frames','collision_dependencies_ready_after_core_ms','scope_ready_after_core_ms']}}
(here/'loading_collision_dispatch_summary_20261011.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
