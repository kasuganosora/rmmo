"""Consolidate accepted receipts without modifying resources, maps or plans."""
from pathlib import Path
import hashlib,json

ROOT=Path('D:/code/rmmo')
RUNTIME=Path('D:/code/rmmo_runtime')
ART=RUNTIME/'art_sources/axel_market_optimization_20261016'
REVIEW=RUNTIME/'review_artifacts/axel_market_optimization_20261016'

def read(path):return json.loads(Path(path).read_text(encoding='utf-8'))
def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def identity(path):return {'path':Path(path).as_posix(),'sha256':sha(path),'bytes':Path(path).stat().st_size}
def write(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

def main():
    publication_path=REVIEW/'publication/publish03/publication.json'
    http_path=REVIEW/'formal_http/http02/editor_verification.json'
    runner_path=REVIEW/'formal_http/http02/runner_result.json'
    accepted_path=REVIEW/'gpu_ab02/acceptance.json'
    publication=read(publication_path);http=read(http_path);runner=read(runner_path);accepted=read(accepted_path)
    assert publication['ok'] and publication['catalog_committed'] and publication['status']=='published_maps_unchanged'
    assert http['passed'] and http['completed'] and http['failures']==0 and http['verified_count']==4
    assert runner['passed'] and runner['engine_error_free']
    assert accepted['visual_accepted'] and accepted['final_art_accepted'] is False
    assert http['catalog_sha_before']==http['catalog_sha_after']==publication['catalog_committed_sha256']
    assert http['formal_map_files_before']==http['formal_map_files_after']
    source_rows={row['asset']:row for row in read(ART/'summary.json')['rows']}
    output=[]
    for mapping in publication['mapping']:
        asset=mapping['asset'];row=source_rows[asset]
        a=read(REVIEW/f'gpu_ab02/{asset}/baseline.json');b=read(REVIEW/f'gpu_ab02/{asset}/candidate.json');compare=read(REVIEW/f'gpu_ab02/{asset}/compare.json')
        assert a['passed'] and b['passed'] and compare['passed'] and all(image['exact'] for image in compare['images'])
        assert sha(mapping['new_glb'])==row['candidate_sha256']==mapping['candidate_sha256']
        assert sha(mapping['new_asset_id'])==mapping['prefab_sha256']
        assert sha(mapping['old_glb'])==row['source_sha256']
        native=mapping['formal_native_identity'];assert sha(native['product'])==native['payload_sha']
        footprint_key=hashlib.sha256(mapping['new_glb'].encode()).hexdigest()
        footprint=read(RUNTIME/f'cache/world3d/compiled_assets_v1/footprints_v1/{footprint_key}.json')
        assert hashlib.sha256(footprint['body'].encode()).hexdigest()==footprint['sha256']
        stats=json.loads(footprint['body'])
        assert stats['source_sha']==row['candidate_sha256'] and stats['payload_sha']==native['payload_sha']
        h=next(item for item in http['items'] if item['id']==asset)
        assert h['http_passed'] and all(h[phase]['valid'] for phase in ('native_before','native_redo','native_reopen'))
        output.append({**mapping,'source_old_bytes':row['source_bytes'],'source_new_bytes':row['candidate_bytes'],'source_saved_bytes':row['source_bytes']-row['candidate_bytes'],
          'isolated_ab_native_old_bytes':a['native']['native_bytes'],'isolated_ab_native_new_bytes':b['native']['native_bytes'],
          'formal_native':native,'formal_footprint_stats':stats['stats'],'formal_footprint_receipt':identity(RUNTIME/f'cache/world3d/compiled_assets_v1/footprints_v1/{footprint_key}.json'),
          'ab_active_rgba_mip_old_bytes':a['native']['stats']['gpu_rgba_bytes'],'ab_active_rgba_mip_new_bytes':b['native']['stats']['gpu_rgba_bytes'],
          'visual_lossless_comparison':'PASS 7/7 exact frame comparisons and actual Q90 viewing','final_art_accepted':False,'baseline_limitations':accepted['assets'][asset]['baseline_limitations'],
          'formal_http':'PASS real catalog discovery/direct prefab placement/selection/undo/redo/save/open/native owner identity',
          'native_owner_after_reopen':h['native_reopen'],'http_item_receipt':identity(REVIEW/f'formal_http/http02/items/{asset}.json'),
          'comparison_receipt':identity(REVIEW/f'gpu_ab02/{asset}/compare.json')})
    old=sum(row['source_old_bytes'] for row in output);new=sum(row['source_new_bytes'] for row in output)
    result={'version':1,'scope':'Four existing market prefabs: lossless source payload optimization and formal catalog replacement only. No authored geometry/UV/material or map edits.',
      'status':{'resource':'PASS','lossless_visual_comparison':'PASS','final_art_realism':'PENDING_BASELINE_REFINEMENT','native_pipeline':'PASS','formal_catalog':'PASS','formal_http':'PASS','formal_map_replacement':'NOT_PERFORMED_LAYOUT_OWNER'},
      'publication':identity(publication_path),'formal_http':identity(http_path),'formal_http_runner':identity(runner_path),'visual_acceptance':identity(accepted_path),
      'formal_http_checks':len(http['checks']),'formal_http_failures':0,'protected_formal_map_files':len(http['formal_map_files_before']),
      'formal_catalog_sha':http['catalog_sha_after'],'source_totals':{'old_bytes':old,'new_bytes':new,'saved_bytes':old-new,'saved_percent':100*(old-new)/old},
      'isolated_ab_native_totals':{'old_bytes':sum(row['isolated_ab_native_old_bytes'] for row in output),'new_bytes':sum(row['isolated_ab_native_new_bytes'] for row in output),'interpretation':'Essentially unchanged; byte-scale serialization variation, not meaningful native savings.'},
      'formal_native_new_total_bytes':sum(row['formal_native']['bytes'] for row in output),
      'active_image_policy':'Each old/new isolated native has 268435440 bytes RGBA8 including mip levels. Formal actual footprint is listed separately. No source texture recompression/resizing or simplification. Estimates are not actual process RSS/VRAM.',
      'old_files_retained':publication['old_files_retained'],'source_masters':publication['source_masters'],
      'failed_attempts_retained':['gpu_ab01','publication/publish01','publication/publish02','formal_http/http01'],
      'failure_resolution':'GPU audit mesh cache contamination fixed in audit duplicate mesh; immutable original JSON authoritative rather than Python-expanded plan copy; HTTP helper now checks has_meta before reading optional native owner. No production checks relaxed.',
      'map_modified':False,'gpu_released_by_this_agent':True,'gpu_handoff_to':'blender_church for missing formal thumbnails; root alone releases the shared queue','formal_thumbnail_completion':'PENDING separate church receipt','mapping':output}
    delivery_path=ART/'delivery.json';write(delivery_path,result)
    lines=['# 市场四款预制件载荷优化与正式交付','',
      '四款原有摊棚已完成无损载荷优化，并正常发布到共享默认素材库。只清理未使用资源，几何、UV、实际材质和使用中的原始贴图保持不变；没有缩图或减面。旧 GLB、旧 prefab 与 Blender 母版全部保留，正式地图未修改。','',
      '**验收边界：无损替换通过，原基线最终写实画质仍待细化。** 28 张候选 Q90 图均实际查看，另查看 4 张基线货品特写；7×4 个相同镜头的本地无损像素比较全部零差异。这并不消除原有陶罐轮廓分段、卷轴纸面厚度、瓶体塑料感、矿石低模轮廓及棚布层次不足的问题，后续布局细化继续处理。','',
      f'源文件合计 **{old:,} → {new:,} B**，减少 **{old-new:,} B（{100*(old-new)/old:.2f}%）**。隔离 A/B 的 native 合计 {result["isolated_ab_native_totals"]["old_bytes"]:,} → {result["isolated_ab_native_totals"]["new_bytes"]:,} B，基本不变；每款活跃图片 RGBA8 全 mip 预算仍为 268,435,440 B。不能把源文件降幅称作显存、RSS 或 native 节省。正式生产导入的 native 合计 **{result["formal_native_new_total_bytes"]:,} B**，实际身份如下，不用隔离 A/B 字节冒充正式交付。','',
      '|资产|旧 GLB B|新 GLB B|正式 native B|正式目录槽位|','|---|---:|---:|---:|---:|']
    for row in output:lines.append(f'|{row["entry"]["label"]}|{row["source_old_bytes"]:,}|{row["source_new_bytes"]:,}|{row["formal_native"]["bytes"]:,}|{row["catalog_slot"]}|')
    lines+=['',f'正式 HTTP **{len(http["checks"])} 项通过、0 失败**，4/4 prefab 从实际目录发现后直接以正式新路径放置，在临时地图完成选择、非法请求无副作用、撤销重做、保存和实际重开。放置/重做/重开均核对真实 PackedScene owner 的源 SHA，以及网格、材质和碰撞。引擎日志无 ERROR；正式目录、旧新资源/native/footprint、母版与 {len(http["formal_map_files_before"])} 份正式地图文件前后 SHA 一致。','',
      '发布使用每件独立 staging 内容根完成 normal importer + Prefabs.capture，再不可变复制到正式目录、生成来源绑定的正式 native。最后读取最新目录，只替换原四个槽位，保留名称、分类与并发新增条目，调用一次原子 revision/lock 保存并重开。旧哈希文件没有原地改写。','',
      f'- [准确 old→new asset_id、GLB 与 native SHA 清单]({delivery_path.as_posix()})',f'- [正式发布回执]({publication_path.as_posix()})',f'- [正式 HTTP 回执]({http_path.as_posix()})',f'- [引擎日志与最终运行结果]({runner_path.as_posix()})',f'- [逐图接受范围及原基线问题]({accepted_path.as_posix()})','',
      '失败尝试保留：gpu_ab01 是审计时给源网格附加 CPU 缓存导致严格 native 校验拒绝；publish01/02 是科学计数与 float32 的测试预期表示问题，正式目录均未提交；http01 功能/SHA 全通过，但工具读取无 metadata 节点产生 ERROR，按门槛未放行，修复后以 http02 完整重跑。未放宽生产校验。','',
      '正式地图实例替换由布局任务通过自己的保存事务完成；本交付没有修改市场计划、旧地图或共享 handoff，也不代表整城帧率验收。']
    document=ROOT/'docs/axel_market_payload_optimization_20261016.md';document.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    write(REVIEW/'delivery_status.json',{'phase':'publication_http_completed_thumbnail_followup','publication_take':'publish03','publication_committed':True,'http_take':'http02','gpu_owner':'blender_church','gpu_released_by_this_agent':True,'global_gpu_release_authority':'root','map_modified':False,'delivery':identity(delivery_path),'document':identity(document),'formal_http':identity(http_path)})
    print(json.dumps({'delivery':identity(delivery_path),'document':identity(document),'publication':identity(publication_path),'http':identity(http_path),'checks':len(http['checks']),'formal_native_bytes':result['formal_native_new_total_bytes']},ensure_ascii=False))

if __name__=='__main__':main()
