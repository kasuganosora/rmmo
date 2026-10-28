"""Real formal-prefab HTTP check on a private desktop and an owned temporary map.

Default performs syntax checks only. --run is for the parent's serial GPU queue
after successful A/B acceptance and immutable publication. Four formal derived
thumbnails are intentionally regenerated. Never imports models, captures prefabs,
replaces a catalog, or opens/saves a formal town map.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess
from run_godot_background import run_background

ROOT=Path('D:/code/rmmo')
REVIEW=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016')
ENGINE=Path('D:/tools/godot/godot.windows.editor.x86_64.exe')
SCRIPT='res://tools/test_axel_market_realism_published_20261016.gd'

def active_gpu():
    command="Get-CimInstance Win32_Process | Where-Object {($_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless') -or $_.Name -like '*blender*'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    result=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',command],capture_output=True,text=True,check=True)
    return json.loads(result.stdout) if result.stdout.strip() else []

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true')
    parser.add_argument('--publication-take')
    parser.add_argument('--take')
    parser.add_argument('--timeout',type=int,default=2100)
    args=parser.parse_args()
    if not args.run:
        completed=subprocess.run([str(ENGINE),'--headless','--path',str(ROOT),'--script',SCRIPT,'--','--syntax-only'],cwd=ROOT,capture_output=True,timeout=120)
        print(((completed.stdout or b'')+(completed.stderr or b'')).decode('utf-8',errors='replace'))
        raise SystemExit(completed.returncode)
    for key in ['publication_take','take']:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',getattr(args,key) or ''):raise ValueError('Explicit simple publication and HTTP take identifiers required')
    receipt=REVIEW/'publication'/args.publication_take/'publication.json'
    published=json.loads(receipt.read_text(encoding='utf-8'))
    if not (published.get('ok') and published.get('catalog_committed') and published.get('status')=='published_maps_unchanged'):
        raise ValueError('Only a successful committed immutable publication can be verified')
    out=REVIEW/'formal_http'/args.take
    if out.exists():raise ValueError('Choose a new HTTP take; previous evidence is retained')
    if active_gpu():raise RuntimeError('Parent GPU queue is occupied')
    command=[str(ENGINE),'--path',str(ROOT),'--script',SCRIPT,'--',f'--receipt={receipt.as_posix()}',f'--out={out.as_posix()}']
    try:
        result=run_background(command,cwd=ROOT,timeout=args.timeout)
    except Exception as exc:
        out.mkdir(parents=True,exist_ok=True)
        (out/'runner_failure.json').write_text(json.dumps({'passed':False,'error':str(exc),'receipt':str(receipt),'scope':'Read-only formal assets; only temporary-map edits authorized. Interrupted execution is not successful HTTP or completed before/after guard verification.'},indent=2),encoding='utf-8')
        raise
    out.mkdir(parents=True,exist_ok=True)
    log=(result.stdout or b'')+(getattr(result,'stderr',None) or b'')
    (out/'engine.log').write_bytes(log)
    report_path=out/'editor_verification.json'
    report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    engine_clean=not re.search(rb'(?m)^(?:SCRIPT ERROR|ERROR):',log)
    repair=report.get('thumbnail_repair',{})
    repair_passed=len(repair.get('completed_signals',{}))==4 and repair.get('actual_model_load_delta')==4 and len(repair.get('images',[]))==4
    if report.get('completed') and repair_passed:
        spec=importlib.util.spec_from_file_location('review_image','C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        uploads=[]
        for row in repair['images']:
            for field,target in [('review_png','review_image'),('ui_preview_png','ui_preview_image')]:
                png=Path(row[field])
                if not png.resolve().is_relative_to(out.resolve()):raise ValueError('Review compression must not alter formal thumbnails')
                image_receipt=module.prepare(png,lossless=False,keep_source=False,quality=90)
                row[target]=image_receipt;del row[field];uploads.append(image_receipt)
        (out/'image_upload_receipts.json').write_text(json.dumps(uploads,indent=2),encoding='utf-8')
        report_path.write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    passed=result.returncode==0 and report.get('passed') and report.get('completed') and report.get('verified_count')==4 and engine_clean and repair_passed
    summary={'passed':bool(passed),'report':str(report_path),'report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest() if report_path.exists() else '', 'returncode':result.returncode,'verified_count':report.get('verified_count',0),'engine_error_free':engine_clean,'thumbnail_repair_passed':repair_passed,'formal_paths_used_directly':True,'formal_map_modified':False}
    (out/'runner_result.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps(summary))
    raise SystemExit(0 if passed else 1)

if __name__=='__main__':main()
