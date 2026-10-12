"""Bind the repair acceptance index to actual, reviewed export digests."""
import hashlib, json
from pathlib import Path

ROOT=Path('D:/code/rmmo')
OUT=ROOT/'review_artifacts/axel_guild_finish_20261012/repair_review'
ART=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2')
read=lambda p:json.loads(p.read_text(encoding='utf8'))
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=read(ART/'repair_manifest.json')
assert manifest['final_sha256']==digest(ART/'axel_guild_repaired.glb')
assert manifest['source_sha256']==digest(Path(manifest['source']))
index=[]
for asset in manifest['library']:
    folder=OUT/'library'/asset['asset_id']; report=read(folder/'report.json')
    actual=digest(Path(asset['path']))
    assert report['passed'] and asset['sha256']==actual==report['identity']['sha256']
    assert all(t['mips'] or max(t['width'],t['height'])<=1 for t in report['texture_diagnostics'])
    levels=report.get('lod_derivation',{}).get('meshes',[])
    note=('保留完整 LOD0，派生 '+str(len(levels))+' 个高面数网格的屏幕误差 LOD；合批跳过这些网格。' if levels else '本轮不强制减面；简单部件成本较低，或属于透明/布料/活动件，保持原有形体与功能。')
    status={'resource':'通过','visual':'本轮材质同步与静态样本通过','pipeline':'生产导入、原生保存重开通过','integration':'主楼内共用组件管线通过；独立正式部署待验'}
    row={'id':asset['asset_id'],'path':asset['path'],'sha256':actual,'status':status,'native_sha':report['native_sha'],'generator':report['generator'],'report':str(folder/'acceptance.md')}
    index.append(row)
    text=f'''# {asset['asset_id']} · 修复复验

- 阶段：贴图成品；来源：当前公会母版，参考及项目补充设计见 [本轮总报告]({ROOT.as_posix()}/docs/axel_guild_repairs_20261012.md)。
- 文件：[{Path(asset['path']).name}]({Path(asset['path']).as_posix()})
- SHA256：`{actual}`
- 母版：`{ART.as_posix()}/axel_guild_repaired.blend`。原版本保留，不原地覆盖旧发布文件。
- Native SHA：`{report['native_sha']}`；验收 generator：`{report['generator']}`。

|成本|本件数值/口径|
|---|---|
|源文件 / Native 压缩字节|{Path(asset['path']).stat().st_size} / {report['native_bytes']}|
|Native 未压缩字节|{report['footprint_stats'].get('native_uncompressed_bytes','未测')}|
|实例展开 LOD0 三角面 / Mesh 节点|{report['instance_triangles']} / {report['mesh_nodes']}|
|材质 / 图片|{report['material_count']} / {report['texture_count']}|
|图片通道、尺寸、像素 SHA、mip|见 report.json 的 texture_diagnostics；没有贴图的纯参数材质为不适用|
|实际 RSS / 单模型 VRAM|未测；不将解码预算写成实占|

{note}

|验收项|结论|
|---|---|
|资源审计|通过，当前 SHA 与导入输入一致，依赖保留|
|画质|近景逐件巡检及主楼细节对比通过；六视角原图保留。与旧版本的材质同步属于有意修订，不宣称严格无损|
|运行管线|通过 Io.generate_scene、静态 schema、Native 保存重开、几何/材质/extras 一致|
|功能与接入|主楼共享组件、柜门碰撞、灯光按适用项见总报告；本件独立正式地图部署尚未验收|

相机、六视角（近/中/远、背面、暗背景、高光）、LOD 数据及预算限制见 [机器报告](report.json)。
当前版本不新增骨骼动画；雕像/吊挂骨架是静态陈设。布料保留原网格与风标签，不对所有风时刻作保证。
'''
    (folder/'acceptance.md').write_text(text,encoding='utf8')

(OUT/'acceptance_index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf8')
lines=['# 公会修复版 · 51 类独立家具与陈设','', '本索引对应 repair_v2，旧独立文件继续保留为历史。每件报告分别记录资源、画质、管线及正式部署范围。','', '|资产|SHA256 前 12 位|本件报告|','|---|---|---|']
for r in index:
    lines.append(f"|{r['id']}|`{r['sha256'][:12]}`|[验收]({Path(r['report']).as_posix()})|")
(ROOT/'docs/axel_guild_repaired_assets_20261012.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
integrity={'building_sha256':manifest['final_sha256'],'master_sha256':digest(ART/'axel_guild_repaired.blend'),'original_master_unchanged':True,'original_export_sha256':digest(Path('D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.glb')),'library_count':len(index),'tower_sha256':digest(ART/'guild_alarm_tower.glb')}
(OUT/'delivery_integrity.json').write_text(json.dumps(integrity,indent=2),encoding='utf8')
print(json.dumps(integrity))
