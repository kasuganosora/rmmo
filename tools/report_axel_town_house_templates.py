"""Report actual native payload identity/cost; never infer visual acceptance."""
from pathlib import Path
import base64
import hashlib
import json
from PIL import Image

OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    index = json.loads((OUT / 'house_templates.json').read_text(encoding='utf8'))
    native = {r['id']: r for r in json.loads((OUT / 'house_template_native_audit.json').read_text(encoding='utf8'))['templates']}
    cache = {}
    reports = []
    for item in index['templates']:
        path = Path(item['loaded_path'])
        source = json.loads(path.read_text(encoding='utf8'))
        audit = native.get(item['id'], {})
        textures = {}
        for mat in audit.get('native_materials', []):
            for key, value in mat.get('paint', {}).items():
                if not key.endswith('_path') or not value:
                    continue
                texture = Path(value)
                if value not in cache:
                    if not texture.is_file():
                        cache[value] = {'missing': True}
                    else:
                        with Image.open(texture) as image:
                            w, h = image.size
                            mip = 0
                            mw, mh = w, h
                            while True:
                                mip += mw * mh * 4
                                if mw == mh == 1:
                                    break
                                mw, mh = max(1, mw // 2), max(1, mh // 2)
                            cache[value] = {'sha256': sha(texture), 'encoded_bytes': texture.stat().st_size,
                                            'width': w, 'height': h, 'source_mode': image.mode,
                                            'rgba8_decode_budget_bytes': w*h*4, 'rgba8_full_mip_budget_bytes': mip}
                textures[value] = cache[value]
        payloads = []
        for r in source['records']:
            if 'house_prefab' not in r:
                continue
            h = r['house_prefab']
            payloads.append({'sha256': h['sha256'], 'compressed_sha256': hashlib.sha256(base64.b64decode(h['data'])).hexdigest(),
                             'compressed_bytes': len(base64.b64decode(h['data'])), 'decoded_bytes': h['length']})
        report = {'id': item['id'], 'source': str(path), 'source_sha256': sha(path), 'native_payloads': payloads,
                  'geometry': {key: audit.get(key) for key in ['render_triangles','render_surfaces','collision_triangles']},
                  'source_parts': item['source_parts'], 'frozen_parts': item['frozen_parts'],
                  'textures': textures, 'unique_rgba8_mip_budget_bytes': sum(t.get('rgba8_full_mip_budget_bytes',0) for t in textures.values()),
                  'lights': audit.get('lights', []), 'door_threshold': item['door_threshold'],
                  'lod_assessment': 'Preserve accepted silhouette and per-floor/roof/active-fixture semantics. No speculative decimation; actual scene timing and distant silhouette required before further LOD.',
                  'stages': {'resource': 'native_decode_identity_cost_passed' if audit and not audit.get('errors') and all(not t.get('missing') for t in textures.values()) else 'pending',
                             'visual': 'pending_root_gpu_review', 'pipeline': 'native_bake_ownership_decode_passed; save_reopen_pending', 'formal_integration': 'pending'},
                  'limits': ['All-storey render totals exclude procedural candle_sconce geometry; lights counted separately.',
                             'Authored frozen surfaces are not runtime draw calls.',
                             'RGBA8 full-mip cost is conservative budget, not measured VRAM/RSS. Shared textures counted once per template, not once per instance.',
                             'New materials and native door revision require exterior GPU review. No repeated indoor tests.']}
        (OUT / 'templates' / (item['id'] + '.review.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2),encoding='utf8')
        reports.append(report)
    (OUT / 'house_template_resource_inventory.json').write_text(json.dumps({'templates': reports, 'shared_textures': cache,
        'all_templates_shared_rgba8_mip_budget_bytes': sum(t.get('rgba8_full_mip_budget_bytes',0) for t in cache.values())},ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'templates':len(reports),'textures':len(cache),'resource_passed':sum(r['stages']['resource'].endswith('passed') for r in reports)}))

if __name__ == '__main__':
    main()
