"""Record already-viewed lighting images without changing model/source resources."""
import hashlib
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

report_path = BASE / 'accepted_lighting/report.json'
report = json.loads(report_path.read_text(encoding='utf-8'))
observations = {
    'entry_closed_still.png': '入口石墙、木门及浅石门框的阴影边界都有相同交叉采样纹，跨材质出现。',
    'entry_closed_no_ssao_still.png': '关闭 SSAO 后上述网纹仍然存在。',
    'entry_closed_no_sun_shadow_still.png': '仅关闭太阳阴影后网纹消失；证明问题位于方向光阴影，不据此改坏源 PBR 纹理。',
    'lantern_detail_night_still.png': '墙体现在得到连续暖光；内部顶盖、底座受光合理，原菱石自身遮挡导致的三角亮斑消失。保留框架、顶盖遮挡。',
    'hall_night_still.png': '大厅近灯桌边、地面出现暖光；夜间整体仍较暗，但自发光石体不再堵住真实点光。'
}
evidence = {
    'source_identity': report['identity'],
    'report_path': str(report_path),
    'report_sha256': sha(report_path),
    'runtime_implementation': report['runtime_implementation'],
    'actual_viewed_images': [dict(path=str(BASE/'accepted_lighting'/name), sha256=sha(BASE/'accepted_lighting'/name), actually_viewed=True, observation=observation) for name, observation in observations.items()],
    'self_shadow_status': '通过：受控闭合发光石体自遮挡修复的 CPU 合同及整楼 GPU 实图；冻结 GLB 未修改。',
    'headless_regression': {'path': str(BASE/'socket_shadow_regression.json'), 'sha256': sha(BASE/'socket_shadow_regression.json'), 'passed_checks': 20},
    'whole_building_inventory': {'path': str(BASE/'whole_building_socket_shadows.json'), 'sha256': sha(BASE/'whole_building_socket_shadows.json'), 'changed_stones': 8, 'hall': 6, 'facade': 2, 'other_candle_sockets': 8},
    'limitations': ['昼夜灯池预算及完整活动柜门运行证明仍由当前源运行专项汇总。', '入口日光终图需改进测试方向光阴影采样后重拍；关阴影图仅作定位，不作为有完整投影的最终验收图。', '此记录不代表正式内容库或地图部署。']
}
(BASE/'lighting_visual_recheck.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
lines = ['# 菱石灯自投影与入口阴影复验', '', evidence['self_shadow_status'], '', f"整楼源 SHA256：`{report['identity']['sha256']}`。运行实现 SHA 见同名 JSON。", '', '整楼实际是 6 枚大厅菱石 + 2 枚门口菱石，共 8 枚；另 8 个为蜡烛 socket。只改变全材质发光、严格包含有效 socket 的闭合实体投影，金属框与玻璃保持原状态。共享资源、流式重建及派生合批语义不变；缺材质、边界、开壳、空心和混合材质保守保留。20 项 headless 回归通过。', '']
for row in evidence['actual_viewed_images']:
    lines += [f"- [{Path(row['path']).name}]({Path(row['path']).as_posix()})：{row['observation']} SHA256 `{row['sha256']}`"]
lines += ['', *['- '+s for s in evidence['limitations']], '']
(BASE/'lighting_visual_recheck.md').write_text('\n'.join(lines), encoding='utf-8')

# Keep the original independent day/night gallery evidence intact. Append the
# corrective runtime evidence rather than relabeling old blocked-light images.
for asset_id in ['guild_hall_lantern', 'guild_facade_wall_lantern']:
    path = BASE/'independent_library_review'/f'{asset_id}.json'
    asset = json.loads(path.read_text(encoding='utf-8'))
    asset['light_self_shadow_recheck'] = {'path':str(BASE/'lighting_visual_recheck.json'), 'sha256':sha(BASE/'lighting_visual_recheck.json'), 'status':evidence['self_shadow_status']}
    asset['runtime_status'] = '菱石自投影修复：20 项 CPU 回归和当前源整楼夜景通过；昼夜灯池/预算最终运行报告待汇总。'
    path.write_text(json.dumps(asset, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    md = path.with_suffix('.md')
    content = md.read_text(encoding='utf-8')
    mark = '\n## 菱石灯运行修复复验\n'
    content = content.split(mark)[0]
    content += mark+'\n'+asset['runtime_status']+'\n\n[修复及实图证据]('+ (BASE/'lighting_visual_recheck.md').as_posix()+')。原独立夜景保留原观察，不将旧截图改称修复后图。\n'
    md.write_text(content, encoding='utf-8')
print('Recorded five actually-viewed lighting images, 8 stone self-shadow exclusions, 2 affected independent reports.')
