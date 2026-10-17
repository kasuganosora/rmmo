"""Read-only S2 asset/placement inventory; never edits the map or asset library."""
from pathlib import Path
import hashlib
import json

ROOT = Path('D:/code/rmmo_runtime')
OUT = ROOT / 'review_artifacts/axel_s2_reference_20261017'
ASSETS = ROOT / 'packs/default/assets'

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    identity = read(OUT / 'source/source_identity.json')
    map_path = Path(identity['path'])
    assert sha(map_path) == identity['sha256'], 'Map changed; export a fresh native snapshot first'
    records = read(OUT / 'source/source_records.json')
    metadata = read(OUT / 'source/source_metadata.json')
    library = read(ASSETS / 'library.json')
    labels = ['绿色金丝带彩柱', '蓝色金丝带彩柱', '原木金丝带彩柱',
              '桥头九面长旗', '跨街布彩旗', '古铜旗幡路灯（可换旗·随风）',
              '写实蓝色尖尾墙挂布幡', 'S12 红金短三角墙旗 A', '晾衣绳架',
              '暖砖长花池', '暖砖L形花池', '高灌木长花池',
              '写实阔叶橡树·宽冠粗干', '写实黄杨灌木',
              '写实大团灌木·横向铺展', '门旁暖光小壁灯',
              '写实踏步石·A', '写实踏步石·B', '写实踏步石·C',
              '宽弧桥头草堆·A', '宽弧桥头草堆·C']
    result = {'map': identity, 'library_sha256': sha(ASSETS/'library.json'),
              'scope': 'S2 frontage X 330..385, Z 260..290; counts are source-record presence, not visibility or final placement acceptance',
              'assets': [], 'houses': [], 'formal_map_modified': False}
    for label in labels:
        entries = [r for r in library if r.get('label') == label]
        assets = {}
        for entry in entries:
            if entry.get('asset_path'):
                paths = [entry['asset_path']]
            elif entry.get('prefab_path'):
                prefab = read(ASSETS/entry['prefab_path'])
                paths = [r['asset_path'] for r in prefab['records'] if r.get('asset_path')]
            else:
                paths = []
            for value in paths:
                path = Path(value)
                if not path.is_absolute(): path = ASSETS/path
                assets[path.as_posix()] = {'path': path.as_posix(), 'exists': path.exists(),
                                          'sha256': sha(path) if path.exists() else None}
        names = {Path(p).name for p in assets}
        instances = [r for r in records if Path(r.get('asset_path', '')).name in names]
        local = [r for r in instances if 330 <= r['position'][0] <= 385 and 260 <= r['position'][2] <= 290]
        result['assets'].append({'label': label, 'library_entry_count': len(entries),
                                 'resources': list(assets.values()), 'whole_map_instances': len(instances),
                                 's2_instances': [{'id':r['uuid'],'position':r['position'],'scale':r['size']} for r in local]})
    for house in metadata['town_reference']['house_layout']['placements']:
        if house.get('shot') != 'S2': continue
        p = house['parameters']
        result['houses'].append({k:house[k] for k in ['id','label','building_id','position','entrance','yaw']} |
                                {'floors':p['floors'], 'window_style':p['window_style'],
                                 'gable_oculus':p.get('gable_oculus',False),
                                 'component_count':len(house['component_ids']),
                                 'all_components_present':all(any(r['uuid']==i for r in records) for i in house['component_ids'])})
    result['missing_variants'] = [
        {'id':'yellow_short_cross_street_cloth','status':'delegated_to_blender','reason':'Existing five-color and nine-long-pennant GLBs differ from reference short yellow rectangular cloths'},
        {'id':'wall_to_wall_white_laundry','status':'delegated_to_blender','reason':'Existing laundry GLB has one merged Structure with ground posts; reference uses wall anchors'},
        {'id':'long_yellow_lamp_banner','status':'blender_source_variant_check','reason':'Existing lamp geometry reusable; current cloth material is oxblood, reference uses a long yellow-green panel'}]
    result['visual_review'] = {'reference_complete':False,'placement_complete':False,
                              'reference':'D:/code/rmmo/docs/references/town_required_shots_20261012/03_festival_residential_lane.webp',
                              'runtime_report':str(OUT/'baseline_runtime/result.json'),
                              'observations':['Two pole pairs and residential rows exist; no scene rebuild is justified by a claim they are absent.',
                                              'Both spans currently use the bridge nine-pennant asset.',
                                              'Flag lamps, wall banners, brick planters, wall laundry, stepping stones and street-end foliage are absent from this frontage.',
                                              'Setbacks and the early wide-angle camera leave an open street; the distant wall blocks the center without the reference tree and roof layers.'],
                              'next_order':['receive missing asset handoffs','complete missing object placement','refine only S2 spacing and camera; preserve user S1 edits']}
    assert sha(map_path) == identity['sha256']
    path = OUT/'inventory.json'
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'report':str(path),'houses':len(result['houses']),'assets':len(result['assets']),
                      'missing_files':[a['path'] for row in result['assets'] for a in row['resources'] if not a['exists']],
                      'map_unchanged':True},ensure_ascii=False))

if __name__ == '__main__': main()
