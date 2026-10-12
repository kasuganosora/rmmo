"""Four follow-up current-town lossless candidates; never writes source or map."""
from pathlib import Path
import importlib.util,json

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('architecture_lossless',HERE/'architecture_lossless.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
helper.OUT=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/secondary')
helper.OUT.mkdir(parents=True,exist_ok=True)
rows=json.loads((HERE/'inventory_report.json').read_text(encoding='utf-8'))['rows']
reports=[]
for prefix,label in [('b3d6babb','garden_wall_240_b3d6babb'),('510592a4','garden_pier_tall_510592a4'),('389bb6a0','garden_pier_medium_389bb6a0'),('83c1f150','wall_pointed_blue_83c1f150')]:
    row=next(r for r in rows if Path(r['path']).name.startswith(prefix))
    report=helper.compact(row,label)
    report['instance_count']=row['instance_count']
    report['scope_note']='Four secondary current-map assets; no GPU, cache build, publication or saved-map change in this subtask.'
    report['gpu_validation']='not run; scheduled by parent with same-camera conditions'
    reports.append(report)
    audit_path=helper.OUT/(label+'_audit.json')
    audit=json.loads(audit_path.read_text(encoding='utf-8'))
    audit.update(scope_note=report['scope_note'],gpu_validation=report['gpu_validation'],instance_count=row['instance_count'])
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
(HERE/'inventory_secondary_summary.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
(helper.OUT/'secondary_lossless_summary.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
