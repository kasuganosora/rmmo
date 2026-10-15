"""Prepare the completed candidate's actual captures for quality-90 review."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil

OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')
HELPER = Path('C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py')

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    build_path = OUT / 'build.json'
    build = json.loads(build_path.read_text(encoding='utf8'))
    assert build['phase'] == 'candidate_complete' and build['failures'] == 0
    assert sha(build['candidate']) == build['candidate_sha256']
    spec = importlib.util.spec_from_file_location('review_image', HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    directory = OUT / 'scene_reviews' / (build['candidate_sha256'][:12] + '-' + sha(build_path)[:10])
    directory.mkdir(parents=True, exist_ok=True)
    images = []
    for capture in build['images']:
        source = Path(capture['path'])
        assert sha(source) == capture['sha256'], f'Stale capture: {source}'
        target = directory / source.name
        existing = helper.verified_receipt(target) if target.is_file() else {}
        if not (existing.get('source_sha256') == capture['sha256'] and helper.same_encoding(existing, False, 90)):
            shutil.copyfile(source, target)
        receipt = helper.prepare(target, quality=90)
        images.append({'path': str(target), 'sha256': receipt['sha256'], 'quality': 90,
                       'reviewed': False, 'camera': capture['camera'],
                       'source_path': str(source), 'source_sha256': capture['sha256']})
    result = {'candidate_sha256': build['candidate_sha256'], 'build_sha256': sha(build_path),
              'images': images, 'visual_acceptance': 'pending actual visual review'}
    path = OUT / 'scene_review_images.json'
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({'report': str(path), 'directory': str(directory), 'images': len(images)}))

if __name__ == '__main__':
    main()
