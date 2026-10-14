"""Bind explicit visual decisions and actual test results to current street SHAs.

This does not decide visual quality or publish any model. Visual pass requires
the manually written decision file and the unchanged images it names.
"""
from pathlib import Path
import hashlib,json

ROOT=Path('D:/code/rmmo')
OUT=ROOT/'review_artifacts/required_street_recheck_20261013'
MANIFEST=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json')

def read(path,default=None):
    return json.loads(Path(path).read_text(encoding='utf-8')) if Path(path).is_file() else default
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def state(status,note,evidence):return {'status':status,'note':note,'evidence':evidence}

def write_reference_report(result):
    labels={'passed':'通过','failed':'未通过','pending':'待验','not_applicable':'不适用'}
    keys=['resource_audit','visual','runtime_pipeline','temporary_editor_integration']
    accepted=sum(all(r['status'][k]['status']=='passed' for k in keys) for r in result)
    lines=[
        '# S10 / S12 新增模型复审（2026-10-13）','',
        f'本批 11 件中，{accepted} 件的资源、画质、运行管线及临时编辑器接入均通过。正式目录/城镇地图尚未发布。每项只采用当前导出 SHA 的证据；完整身份与独立状态见 [逐件验收索引](acceptance/index.json)。','',
        '## 参考与最终修复','',
        '按 `rmmo-model-review` 执行。用户原图入口为 `docs/references/town_required_shots_20261012/` 的 S10 果树院落、S12 浅溪踏石及外挑双柱拱门。原始资料、原母版、原 GLB 与各次回退版本保留；不可见背部、雕饰纹样和游戏通行尺寸是项目补充设计。','',
        '- 外挑双柱拱门保留两柱、柱础、拱券和回墙关系，补背部连接。小型切石替换原不合尺度的岩崖层理，补米制 UV；柱体端盖与侧面分离法线，修复原斜向假阴影。',
        '- 高窄雕饰板保留尖顶、层次边框，叶片及卷草接入底板；曲线实现后建立有效 UV。内部卷草图案为项目补充设计。',
        '- 三/四级下水短阶采用粗糙细矿物切石。0.16 m 踢面、0.40 m 踏面与 0.84 m 平台是第三人称通行适配。',
        '- 四种踏石及组合最终采用统一角序的环形采样、宽圆肩和独立内冠。轮廓变化对 X/Y 同倍作用，保留角序；两圈浅内冠连接中心，顶冠起伏控制在毫米级；移除旧内辐射边倒角。四件宽度和轮廓变化不同，中央稳定踏带属于游戏补充设计。真实碰撞完全跟随可见三角形，没有跨缝隐形桥。',
        '- 踏石保留已购 `natural_rock_02` 灰色碎裂岩面及正确的 DirectX 法线绿色通道转换；可见冠面连续投影，水下侧面连续环向 UV。水线验收平面固定在 0.34 m，仅用于观察露出比例，不代表正式河流材质验收。干地全露时两种 UV 的接带仍可见，本次画质结论限定于 S12 浅溪踏石用途；正式水透明度和水下观察仍随场景复验，不宣称任意露底摆放已验。',
        '- 安装样例修正矩形墙洞：实心弧形墙肩封住旧拱角漏天处，保留真正通透的拱顶。它是拱门和雕饰的安装验证载体，不是完整住宅。',
        '- 红果树保留已购枝叶几何、叶 atlas、alpha、三个 LOD 及风场；果皮 UV 从无效层恢复，增加粗糙度微差，主干转竖向米制 UV，枝条恢复原已购 UV。树皮改灰褐色，母版与 GLB 同步；果形/数量是参考红果语义的补充设计，不冒称确证物种。','',
        '## 逐件结果','',
        '| 模型 | 源三角形 | 资源 | 画质 | 运行管线 | 临时编辑器 |','|---|---:|---|---|---|---|']
    for r in result:
        record=read(r['report']);cost=record['source_cost'].get('triangles_all_stored_lods','—')
        cells=[f"[{r['id']}](acceptance/{r['id']}.json)",str(cost)]+[labels.get(r['status'][k]['status'],r['status'][k]['status']) for k in keys]
        lines.append('| '+' | '.join(cells)+' |')
    lines += ['',
        '## 验证与成本边界','',
        '资源证据见 [resource_audit.json](resource_audit.json)；真实 AssetLibrary 导入、原生缓存身份、逐件 native 资源图、实际 3D loopback HTTP 放置/选择/碰撞/非法调用/撤销重做/保存重开见 [editor_http.json](editor_http.json)。测试通过既有进程级 content_root_override 隔离内容根；没有提高 8 GiB 缓存预算、清理共享缓存或覆盖用户地图。',
        '',
        '生产 `world_authority.gd` 使用 1.8 m 高、0.30 m 半径角色胶囊，拱门、两种阶梯、四石组合分别双向遍历，共 8 路。最终原生模型证据见 [traversal_native.json](traversal_native.json)；GLB 直接验证另见 [traversal.json](traversal.json)，两者不混用。单石由组合四个相同局部三角网覆盖物理路线，并保留各自独立碰撞探针。',
        '',
        '四件实际导出网格的顶冠朝下三角、退化三角均为零；每件 3,721 个竖直采样没有重叠的向上表面。组合局部三角形与四个单件逐点完全一致，检查记录写入逐件 JSON。',
        '',
        '人工图审覆盖近、中、远、背面、材质/连接细节；树补明暗叶缘、树影、风姿态及六个距离的自动 LOD/强制 LOD0 对照。当前视图、相机和光照参数见每件 report.json；实际查看的图像 SHA 见 [visual_decisions.json](visual_decisions.json)。发送模型分析前使用原尺寸高质量 WebP，PNG 仍在本地保留以供精确比较。',
        '',
        '小踏石各 958 三角、组合 3,832 三角；去除问题拓扑后无需额外 LOD。台阶、雕饰、拱门保留轮廓与倒角，未为比例指标强制减面。树的 363,516 三角是全部存储 LOD 的合计；实际图库计数（含 2 面地面）为 258,094 → 93,513 → 44,441，不能将合计当作单帧可见面数。',
        '',
        'RGBA/mip、原生资源图及准入估算是资源预算，不是单件实测 RSS/VRAM；同像素纹理的去重统计也不证明不同导出文件在运行时共享纹理。正式地图部署仍需复用既有共享材质/批次和逐组件选择语义。',
        '',
        '## 已保留的失败证据','',
        'history/ 保留旧大尺度层理、规则石墩、局部压肩后的顶扇反折、矩形拱洞、HTTP 夹具身份错误及共享 native 缓存容量耗尽记录。旧单轴压肩使相邻顶点角序反转，原倒角又放大了顶内折面；最终已改为完整有序冠肩拓扑。通行通过从未替代这些画面问题的修复。','']
    (OUT/'reference_review.md').write_text('\n'.join(lines),encoding='utf-8')

