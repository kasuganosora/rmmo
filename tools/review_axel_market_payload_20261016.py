"""Prepare fixed market A/B receipts; GPU execution is explicit and serial only.

Default writes this task's read-only-source plan. --run starts private desktops
after the caller has coordinated the GPU queue. Never publishes formal assets.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess,sys,time
from run_godot_background import run_background

ROOT=Path('D:/code/rmmo')
RUNTIME=Path('D:/code/rmmo_runtime')
ART=RUNTIME/'art_sources/axel_market_optimization_20261016'
REVIEW=RUNTIME/'review_artifacts/axel_market_optimization_20261016'
ENGINE=Path('D:/tools/godot/Godot_v4.7.2-stable_win64.exe')
LIBRARY=RUNTIME/'packs/default/assets/library.json'
SCRIPT='res://tools/review_axel_market_payload_20261016.gd'
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def put(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def active_gpu():
    code="Get-CimInstance Win32_Process | Where-Object {$_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    p=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',code],capture_output=True,text=True,check=True)
    return json.loads(p.stdout) if p.stdout.strip() else []
def absolute_record_path(value):
    p=Path(value)
    return p if p.is_absolute() else LIBRARY.parent/p

def prepare():
    summary=read(ART/'summary.json');catalog=read(LIBRARY);rows=[]
    for row in summary['rows']:
        assert sha(row['source'])==row['source_sha256'] and sha(row['candidate'])==row['candidate_sha256']
        matches=[]
        for index,entry in enumerate(catalog):
            if 'prefab_path' not in entry:continue
            path=absolute_record_path(entry['prefab_path'])
            prefab=read(path)
            records=[r for r in prefab.get('records',[]) if Path(r.get('asset_path','')).name==Path(row['source']).name]
            if records:
                assert len(records)==len(prefab['records'])==1, 'Unexpected multi-part market prefab'
                matches.append({'catalog_index':index,'entry':entry,'prefab_path':path.as_posix(),'prefab_sha256':sha(path),'prefab':prefab,'old_asset_id':path.as_posix()})
        assert len(matches)==1, f"Need one exact existing prefab for {row['asset']}: {len(matches)}"
        old=matches[0]
        # Frozen payload template: only the source reference changes. Capture's
        # canonical JSON/label hashing will determine the new immutable ID later.
        replacement=json.loads(json.dumps(old['prefab']))
        replacement['records'][0]['asset_path']=row['candidate_sha256']+'.glb'
        plan={k:row[k] for k in ['asset','label','source','source_sha256','candidate','candidate_sha256','source_bytes','candidate_bytes']}
        plan['label']=old['entry']['label'];plan['existing_prefab']=old
        plan['candidate_payload_template']=replacement
        plan['prospective_formal_glb']=(LIBRARY.parent/(row['candidate_sha256']+'.glb')).as_posix()
        plan['candidate_prefab_id']='PENDING production Prefabs.capture serialization/hash after acceptance'
        plan['identity_rule']='New immutable prefab_path/MCP asset_id. Preserve original catalog slot/name/category, record uuid/position/rotation/size and other fields. Retain old prefab and GLB.'
        rows.append(plan)
    output={'version':1,'status':'PREPARED_NOT_RUN','source_summary_sha256':sha(ART/'summary.json'),'catalog_snapshot':{'path':LIBRARY.as_posix(),'sha256':sha(LIBRARY)},'scope':'4 isolated old/new native and fixed-frame comparisons; no formal library/map writes','rows':rows,'render':{'width':1400,'height':1000,'views':['near','medium','far','back','cloth_detail','goods_detail','structure_detail'],'same_camera_from':'baseline camera_views.json','texture_policy':'No source texture readback/reencode/resize; CPU compactor already proves actual bytes/pixels. Native engine import performs its ordinary decode.','screenshots':'Exact PNG stays local until comparison; upload actual original-size lossy WebP Q90 with receipt.'},'pending':['Queue after parent releases church/guardhouse/watermill GPU + HTTP work','Native packed and footprint results','Same-frame image comparison and actual visual inspection','Formal publication and old→new asset_id mapping; not this tool','Layout owner may later update old map instances; no map automatic replacement']}
    put(ART/'review_plan.json',output)
    put(ART/'publication_plan.json',{'version':1,'status':'PLAN_ONLY_NOT_AUTHORIZED_BY_THIS_SCRIPT','catalog_before':output['catalog_snapshot'],'rows':rows,'existing_tools':{'import':'scripts/world_editor/asset_library.gd: import_file, _compile_import, save','prefab':'scripts/world_editor/prefab_library.gd: capture, read','known_example':'tools/publish_town_props.gd (hardcoded historical batch: do not execute unchanged)','conflict_save':'AssetLibrary.save uses revision + native save lock + atomic publication','immutable_copy_example':'tools/publish_joint_model_candidates.gd: import_exact_candidate (hardcoded historical map migration: do not execute unchanged)'},'preserve':['Original library slot, label, category and author-facing semantics','Prefab record obj_1 UUID and full transform/size, bounds, surface/collision values','Old GLBs/prefabs/native masters in place, no rewriting content-addressed files','All formal maps unchanged'], 'requires_after_acceptance':['Stage each new content-addressed GLB with exact source SHA and valid closed embedded graph','Use production importer/native+footprint path, no direct mutable replacement under old SHA','Capture cloned prefab record with only asset_path changed, validate new payload and compare all other fields','Reload fresh catalog revision; remove temporary direct-asset/duplicate entries and replace exactly the original prefab slot preserving label/category','One conflict-aware catalog save and reopen; guard original catalog entries and source SHAs before publication','Generate/reuse thumbnail under new immutable prefab ID','Emit old_asset_id→new_asset_id and old_glb→new_glb mapping for layout owner; no automatic map rewrite','Real HTTP list_assets/place_asset/undo/redo/save/reopen in a temporary map after library publication']})
    return output

def command(asset,case,take,headless=False):
    return [str(ENGINE),*(['--headless'] if headless else []),'--path',str(ROOT),'--script',SCRIPT,'--',f'--asset={asset}',f'--case={case}',f'--take={take}']

def run(args,plan):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',args.take):raise ValueError('Take must be an identifier')
    folder=REVIEW/args.take
    if folder.exists():raise ValueError('Use a fresh take; previous evidence is immutable')
    busy=active_gpu()
    if busy:raise RuntimeError(f'GPU queue not released: {busy}')
    folder.mkdir(parents=True);status={'state':'starting','owner':'market_review','take':args.take,'plan_sha256':sha(ART/'review_plan.json'),'formal_writes':False,'jobs':[]};put(folder/'status.json',status)
    for row in plan['rows']:
        asset=row['asset']
        for case in ['baseline','candidate','compare']:
            if case!='compare' and active_gpu():raise RuntimeError('Another GPU process appeared; stopping before next owned job')
            cmd=command(asset,case,args.take,case=='compare');began=time.time()
            status.update(state='running',asset=asset,case=case,updated=began);put(folder/'status.json',status)
            if case=='compare':p=subprocess.run(cmd,cwd=ROOT,capture_output=True,timeout=args.timeout)
            else:p=run_background(cmd,cwd=ROOT,timeout=args.timeout)
            dest=folder/asset;dest.mkdir(exist_ok=True);(dest/(case+'.log')).write_bytes(p.stdout)
            status['jobs'].append({'asset':asset,'case':case,'returncode':p.returncode,'elapsed_seconds':time.time()-began});put(folder/'status.json',status)
            report=read(dest/(case+'.json')) if (dest/(case+'.json')).exists() else {}
            if p.returncode or not report.get('passed'):raise RuntimeError(f'{asset}/{case} failed; retained local PNG and native evidence')
        # Exact comparisons precede upload compression. Keep PNG only if needed
        # to diagnose a failed compare; successful PNG has saved pixel SHA/delta.
        spec=importlib.util.spec_from_file_location('review_image','C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        receipts=[]
        for png in sorted((folder/asset).glob('*/*.png')):receipts.append(module.prepare(png,lossless=False,keep_source=False,quality=90))
        put(folder/asset/'image_upload_receipts.json',receipts)
        for case in ['baseline','candidate']:
            report_path=folder/asset/(case+'.json');report=read(report_path);lookup={Path(r['source']).as_posix():r for r in receipts}
            for shot in report['screenshots']:
                receipt=lookup[Path(shot['path']).as_posix()];shot['local_png_sha256']=shot['file_sha256'];shot.update(path=receipt['path'],file_sha256=receipt['sha256'],upload_encoding={'quality':90,'lossless':False,'dimensions':receipt['dimensions']})
            report['visual_inspection']='PENDING actual viewing';put(report_path,report)
    status.update(state='completed_awaiting_visual_inspection',updated=time.time());put(folder/'status.json',status)
    print(json.dumps({'completed':True,'output':str(folder),'gpu_visual_inspection':'pending','formal_writes':False}))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true');parser.add_argument('--take',default='gpu_ab01');parser.add_argument('--timeout',type=int,default=900);args=parser.parse_args()
    # Running frozen acceptance must never rewrite the source/catalog plans.
    plan=read(ART/'review_plan.json') if args.run else prepare()
    if args.run:
        try:return run(args,plan)
        except Exception as exc:
            status_path=REVIEW/args.take/'status.json'
            if status_path.exists():
                status=read(status_path)
                if status.get('state')=='running':
                    status.update(state='failed',error=str(exc),updated=time.time())
                    put(status_path,status)
            raise
    print(json.dumps({'status':'PREPARED_NOT_RUN','plan':str(ART/'review_plan.json'),'publication_plan':str(ART/'publication_plan.json'),'pairs':len(plan['rows']),'run_after_parent_releases_gpu_queue':f'python tools/review_axel_market_payload_20261016.py --run --take={args.take}','gpu_started':False},ensure_ascii=False))

if __name__=='__main__':main()
