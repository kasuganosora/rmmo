"""Run only affected acceptance after the two roof-normal detail pairs are approved.

The caller must own the serial private GPU slot. Runtime activities, lights and
optimization A/B are reused through the independent e24-to-successor scope proof.
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import time

from run_guild_main_patch_checks import ART, OUT, ROOT, gpu, load, sha, webp_gallery


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-sha',required=True)
    options=parser.parse_args()
    proof_path=OUT/'roof_normal_scope/independent_scope_audit.json'
    proof=load(proof_path)
    assert proof['passed'] and proof['after']['sha256']==options.expected_sha
    assert proof['audit_tool_sha256']==sha(ROOT/'tools/audit_guild_roof_scope.py')
    for identity in [proof['before'],proof['after']]:
        assert sha(identity['path'])==identity['sha256']
    source=Path(proof['after']['path'])
    assert load(ART/'repair_manifest.json')['final_sha256']==options.expected_sha
    history=OUT/'history'/('before_roof_acceptance_'+time.strftime('%Y%m%d_%H%M%S'))
    history.mkdir(parents=True,exist_ok=True)
    for relative in ['resource_audit/axel_guild_repaired.json','resource_audit/index.json']:
        shutil.copy2(OUT/relative,history/Path(relative).name)
    cpu=subprocess.run([sys.executable,'tools/audit_guild_reference_resources.py'],cwd=ROOT,
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
    (OUT/'accepted_roof_resource.log').write_bytes(cpu.stdout)
    print('END accepted_roof_resource',cpu.returncode,flush=True)
    if cpu.returncode:return cpu.returncode
    imported_dir=OUT/'accepted_roof_import'
    gpu('accepted_roof_import','res://tools/test_guild_reference_import.gd',[
        f'--source-dir={ART.as_posix()}',f'--out={imported_dir.as_posix()}',
        '--only=axel_guild_repaired','--isolated-content'])
    imports=load(imported_dir/'import_report.json')
    assert imports['completed'] and imports['passed'] and imports['real_http']
    assert len(imports['items'])==1
    item=imports['items'][0]
    assert item['input_sha']==options.expected_sha and item['passed'] and item['http_passed']
    for case,identity,scale in [('before',proof['before'],.8),('after',proof['after'],1.0)]:
        directory=OUT/('accepted_roof_before_distance' if case=='before' else 'accepted_roof_building')
        gpu(directory.name,'res://tools/review_guild_roof_normal.gd',[
            f'--source={Path(identity["path"]).as_posix()}',f'--out={directory.as_posix()}',
            '--kind=building','--views=near,medium,far,roof_material',f'--normal-scale={scale}',
            f'--normal-image={(OUT/"roof_normal_scope"/(case+"_normal.png")).as_posix()}'])
        webp_gallery(directory)
        gallery=load(directory/'report.json')
        assert gallery['passed'] and gallery['gallery_completed'] and gallery['identity']['sha256']==identity['sha256']
    assert sha(source)==options.expected_sha
    for identity in proof['unchanged_deliveries']:
        row=load(OUT/'acceptance'/(identity['id']+'.json'))
        assert sha(row['source_path'])==identity['sha256']
    summary=dict(source_sha256=options.expected_sha,source_immutable=True,passed=True,
                 scope_proof=dict(path=str(proof_path),sha256=sha(proof_path)),
                 import_report=str(imported_dir/'import_report.json'),
                 same_camera_before_after=['near','medium','far','roof_material'],
                 manual_visual_status='pending independent final distance inspection',
                 reused_scopes=proof['inherited_scopes'],
                 note='No repeated full-scene runtime or twenty-camera optimization run; their original e24 source SHA remains explicit.')
    (OUT/'accepted_roof_checks.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
    print('ROOF_AFFECTED_AUTOMATIC_CHECKS_COMPLETE',flush=True)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
