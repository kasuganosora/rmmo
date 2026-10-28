"""Recheck current street candidates in a temporary HTTP/native fixture.

Parent agent schedules this runner; no foreground windows or formal map writes.
Unchanged imports may be reused only after the production identity validates.
"""
from pathlib import Path
import subprocess
import argparse
import shutil
import time
import hashlib
import json
import os
from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review_artifacts/required_street_recheck_20261013'
GODOT = Path('D:/tools/godot/godot.windows.editor.x86_64.exe')
MANIFEST = 'D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json'

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))

def verify_sources():
    rows=read_json(MANIFEST)['assets']
    assert len(rows)==11 and len({r['id'] for r in rows})==11
    for row in rows:
        path=Path(row['path'])
        assert path.is_file(), path
        assert hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'], row['id']
        assert path.stat().st_size==row['source_bytes'], row['id']
    return rows

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gallery',action='store_true',help='First redo the eight reference-corrected stone/arch/tree outputs')
    parser.add_argument('--stones-gallery',action='store_true',help='Only redo five stones after continuous UV correction')
    parser.add_argument('--tree-gallery',action='store_true',help='Only redo the tree after S10 bark tone correction')
    parser.add_argument('--demo-gallery',action='store_true',help='Redo the installation wall after curved-opening repair')
    parser.add_argument('--quick-stones',action='store_true',help='Only two combo views for geometry iteration; skips final HTTP/native acceptance')
    args=parser.parse_args()
    rows=verify_sources()
    OUT.mkdir(parents=True, exist_ok=True)
    history=OUT/'history';history.mkdir(exist_ok=True)
    stamp=time.strftime('%Y%m%d_%H%M%S')
    for name in ['editor_http.json','editor_http.log','traversal_native.json','traversal_native.log','summary_subset.json','native_gpu_reference_fixes.log']:
        path=OUT/name
        if path.exists():shutil.copy2(path,history/(stamp+'_'+name))
    if args.gallery or args.stones_gallery or args.tree_gallery or args.demo_gallery or args.quick_stones:
        ids=['s12_water_step_a','s12_water_step_b','s12_water_step_c','s12_water_step_d','s12_water_steps_four'] if args.gallery or args.stones_gallery else []
        if args.gallery:ids+=['s12_projecting_arch','s12_facade_installation_demo','s10_redfruit_broadleaf']
        elif args.tree_gallery:ids+=['s10_redfruit_broadleaf']
        if args.demo_gallery and 's12_facade_installation_demo' not in ids:ids+=['s12_facade_installation_demo']
        if args.quick_stones:
            assert not (args.gallery or args.stones_gallery or args.tree_gallery or args.demo_gallery)
            ids=['s12_water_steps_four']
            os.environ['RMMO_STREET_QUICK_SHOULDERS']='1'
        try:
            result=run_background([GODOT,'--path',ROOT,'-s','res://tools/review_required_street_assets_recheck.gd','--',*ids],cwd=ROOT,timeout=700)
        finally:
            os.environ.pop('RMMO_STREET_QUICK_SHOULDERS',None)
        (OUT/'native_gpu_reference_fixes.log').write_bytes(result.stdout)
        print('STREET_GALLERY_EXIT',result.returncode,flush=True)
        if result.returncode:return result.returncode
        summary=read_json(OUT/'summary_subset.json')
        assert set(summary['assets'])==set(ids) and not summary['failures']
        for row in rows:
            if row['id'] not in ids:continue
            report=read_json(OUT/row['id']/'report.json')
            assert report['passed'] and report['gallery_completed']
            assert report['identity']['sha256']==row['sha256']
            assert all((OUT/row['id']/shot['name']).is_file() for shot in report['screenshots'])
        if args.quick_stones:
            verify_sources()
            return 0
    result = run_background([GODOT, '--path', ROOT, '-s', 'res://tools/test_required_street_assets_http_recheck.gd','--','--reuse-imports'], cwd=ROOT, timeout=1050)
    (OUT / 'editor_http.log').write_bytes(result.stdout)
    print('STREET_HTTP_EXIT', result.returncode, flush=True)
    if result.returncode:
        return result.returncode
    report=read_json(OUT/'editor_http.json')
    assert report['completed'] and report['passed'] and len(report['items'])==11
    for row in rows:
        item=next(x for x in report['items'] if x['id']==row['id'])
        assert item['input_sha']==row['sha256'] and item['passed'] and item['http_passed']
    result = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '-s', 'res://tools/test_required_street_traversal_recheck.gd', '--', MANIFEST, '--native'], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=150)
    (OUT / 'traversal_native.log').write_bytes(result.stdout)
    print('STREET_NATIVE_TRAVERSAL_EXIT', result.returncode, flush=True)
    if result.returncode==0:
        report=read_json(OUT/'traversal_native.json')
        assert report['passed'] and len(report['cases'])==8
        assert all(case['reached'] and case['native_sha'] for case in report['cases'])
        verify_sources()
    return result.returncode

if __name__ == '__main__':
    raise SystemExit(main())
