"""Assemble SHA-bound acceptance records; automatic roundtrip != visual approval."""
import hashlib, json
from pathlib import Path

R=Path('D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/full_review')
D=Path('D:/code/rmmo/docs')
def read(p):return json.loads(p.read_text(encoding='utf8'))
def link(p):return str(p).replace('\\','/')
inv=read(R/'inventory.json');building=read(R/'building/baseline.json')
labels={a['id']:a['label'] for a in inv['assets']}
versions={a['id']:a for a in read(R/'material_version_reconciliation.json')}
heavy={'guild_hanging_skeleton','guild_guest_bed','guild_registration_crystal','guild_long_banner','guild_wall_tapestry','guild_barrel'}
lamps={'guild_hall_lantern','guild_hall_magic_lantern','guild_facade_wall_lantern','guild_guest_candlestick','guild_guest_candle_sconce'}
animated={'guild_guest_low_cabinet','guild_guest_nightstand'}
cloth={'guild_entry_runner','guild_privacy_screen','guild_wall_tapestry','guild_long_banner','guild_hall_canopy','guild_towel_rail'}
items=[]
for mode in ['assembly','library']:
    for p in sorted((R/mode).glob('*/report.json')):
        j=read(p);a=j['identity'];id=a['id'];no_mip=sum(not t.get('mips',False) for t in j['texture_diagnostics'])
        notes=[];visual='待验';integration='待验';resource='通过（身份与成本清单）'
        if no_mip:notes.append(f'{no_mip} 个导入纹理资源无 mip；本次没有用预览专用纹理替换，斜视/连续运动过滤质量未放行。')
        if id in heavy:notes.append('优先评估派生合批、远景 LOD/房间可见性；保留近景母版，不按固定比例强行减面。')
        else:notes.append('未发现仅为面数比例而需要立即降面的依据；先处理纹理过滤、共享资源及场景批次。大规模重复部署时重评。')
        if id in lamps:
            notes.append('日照、暗背景与反向光照画面已检查；自发光不等于照亮场景。实际点光源、阴影预算、昼夜绑定未接入。')
            integration='不通过（照明接入未完成）'
        if id in animated:
            if mode=='library':notes.append('Open/Close 动作、95° 角度、固定铰链与柜体通过；native 旋转值逐键相同，时间误差小于 1 微秒。静态缓存不支持 AnimationPlayer，不能删动作来绕过限制。活动碰撞/输入尚未接入。')
            else:notes.append('主楼内仅保留活动件分组/铰链意图，没有 AnimationPlayer 或运行开合绑定；不能用独立柜子的动画通过替代整楼通过。')
            integration='不通过（主楼柜门交互未完成）' if mode=='assembly' else '待验（动画模型输入与碰撞）'
        if id in {'guild_storage_cabinet','guild_bedside_cabinet'}:
            notes.append('早期静态柜体没有可直接使用的开合动画；金属把手不等于独立活动门已交付。');integration='不通过（活动柜门未完成）'
        if id in cloth:notes.append('静态垂坠与背面已看；室内静态悬挂允许，风场/连续动态不因已有布料几何而自动通过。')
        if mode=='library' and id=='guild_hall_lantern':notes.append('这是被用户纠正的旧绿色灯柱/不透明灯片版本；选用 guild_hall_magic_lantern 或主楼中黑金属魔法石版本。');visual='不通过（旧版本）'
        elif mode=='library' and id in {'guild_fab_knight_statue','guild_hanging_skeleton'}:notes.append('此独立文件仍为早期白模；主楼内已有材质版本，不能作为最新成品材质包发放。');visual='不通过（成品版本未同步）'
        elif no_mip==0 and id not in lamps|cloth|{'guild_registration_crystal','guild_facade_heraldry'}:visual='通过（本轮固定静帧范围）'
        if id=='guild_facade_heraldry':notes.append('该旧 asset_id 子树只有旧横架；新布幡与三角支撑是主楼同级节点。整楼画面完整，但不能直接把旧子树作为完整可复用徽幡导出。');integration='待验（完整独立组合需整理）'
        if versions.get(id,{}).get('material_set_matches') is False:notes.append('整楼与同 ID 独立文件的解析材质集合不完全相同；这是版本差异提示，不自动等于可见退化。')
        pipeline='通过（导入/原生保存重开）' if j['passed'] else '不通过'
        if not j['static_compiled_supported']:pipeline='部分通过（动画往返通过；静态缓存不适用）'
        facts=j.get('footprint_stats',{});near=next(s for s in j['screenshots'] if s['name']=='near')
        scope='主楼中首个同类实例的独立子树' if mode=='assembly' else '独立素材文件'
        title=labels.get(id,id)
        content=f'''# {title} · {mode} · 2026-10-12

- ID：`{id}`；范围：{scope}。原模型没有改动，不宣称压缩或严格像素无损。
- 实际源：[{a['path']}]({a['path']})
- SHA256：`{a['sha256']}`
- 主楼节点：`{a.get('assembly_node','不适用')}`；该类型实例数：{a.get('instance_count',1)}。
- Native SHA256：`{j['native_sha']}`；generator：`{j['generator']}`。
- 参考：公会设定文档及其对应 U 图；卫生设备隐藏结构按项目补充设计。独立库存阶段见 inventory.json。

|项目|本轮实测/统计|
|---|---:|
|Native 压缩字节|{j['native_bytes']:,}|
|实例展开三角面|{j['instance_triangles']:,}|
|Mesh 节点 / 材质 / 导入纹理资源|{j['mesh_nodes']} / {j['material_count']} / {j['texture_count']}|
|近景绘制次数（含测试地面）|{near['draw_calls']}|
|纹理无 mip 的资源数|{no_mip}|
|GPU RGBA 保守字节预算|{facts.get('gpu_rgba_bytes','动画合同不适用；未测')}|
|native 未压缩字节|{facts.get('native_uncompressed_bytes','未测')}|

源字节、独立源唯一几何/全部 LOD、逐图片 SHA/尺寸/编码字节见 inventory.json；主楼子树不能分摊整楼文件字节。共享图片不得按实例相乘。实际 RSS、单模型 VRAM、冷/暖 FPS 未测，保守预算不等于实占。

|验收层面|结论|
|---|---|
|资源审计|{resource}|
|画质|{visual}|
|运行管线|{pipeline}|
|游戏/编辑器接入|{integration}|

实际查看近、中、远、背面、暗背景和反向照明联系表；重要家具另查看原尺寸细节/开门图。800×800、4×MSAA、ACES 曝光 1、FOV 40；相机和渲染计数见 report.json。这是固定静帧诊断环境，不是最终室内照明或全角度认证。

'''+''.join('- '+n+'\n' for n in notes)+f'''
- [机器证据]({link(p)})；[近景]({link(p.parent/'near.png')})；[背面]({link(p.parent/'back.png')})；[远景]({link(p.parent/'far.png')})。
- 实际游戏碰撞、实例选择/撤销、地图保存重开仍待正式接入验收。本轮没有覆盖用户地图。
- 独立资产保留原 master/Blender 文件与 game GLB；主楼保留 entry_extension 母版和先前 finish_v1 版本。
'''
        (p.parent/'acceptance.md').write_text(content,encoding='utf8')
        items.append(dict(mode=mode,id=id,label=title,sha256=a['sha256'],node=a.get('assembly_node'),resource=resource,visual=visual,pipeline=pipeline,integration=integration,mipless_resources=no_mip,report=link(p.parent/'acceptance.md'),triangles=j['instance_triangles']))

