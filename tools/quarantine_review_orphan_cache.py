"""Apply the frozen orphan-only cache plan reversibly; never delete files."""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path('D:/code/rmmo')
PLAN = ROOT / 'review_artifacts/guild_formal_import_20261013/cache_preflight.json'
CACHE = Path('D:/code/rmmo_runtime/cache/world3d/compiled_assets_v1').resolve()
DEST = Path('D:/code/rmmo_runtime/review_artifacts/guild_formal_import_20261013/orphan_native_quarantine').resolve()
JOURNAL = ROOT / 'review_artifacts/guild_formal_import_20261013/cache_quarantine_receipt.json'


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def main():
    plan = json.loads(PLAN.read_text(encoding='utf-8'))
    assert Path(plan['cache_root']).resolve() == CACHE
    assert Path(plan['quarantine_root']).resolve() == DEST
    assert not JOURNAL.exists(), 'Do not overwrite a completed/partial movement receipt'
    expected_meta = {str(Path(r['path']).resolve()): r for r in plan['metadata_guard']}

    def guard_metadata():
        files = {str(p.resolve()): p for p in CACHE.rglob('*') if p.is_file() and p.suffix != '.scn'}
        assert set(files) == set(expected_meta), 'Cache metadata changed; stop and re-audit'
        referenced = set()

        def walk(v):
            if isinstance(v, dict):
                for k, value in v.items():
                    if k == 'payload_sha':
                        referenced.add(value)
                    walk(value)
            elif isinstance(v, list):
                for value in v:
                    walk(value)

        for key, p in files.items():
            assert p.stat().st_size == expected_meta[key]['bytes'] and sha(p) == expected_meta[key]['sha256'], 'Changed cache metadata'
            walk(json.loads(p.read_text(encoding='utf-8-sig')))
        return referenced

    referenced = guard_metadata()
    actual = {p.name: p.stat().st_size for p in CACHE.glob('*.scn')}
    expected = {r['name']: r['bytes'] for r in plan['payload_listing_guard']}
    assert actual == expected, 'Payload list changed since audit'
    for row in plan['selected_payloads']:
        src, dst = Path(row['path']).resolve(), Path(row['destination']).resolve()
        assert src.parent == CACHE and dst.parent == DEST and src.name == dst.name
        assert src.suffix == '.scn' and src.stem == row['sha256'] and src.stem not in referenced
        assert not src.is_symlink() and not dst.exists()
        assert src.stat().st_size == row['bytes'] and sha(src) == row['sha256']
    # No writes take place until the whole concrete source/destination set is validated.
    DEST.mkdir(parents=True, exist_ok=True)
    receipt = {'plan': str(PLAN), 'plan_sha256': sha(PLAN), 'mode': 'reversible orphan payload quarantine; no deletion', 'moved': [], 'completed': False}

    def persist():
        tmp = JOURNAL.with_suffix('.tmp')
        tmp.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        os.replace(tmp, JOURNAL)

    persist()
    for row in plan['selected_payloads']:
        referenced = guard_metadata()
        src, dst = Path(row['path']).resolve(), Path(row['destination']).resolve()
        assert src.stem not in referenced and not dst.exists()
        assert src.stat().st_size == row['bytes'] and sha(src) == row['sha256']
        src.rename(dst)  # Same-volume, explicit single-file move; Windows refuses overwrite.
        assert sha(dst) == row['sha256']
        receipt['moved'].append(row)
        persist()
    guard_metadata()
    receipt['completed'] = True
    receipt['moved_bytes'] = sum(r['bytes'] for r in receipt['moved'])
    receipt['remaining_cache_bytes'] = sum(p.stat().st_size for p in CACHE.glob('*.scn'))
    receipt['free_cache_bytes'] = plan['cache_limit_bytes'] - receipt['remaining_cache_bytes']
    persist()
    print(json.dumps({k: receipt[k] for k in ['completed', 'moved_bytes', 'remaining_cache_bytes', 'free_cache_bytes']}))


if __name__ == '__main__':
    main()
