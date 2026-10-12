from pathlib import Path
import json

HERE=Path(__file__).resolve().parent
j=json.loads((HERE/'inventory_report.json').read_text(encoding='utf-8'))
s=json.loads((HERE/'inventory_secondary_summary.json').read_text(encoding='utf-8'))
priorities=[
 ('bridge_long','P0','桥街长彩旗','用户指定优先；9千面却264 MiB解压像素；实际等待2.06 s'),
 ('42028074','P0','StreetSpire 街道尖塔','408 MiB源、2.28 s剩余等待；先删历史数据及字节重复'),
 ('9ba5457e','P0','橡树组合','210 MiB源、1.99 s剩余等待；先删导出冗余'),
 ('ca8df548','P1','圆灌木','1.77 GiB准入、7实例、1.13 s剩余等待'),
 ('06d99753','P1','Foliage','3,674面但1.75 GiB准入；优先纹理尺寸/通道'),
 ('47fd0e87','P1','铺展灌木','1.78 GiB准入、6实例；与其它灌木纹理相同'),
 ('afbfc8ac','P1','高灌木','1.77 GiB准入；与其它灌木纹理相同'),
 ('83c1f150','P1','蓝色墙挂长幡','143 MiB简单布幡、0.79 s剩余等待；无损候选已产出'),
 ('389bb6a0','P1','花园中柱','143 MiB/4,712面、1.00 s剩余等待；无损候选已产出'),
 ('b3d6babb','P1','花园墙240','144 MiB、29实例；无损候选已产出'),
 ('510592a4','P1','花园高柱','143 MiB/5,024面；无损候选已产出'),
 ('c9c641df','P2','arch_B 草','224实例；查共享图像、LOD/剔除；当前无归属等待样本'),
 ('117f47a0','P2','arch_A 草','206实例；查共享图像、LOD/剔除；当前无归属等待样本'),
 ('2abd3fe0','P2','arch_C 草','201实例；查共享图像、LOD/剔除；当前无归属等待样本'),
 ('5beaac04','P2','Metal/CandleWarm/Goods 物件','3,672面却0.87 GiB准入、27实例；检查纹理通道'),
 ('79b1fdff','P2','PostBody/GoldSilk A','5,212面却0.87 GiB准入；先纹理再几何'),
 ('c20c7887','P2','GoldSilk/PostBody B','5,212面却0.87 GiB准入；先纹理再几何'),
 ('893bd73c','P2','wild_D 草','7实例、0.44 s剩余等待；与wild变体共用图像'),
 ('91ce39fb','P2','wild_C 草','3实例、0.21 s剩余等待；与wild变体共用图像'),
 ('3f3d8298','P2','wild_F 草','2实例、0.11 s剩余等待；与wild变体共用图像'),
 ('f265495a','P2','short_B 草','39实例；先清理未引用图像'),
 ('2528503a','P2','short_C 草','41实例；先清理未引用图像'),
 ('308166ed','P2','short_A 草','11实例；先清理未引用图像'),
 ('c9e7a4d4','P2','wild_A 草','11实例、4,827面；先清理未引用图像'),
 ('537fe3a8','P2','wild_H 草','3实例、4,207面；先清理未引用图像'),
 ('0c878137','P2','wild_E 草','仅2,325面；先清理未引用图像'),
 ('24ac85de','P2','wild_G 草','仅3,469面；先清理未引用图像'),
 ('ad5d4969','P2','wild_B 草','1实例；先清理未引用图像'),
 ('6df0af80','P2','Structure 6df','仅1,584面但34 MiB源；需结合画面识别用途'),
 ('a83439c9','P3','Structure a834','1实例；清理低优先'),
 ('8c3d70c8','P3','Structure 8c3','源仅3.49 MiB；关注0.47 GiB准入口径，需查像素'),
 ('f3088190','P3','路灯/旗幡组合','0.48 MiB、33实例；当前资源大小合理，暂不减面'),
]
lines=['# 当前城镇资源引用与异常体积清单（2026-10-11）','',
       '这是资源侧只读审计与四件独立无损候选记录。没有修改地图、旧hash资产、加载预算、加载代码，也没有运行GPU。',
       '',f"正式地图：`{j['map_path']}`；SHA256 `{j['map_sha256']}`。4,437条记录、1,762个定义；32个native外部模型共897实例、源文件合计2,272.894 MiB，32份源SHA全部与交接一致。",
       '', '## 口径与排序', '',
       'Full peak是加载准入的保守估计，既不是文件大小，也不是实测RSS/VRAM；表中MiB/GiB均二进制单位。三角面是独立mesh数据总量，含已有LOD；不能当成所有距离的实际绘制面数。实例多意味着绘制/剔除/交互压力，不能将文件或共享贴图内存乘实例数。',
       '', '按用户指定彩旗优先、真实B1/B2需求剩余等待、纹理/几何失衡和实例数量人工分级；同级次序是工作建议，并非统计最优调度。等待均值仅使用可归属且达到trace阈值的样本；“未归属”不能写成0秒或已证实没有成本。',
       '', '|序|级别|对象/路径前缀|实例|独立面数|源MiB|full peak GiB|已归属等待ms|判断|',
       '|---:|---|---|---:|---:|---:|---:|---:|---|']
