"""Serial recheck of one revised guild building; frozen props/tower are reused.

The caller supplies the expected new SHA and schedules the private GPU desktop.
No production map, catalogue, cache budget or shared-cache content is modified.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time

from PIL import Image
from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review_artifacts/guild_reference_recheck_20261013'
ART = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
GODOT = Path('D:/tools/godot/godot.windows.editor.x86_64.exe')
OPT = ROOT / 'review_artifacts/axel_guild_finish_20261012/reference_v3_patch_optimization_20261013'


def load(path):
    return json.loads(Path(path).read_text(encoding='utf8'))


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def gpu(label, script, args, timeout=1500):
    print('BEGIN', label, flush=True)
    result = run_background([GODOT, '--path', ROOT, '--script', script, '--', *args],
                            cwd=ROOT, timeout=timeout)
    (OUT / (label + '.log')).write_bytes(result.stdout)
    print('END', label, result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)


def webp_gallery(folder):
    """Viewing copies are lossless WebP; PNG stays local for exact A/B tooling."""
    conversions = []
    for original in sorted(folder.glob('*.png')):
        target = original.with_suffix('.webp')
        with Image.open(original) as image:
            rgba = image.convert('RGBA')
            rgba.save(target, format='WEBP', lossless=True, method=6, exact=True)
        with Image.open(target) as decoded:
            assert decoded.convert('RGBA').tobytes() == rgba.tobytes(), target
        conversions.append(dict(png=str(original), png_sha256=sha(original),
                                webp=str(target), webp_sha256=sha(target), exact_rgba=True))
    (folder / 'webp_viewing_manifest.json').write_text(
        json.dumps(conversions, ensure_ascii=False, indent=2), encoding='utf8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-sha', required=True)
    options = parser.parse_args()
    source = ART / 'axel_guild_repaired.glb'
    manifest = load(ART / 'repair_manifest.json')
    assert sha(source) == options.expected_sha == manifest['final_sha256']
    unchanged = [dict(asset_id='guild_alarm_tower', **manifest['tower']), *manifest['library']]
    for row in unchanged:
        assert sha(row['path']) == row['sha256']
        previous = load(OUT / 'acceptance' / (row['asset_id'] + '.json'))
        assert previous['source_sha256'] == row['sha256'], row['asset_id']
    # Preserve former CPU evidence before refreshing its current-source record.
    history = OUT / 'history' / ('before_main_patch_' + time.strftime('%Y%m%d_%H%M%S'))
    history.mkdir(parents=True, exist_ok=True)
    for relative in ['resource_audit/axel_guild_repaired.json', 'resource_audit/index.json']:
        path = OUT / relative
        if path.is_file():
            shutil.copy2(path, history / path.name)
    cpu = subprocess.run([sys.executable, 'tools/audit_guild_reference_resources.py'], cwd=ROOT,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    (OUT / 'accepted_main_patch_resource.log').write_bytes(cpu.stdout)
    print('END accepted_main_patch_resource', cpu.returncode, flush=True)
    if cpu.returncode:
        return cpu.returncode
    imported_dir = OUT / 'accepted_main_patch_import'
    gpu('accepted_main_patch_import', 'res://tools/test_guild_reference_import.gd', [
        f'--source-dir={ART.as_posix()}', f'--out={imported_dir.as_posix()}',
        '--only=axel_guild_repaired', '--isolated-content'])
    imports = load(imported_dir / 'import_report.json')
    assert imports['passed'] and imports['completed'] and len(imports['items']) == 1
    item = imports['items'][0]
    assert item['input_sha'] == options.expected_sha and item['passed'] and item['http_passed']
    runtime_dir = OUT / 'accepted_main_patch_runtime'
    gpu('accepted_main_patch_runtime', 'res://tools/test_guild_repaired_runtime.gd', [
        f'--source={item["output_path"]}', f'--content-root={imports["content_root"]}',
        f'--out={runtime_dir.as_posix()}'])
    runtime = load(runtime_dir / 'runtime.json')
    assert runtime['passed'] and runtime['source_sha'] == options.expected_sha
    webp_gallery(runtime_dir)
    gallery_dir = OUT / 'accepted_main_patch_building'
    gpu('accepted_main_patch_building', 'res://tools/review_guild_reference_camera.gd', [
        f'--source={source.as_posix()}', '--kind=building', f'--out={gallery_dir.as_posix()}',
        '--views=near,entry_closed,lantern_detail,lantern_detail_night,hall_night,rose_backlight,crystal_front,stone_raking'])
    gallery = load(gallery_dir / 'report.json')
    assert gallery['passed'] and gallery['gallery_completed'] and gallery['identity']['sha256'] == options.expected_sha
    webp_gallery(gallery_dir)
    args = [f'--source={source.as_posix()}', f'--candidate={source.as_posix()}', f'--out={OPT.as_posix()}']
    for case in ['baseline', 'candidate']:
        gpu('main_patch_opt_' + case, 'res://tools/review_guild_reference_optimization.gd', args + [f'--case={case}'])
        webp_gallery(OPT / case)
    compared = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '--script',
                               'res://tools/review_guild_reference_optimization.gd', '--',
                               *args, '--case=compare'], cwd=ROOT, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=180)
    (OUT / 'main_patch_opt_compare.log').write_bytes(compared.stdout)
    print('END main_patch_opt_compare', compared.returncode, flush=True)
    if compared.returncode:
        return compared.returncode
    assert load(OPT / 'compare.json')['passed']
    assert sha(source) == options.expected_sha
    for row in unchanged:
        assert sha(row['path']) == row['sha256']
    print('MAIN_PATCH_AUTOMATIC_CHECKS_COMPLETE manual A/B verdict still required', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
