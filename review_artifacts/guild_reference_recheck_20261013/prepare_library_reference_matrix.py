"""Read-only resource inventory and independent reference review scaffold.

Only writes this review directory. No model edits, GPU or formal library import.
"""
import ast
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path('D:/code/rmmo')
BASE = ROOT / 'review_artifacts/guild_reference_recheck_20261013'
OLD = ROOT / 'review_artifacts/axel_guild_finish_20261012/repair_review'
SOURCE = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
OUTPUT = BASE / 'independent_library_review'


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20+length]), data


def digest(data):
    return hashlib.sha256(data).hexdigest()


def functional_signature(doc):
    """Node identity, placement, groups and hinge/light/wind contracts; no colour."""
    rows = []
    for node in doc.get('nodes', []):
        extra = node.get('extras', {})
        selected = {k: v for k, v in extra.items() if any(word in k.lower() for word in
                    ('hinge', 'door_', 'fixture', 'wind', 'light', 'collision'))}
        if not selected:
            continue
        rows.append({'name': node.get('name'), 'extras': selected,
                     'matrix': node.get('matrix'), 'translation': node.get('translation'),
                     'rotation': node.get('rotation'), 'scale': node.get('scale')})
    return {'sha256': digest(json.dumps(rows, sort_keys=True).encode()), 'nodes': rows}