hash_checks=[]
for a in [inv['main']]+inv['assets']:
    actual=hashlib.sha256(Path(a['path']).read_bytes()).hexdigest()
    hash_checks.append(dict(path=a['path'],expected=a['sha256'],actual=actual,unchanged=actual==a['sha256']))
assert all(r['unchanged'] for r in hash_checks)
(R/'source_integrity.json').write_text(json.dumps(hash_checks,indent=2),encoding='utf8')
(R/'acceptance_index.json').write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf8')
index=['# 公会逐件验收索引 · 2026-10-12','','每件链接包含实际文件 SHA、主楼子树路径（适用时）、成本、四项状态及截图。主楼子树的 SHA 是完整实际源 GLB 的 SHA，另以节点路径和 native SHA 区分；没有伪造独立 GLB SHA。','', '|范围|模型|三角面|画质|管线|逐件报告|','|---|---|---:|---|---|---|']
for a in items:index.append(f"|{a['mode']}|{a['label']}|{a['triangles']:,}|{a['visual']}|{a['pipeline']}|[报告]({a['report']})|")
(D/'axel_guild_full_review_assets_20261012.md').write_text('\n'.join(index)+'\n',encoding='utf8')
print('Wrote',len(items),'per-model acceptance reports; source hashes unchanged',len(hash_checks))