def main():
    manifest=read(MANIFEST);http=read(OUT/'editor_http.json',{});walk=read(OUT/'traversal_native.json',{})
    decisions=read(OUT/'visual_decisions.json',{})
    topology=read(MANIFEST.parent/'ordered_boulders_v3_topology.json',[])
    result=[];dest=OUT/'acceptance';dest.mkdir(exist_ok=True)
    for asset in manifest['assets']:
        ident=asset['id'];digest=sha(asset['path']);assert digest==asset['sha256']
        resource=read(OUT/ident/'resource_review.json',{})
        gallery=read(OUT/ident/'report.json',{})
        imported=next((x for x in http.get('items',[]) if x['id']==ident and x.get('input_sha')==digest),{})
        decision=decisions.get(ident,{})
        images=decision.get('viewed_images',[])
        image_current=bool(images) and all(Path(x['path']).is_file() and sha(x['path'])==x['sha256'] for x in images)
        visual_current=decision.get('source_sha256')==digest and gallery.get('identity',{}).get('sha256')==digest and image_current
        resource_pass=resource.get('sha256')==digest and resource.get('issues')==[] and resource.get('mother_sha256')==sha(asset['source_blend'])
        if ident.startswith('s12_water_step'):
            resource_pass=resource_pass and any(t.get('id')==ident and t.get('source_sha256')==digest and t.get('passed') for t in topology)
        pipeline_pass=bool(imported.get('passed') and imported.get('semantic_exact') and imported.get('native_resource_stats'))
        editor_pass=bool(http.get('completed') and http.get('passed') and imported.get('http_passed'))
        route_id='s12_water_steps_four' if ident.startswith('s12_water_step') else ident
        route_source=next((a['sha256'] for a in manifest['assets'] if a['id']==route_id),None)
        routes=[r for r in walk.get('cases',[]) if r['id']==route_id and r.get('sha256')==route_source]
        route_required=ident.startswith('s12_water_step') or ident.startswith('s12_landing_steps') or ident=='s12_projecting_arch'
        traversal_pass=not route_required or (walk.get('passed') and len(routes)==2 and all(r['reached'] and r['native_sha'] for r in routes))
        status={
            'resource_audit':state('passed' if resource_pass else 'pending','Actual source and mother SHA; finite geometry/UV, collision roles, image costs. No measured RSS/VRAM.',[str(OUT/ident/'resource_review.json')]),
            'visual':state(decision.get('status','pending') if visual_current else 'pending','; '.join(decision.get('observations',[])) if visual_current else 'Current-SHA explicit image review is not complete.',[str(OUT/ident/'report.json'),str(OUT/'visual_decisions.json')]),
            'runtime_pipeline':state('passed' if pipeline_pass and traversal_pass else 'pending','Actual AssetLibrary import, source/native semantics, native reopen and production capsule traversal where applicable.',[str(OUT/'editor_http.json')]+([str(OUT/'traversal_native.json')] if route_required else [])),
            'temporary_editor_integration':state('passed' if editor_pass else 'pending','Real loopback 3D HTTP placement, independent selection, collision, invalid-call atomicity, undo/redo, save/reopen in an isolated library and map.',[str(OUT/'editor_http.json')]),
            'formal_integration':state('pending','Not published to the production catalogue or city map by this review.',[])}
        record={'id':ident,'source':asset['path'],'source_sha256':digest,'source_mother':asset['source_blend'],'mother_sha256':sha(asset['source_blend']),
                'stage':'textured reference repair candidate','reference':str(ROOT/'docs/references/town_required_shots_20261012/manifest.json'),
                'status':status,'source_cost':resource,'native_cost':{k:imported.get(k) for k in ['native_manifest','native_resource_stats','conservative_admission','stats']},
                'visual_decision':decision if visual_current else {},'traversal_cases':routes,'topology_checks':[t for t in topology if t.get('id')==ident],'formal_map_modified':False,
                'cost_scope':'Native and RGBA/mip figures are conservative resource/admission budgets, not measured RSS/VRAM. Stored tree triangles include all LODs.'}
        (dest/(ident+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        result.append({'id':ident,'source_sha256':digest,'status':status,'report':str(dest/(ident+'.json'))})
    (dest/'index.json').write_text(json.dumps({'assets':result,'formal_map_modified':False,'current_manifest':str(MANIFEST)},ensure_ascii=False,indent=2),encoding='utf-8')
    write_reference_report(result)
    print(json.dumps([{'id':r['id'],'status':{k:v['status'] for k,v in r['status'].items()}} for r in result]))

if __name__=='__main__':main()