def main():
    OUTPUT.mkdir(exist_ok=True)
    catalog = {}
    for module in ['axel_guild_furniture.py', 'axel_guild_furnishings.py',
                   'axel_guild_guestroom.py', 'axel_guild_textiles_sanitary.py']:
        for node in ast.parse((ROOT/'tools'/module).read_text(encoding='utf-8')).body:
            if isinstance(node, ast.Assign) and any(isinstance(n, ast.Name) and n.id == 'ASSETS' for n in node.targets):
                catalog.update({'guild_'+k: v for k, v in ast.literal_eval(node.value).items()})
    catalog.update({
        'guild_facade_heraldry': ('门面公会布幡', 'U00,U01,U19,U33'),
        'guild_facade_wall_lantern': ('入口壁灯', 'U19,U35; 用户暖白菱形魔法石修正'),
        'guild_entrance_crescent_standard': ('入口月牙徽饰立杆', 'U19,U35'),
        'guild_statue_decorative_panel': ('雕像两侧薄装饰板', 'U03,U05,U14; 用户金属圆环修正'),
        'guild_hanging_skeleton': ('吊挂骨架', 'U04,U18; 未展示解剖为项目补充设计'),
        'guild_fab_knight_statue': ('Fab 持剑骑士雕像', 'U05,U18; 用户明确接受 Fab 替代'),
    })
    reference_manifest = json.loads((ROOT/'docs/references/axel_guild_plan_20261007/manifest.json').read_text(encoding='utf-8'))
    refpaths = {x['id']: str(ROOT/'docs/references/axel_guild_plan_20261007'/x['file']) for x in reference_manifest['files']}
    manifest = json.loads((SOURCE/'repair_manifest.json').read_text(encoding='utf-8'))
    old_runtime = json.loads((OLD/'runtime.json').read_text(encoding='utf-8'))
    rows = []
    for item in manifest['library']:
        aid = item['asset_id']
        doc, data = read_glb(Path(item['path']))
        olddoc, olddata = read_glb(Path(str(item['path']).replace('repair_v3', 'repair_v2')))
        title, refs = catalog[aid]
        activities = []
        if item.get('hinge_members'):
            activities.append('柜门关闭/半开/全开/复位；金属件跟随；碰撞随动')
        if aid in ('guild_hall_lantern', 'guild_facade_wall_lantern', 'guild_guest_candlestick', 'guild_guest_candle_sconce'):
            activities.append('灯光插槽、夜间发光、邻近真光与阴影预算；外墙灯昼夜切换')
        if aid in ('guild_facade_heraldry', 'guild_long_banner', 'guild_wall_tapestry', 'guild_towel_rail'):
            activities.append('布料固定边、双面/厚度、适用风标签；不默认静态图证明风场')
        oldsig, newsig = functional_signature(olddoc), functional_signature(doc)
        unchanged = data == olddata
        reuse = '无本件适用活动件；静态外观另验'
        if activities:
            reuse = ('资源逐字节未变；旧原生报告可引用同资源证据，仍需确认当前 generator/合同兼容。'
                     if unchanged else '源资源已变；旧报告只作共享合同背景，当前资源运行状态待验。')
        if item.get('hinge_members'):
            reuse += ' 旧 runtime.json 是整楼 24 柜门运行证据；独立旧报告动画数组为空，不是独立柜门动作实测。'
        row = {
            'asset_id': aid, 'name': title, 'references': refs,
            'reference_paths': {r: refpaths[r] for r in re.findall(r'U\d+', refs) if r in refpaths},
            'source': item['path'], 'actual_sha256_at_inventory': digest(data),
            'manifest_sha256': item['sha256'], 'manifest_matches': digest(data) == item['sha256'],
            'previous_sha256': digest(olddata), 'unchanged_bytes_from_v2': unchanged,
            'reference_changed': item.get('reference_changed', False),
            'functional_signature_equal_v2': oldsig['sha256'] == newsig['sha256'],
            'functional_signature_v3': newsig,
            'old_native_report': str(OLD/'library'/aid/'report.json'),
            'old_runtime_source_sha': old_runtime['source_sha'],
            'activity_checks': activities, 'evidence_reuse_limit': reuse,
            'final_gallery': str(BASE/'final_library'/aid),
            'visual_status': '待最终新图逐件目视验收',
            'resource_status': '库存快照，待总装确认最终 SHA 与本件新 report.json',
            'pipeline_status': '待本件新 Native 导入/保存重开证据',
            'runtime_status': '待适用活动项核验' if activities else '无活动项；静态碰撞/语义待新报告',
            'integration_status': '正式内容编辑器/地图部署尚未在此验收',
            'viewed_images': [], 'observations': [],
        }
        # Keep human review separate; preparation never silently labels images passed.
        (OUTPUT/(aid+'.json')).write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf-8')
        rows.append(row)
    (OUTPUT/'matrix.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['# 51 件公会独立资产：参考与最终验收矩阵', '',
             '本表是最终画廊生成前的准备快照，所有最终画质状态均为待验。旧图、旧 SHA 和旧“通过”不替代当前输出。'
             '后续逐件结论记录实际查看的新图路径及其对应 source SHA。', '',
             '|资产|参考/依据|本轮源变化|活动/专项|最终目视|', '|---|---|---|---|---|']
    for r in rows:
        lines.append(f"|{r['asset_id']} · {r['name']}|{r['references']}|{'未变' if r['unchanged_bytes_from_v2'] else '有变'}|{'; '.join(r['activity_checks']) or '静态陈设'}|待验|")
    lines += ['', '## 旧活动件证据边界', '',
              '旧 `runtime.json` 的源 SHA 是 `'+old_runtime['source_sha']+'`，检查了整楼 14 个柜体、24 个柜门在 0/0.5/1 开合与复位时的碰撞随动。'
              '该证据不等于 51 件独立导出的每件都做过动作验收。旧独立柜件 `animation_samples` / `animation_signature` 为空，说明其 glTF 没有动画轨道；运行开合由 rmmo_hinge 合同提供。', '',
              '当前库存中床头柜、客房矮柜若与 repair_v2 字节完全相同，可复用其旧独立原生转换证据；整楼动作仍需确认本轮使用相同组件实现和符合位置/枢轴合同。储物高柜材质重导出改变 SHA，不能仅凭旧 runtime.json 宣称当前成品开合通过。', '',
              '织物静态图只确认形态/固定件；若需要风场动态通过，须有当前风标签、固定边和多时刻画面/运行证据。灯具静态发光画面也不单独证明夜间真光、阴影限额或昼夜开关。']
    (OUTPUT/'matrix.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(json.dumps({'count': len(rows), 'unchanged': sum(r['unchanged_bytes_from_v2'] for r in rows),
                      'manifest_mismatches': [r['asset_id'] for r in rows if not r['manifest_matches']],
                      'activity': [{k:r[k] for k in ['asset_id','unchanged_bytes_from_v2','functional_signature_equal_v2']} for r in rows if r['activity_checks']]}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