for rank,(prefix,tier,label,why) in enumerate(priorities,1):
    r=next(r for r in j['rows'] if Path(r['path']).name.startswith(prefix))
    w=f"{r['measured_wait_mean_ms']:.1f}" if r['measured_wait_mean_ms'] is not None else '未归属'
    lines.append(f"|{rank}|{tier}|{label} `{prefix}`|{r['instance_count']}|{r['gltf_unique_triangle_count']:,}|{r['source_bytes']/2**20:.2f}|{r['full_peak_estimate_bytes']/2**30:.3f}|{w}|{why}|")
lines += ['', '## 初步无损证据', '',
          '- 32个GLB中，当前默认场景未引用的嵌入图像合计894.962 MiB；另有11.927 MiB活跃引用图像可做字节相同去重。两项不重叠共906.889 MiB，仅是扫描结果，未包含其它孤立bufferView，不代表所有候选已制作或显存下降。',
          '- 24组跨GLB字节完全相同图像；其中14组在多个GLB当前材质中仍被引用，重复文件载荷约224.702 MiB。三种灌木与Foliage、wild草变体、花园石件与尖塔存在同源图像。需要管线级共享或资源打包验证，不能直接宣称运行内存已自动共享。',
          '- 大量图像名有 `_orm`、`_orm2`、`_orm3`、`_normal2` 等导出代际残留，证明先清理依赖及旧buffer比盲目减面更合适。',
          '- 完整路径、源/产品SHA、原footprint、尺寸/通道、所有图像SHA、未引用列表、跨文件重复组、记录UUID、等待样本在 `inventory_report.json`。',
          '', '## 四件新增无损候选', '',
          '保存位置：`D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/secondary/`。使用architecture_lossless.py的保守图解析器；保留全部场景/节点/mesh和引用的材质，不按默认场景删几何。删除未引用资源表、孤立历史buffer以及字节相同别名。完全不重采样、不重编码、不减面。',
          '', '|物件|源MiB|候选MiB|减少MiB|图片表前→后|', '|---|---:|---:|---:|---|']
for r in s:
    lines.append(f"|{r['label']}|{r['source_bytes']/2**20:.2f}|{r['candidate_bytes']/2**20:.2f}|{r['saved_bytes']/2**20:.2f}|{r['source_tables']['images']}→{r['candidate_tables']['images']}|")
lines += ['', f"合计 {sum(r['source_bytes'] for r in s)/2**20:.2f}→{sum(r['candidate_bytes'] for r in s)/2**20:.2f} MiB，减少{sum(r['saved_bytes'] for r in s)/2**20:.2f} MiB。", '',
          '验证全部通过：固定源SHA前后相同；resolved graph完全相同；所有引用accessor与image的bufferView逐字节相同；节点、位姿、extras（含风场/碰撞）、场景、扩展声明完全相同。源图像尺寸及像素不变。逐件audit包含完整映射和SHA。',
          '', '这些收益主要是源文件与SHA读取量下降：native原来已经只保留被引用图片，因此本轮不能把源文件减少百分比当作解压像素或显存下降。待父任务统一做GPU近中远同条件比对、真实导入缓存、footprint、保存重开；当前均未发布。',
          '', '## 32项之外的当前真实依赖', '',
          '- 其余模型为3个石桥路径、5个实例；每个GLB约0.31 MiB。桥实际生成/冻结数据在当前定义中，不按GLB大小冒称整桥成本。五桥也是近期已做专项LOD的对象，本轮没有重复改。',
          '- 当前1,762个定义合计压缩93.739 MiB、解压序列化130.334 MiB。最大的5份是桥定义，分别约4.05、3.60、3.04、2.96、2.91 MiB；之后单定义最大不足0.7 MiB，未发现另一个百MiB单独冻结prefab。它们仍有解析/场景构建成本，不能称已完成所有性能优化。',
          '- 当前材质引用59个唯一外部PNG/JPG路径，文件总216.301 MiB，未发现字节相同文件重复。最大为多个2K RGB法线图（约7–11 MiB），规模与城墙/地形/房屋复用用途大体对应，优先级低于错误累计导出的百MiB小物件。未做像素等价但不同编码的外部图像查重或实际texel density验收。',
          '- 查询只遍历当前地图记录依赖，未扫描/裁剪离线母版、旧地图历史版本或未引用资源库。',
          '', '## 复查入口', '',
          '- `inventory_decode.gd`：headless只读解码当前 `.rmres`，不创建场景、GPU或写地图。',
          '- `inventory_map_definitions.json`：定义摘要与逐记录引用。',
          '- `inventory_audit.py` / `inventory_report.json`：32项完整文件/图像扫描与依赖排名原始数据。',
          '- `inventory_secondary_lossless.py` / `inventory_secondary_summary.json`：四件候选构建与严格校验。',
          '- `inventory_report_md.py`：本报告生成脚本。', '']
(HERE/'inventory_report.md').write_text('\n'.join(lines),encoding='utf-8')
print('Wrote',HERE/'inventory_report.md')
