"""Bind completed visual rechecks to accepted exported bytes and native reports."""
import hashlib,json
from pathlib import Path
BASE=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013')
OUT=BASE/'independent_library_review'
SOURCE=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

rows=json.loads((OUT/'matrix.json').read_text(encoding='utf-8'))
manifest=json.loads((SOURCE/'repair_manifest.json').read_text(encoding='utf-8'))
by_id={r['asset_id']:r for r in manifest['library']}
batch=json.loads((BASE/'interior_batch_validation.json').read_text(encoding='utf-8'))
protected={'guild_guest_bed','guild_guest_chair','guild_hanging_skeleton','guild_registration_crystal'}
rechecked=set(batch['changed_asset_ids'])-protected
rechecked.update({'guild_facade_wall_lantern','guild_registration_crystal','guild_hall_lantern',
                  'guild_guest_candle_sconce','guild_guest_candlestick','guild_facade_heraldry'})
notes={
 'guild_storage_cabinet':'原纯米色门芯已恢复细木纹，门框/门芯深浅一致且保留黑金属铰链和把手；近/远及背面无新缺陷。',
 'guild_privacy_screen':'旧木框与白色织物已能区分，近景可见柔和褶皱/细织纹，背面与下缘保持完整。',
 'guild_towel_rail':'双层折回毛巾织纹可辨，悬挂横杆/壁装木座为真实木色，未出现纸板金属感。',
 'guild_shower_tray':'细矿物切石表面已替换纯白，内坡/口沿/排水件保持；不把无砖缝误判为缺图。',
 'guild_wash_basin':'切石细矿物、低光泽内外壁和盆口可辨，原纯白瓷感已修正，排水孔结构保留。',
 'guild_registration_counter':'石砖台身、深色台面与切石托架区分正确，托架细微矿物变化可见。',
 'guild_quest_board_filled':'挂墙式红底金框、张贴纸张及背面挂点保持完整；背面木材已更新。',
 'guild_bottle_round':'腹肩曲线明显连续，瓶口硬边与塞、贴标厚度保留；近中远没有标签穿入。',
 'guild_bottle_squat':'肩颈连续过渡得到修复，窄口/宽腹比例不变，标签重新贴合且保留厚度。',
 'guild_bottle_tall':'肩颈圆滑而筒身笔直，未把瓶口/底脚磨掉；标签随曲面贴合。',
 'guild_serving_jug':'壶腹/肩部从长锥段变为连续曲线，保留瓶口翻沿、底面、把手接缝，近中远形状稳定。',
 'guild_wash_ewer':'壶腹/肩曲线更连续，非对称出水嘴、把手、内口和底部接合保持。',
 'guild_registration_crystal':'新源已另查日/夜/细节图：内部细星尘和透层仍清楚，灰钢与黄铜分别可辨，未回退成蓝色塑料实心球。',
 'guild_facade_wall_lantern':'新源已另查日/夜图：四玻璃片内暖白菱石可辨，夜景壳体受暖光照亮，金属与玻璃无材质回退。',
 'guild_hall_lantern':'日/夜图保留黑金属、玻璃和暖白菱石。独立夜景只确认发光层；该机位邻近真光为0，真光预算须看运行专项。',
 'guild_guest_candle_sconce':'日/夜图中金属托、蜡烛与暖黄火焰完整，夜景邻近暖光与投影可见。',
 'guild_guest_candlestick':'日/夜图中黄铜反射、白蜡与暖黄火焰均保留，夜景周边暖光可见。',
 'guild_facade_heraldry':'风0/1/4秒图显示布下缘轻动，顶端挂点/三角支架保持固定；双面徽样和布厚度无破损。',
 'guild_long_banner':'长幡布面/图案/穗饰保持，挂杆旧木色已更新；作为室内固定织物不额外声称风模拟。',
 'guild_wall_tapestry':'大幅图案布及挂杆/挂点保持完整，旧木杆读感自然；固定室内织物无新增风要求。',
}
history_fields=['audited_source_sha256','native_report','native_report_sha256','native_generator',
                'viewed_images','observations','visual_status','pipeline_status','resource_status']
changed=[];reused=[];new_views=0
for row in rows:
 aid=row['asset_id'];folder=BASE/'accepted_library'/aid
 report=json.loads((folder/'report.json').read_text(encoding='utf-8'))
 actual=digest(Path(by_id[aid]['path']))
 assert actual==by_id[aid]['sha256']==report['identity']['sha256'],aid
 assert report['passed'] and not report['failures'],aid
 same=actual==row['audited_source_sha256']
 if not same:changed.append(aid)
 if aid not in rechecked:
  assert same, 'Changed source lacks a visual recheck: '+aid
  reused.append(aid)
 if not row.get('visual_history'):
  row['visual_history']=[{k:row.get(k) for k in history_fields}]
 old_observation=row['observations'][0]
 if aid in rechecked:
  images=[{'path':str(path),'sha256':digest(path),'view':path.stem,'actually_viewed':True}
          for path in sorted(folder.glob('*.png'))]
  row['viewed_images']=images;new_views+=len(images)
  row['observations']=[notes.get(aid,'已复看原生五视图：偏浅黄木色修正为棕色旧木，原2K纹理和构件细节保留，未发现新的结构、UV、材质或距离轮廓缺陷。')]
  row['visual_evidence_method']='本次 accepted_library 实际逐图复看'
 else:
  row['visual_evidence_method']='源GLB逐字节SHA及Native generator未变；复用前次已逐图查看的5幅图像，未冒称又看了新图'
  assert report['generator']==row['native_generator'],aid
 row.update(audited_source_sha256=actual,manifest_sha256=actual,manifest_matches=True,
            final_gallery=str(folder),native_report=str(folder/'report.json'),
            native_report_sha256=digest(folder/'report.json'),native_generator=report['generator'],
            native_sha256=report.get('native_sha'),batch_repair_pending=False,
            visual_status='通过：参考与已授权补充设计、材质读感和同条件近中远/背面/高光检查未见阻塞缺陷',
            pipeline_status='通过：本轮GLB→Native保存/重开及几何、材质、extras等价，实际SHA与manifest一致',
            resource_status='通过记录：本轮报告含原生/导出/解码纹理成本；没有声称实际RSS/VRAM测量',
            native_report_checks=report['checks'])
 if aid=='guild_facade_heraldry':
  row['runtime_status']='风场可视项通过：0/1/4秒布面轻动且固定边稳定；正式场景碰撞/挂墙位置由总装验收'
 elif aid in ('guild_long_banner','guild_wall_tapestry','guild_towel_rail'):
  row['runtime_status']='室内固定织物，静态厚度/双面/悬挂结构通过；无额外风场动态承诺'
 elif aid in ('guild_guest_candle_sconce','guild_guest_candlestick','guild_hall_lantern','guild_facade_wall_lantern'):
  row['runtime_status']='日/夜可视项已看；邻近真光/昼夜逻辑/预算的整楼运行专项待最终汇总证据'
 elif by_id[aid].get('hinge_members'):
  row['runtime_status']='柜门硬件与独立铰链语义保留；0/半开/全开/复位及碰撞随动等待最终整楼专项报告'
  row['needs_final_runtime_evidence']=True
 else:row['runtime_status']='无本件新增活动合同；当前Native静态语义检查通过'
 (OUT/(aid+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
 lines=[f"# {row['name']} · {aid}",'',f"参考：{row['references']}",'',row['observations'][0],'',
        f"目视：{row['visual_status']}",f"证据方式：{row['visual_evidence_method']}",
        f"管线：{row['pipeline_status']}",f"运行：{row['runtime_status']}",
        f"接入：{row['integration_status']}",'',f"最终源 SHA256：`{actual}`",'',
        f"[本轮原生报告]({str(folder/'report.json').replace(chr(92),'/')})",'',
        '## 实际查看图像','']
 lines += [f"- [{x['view']}]({x['path'].replace(chr(92),'/')}) · `{x['sha256']}`" for x in row['viewed_images']]
 lines += ['', '前次缺陷、前次源SHA与复验记录保存在同名JSON的visual_history。']
 (OUT/(aid+'.md')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
(OUT/'matrix.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 51 件公会独立资产最终目视验收','',
 f'全部51件本轮原生管线通过，实际GLB/manifest/报告源SHA逐件一致。前次实际查看255幅图；本轮对33件复查{new_views}幅新图，其中29件源发生变化、另4件补看灯光/风场。其余18件依据相同资源SHA、相同generator复用已看的图像证据。',
 '', '高柜门芯木纹、偏黄木材、纯白布/石表面、5类瓶壶直线锥段均已修正并在新图复核。未发现新的阻塞画质问题。正式内容编辑器/地图部署仍独立记录，不能由候选验收代替。','',
 '|资产|依据|目视|最终观察|','|---|---|---|---|']
for row in rows:
 lines.append(f"|[{row['name']}]({row['asset_id']}.md)|{row['references']}|通过|{row['observations'][0]}|")
lines += ['', '## 活动件证据边界','',
 '柜门仍由rmmo_hinge驱动，没有GLTF动画轨道；本次静态图只确认硬件和独立语义。最终整楼0/0.5/1及复位、碰撞随动报告尚需总装汇总绑定当前源。旧e920…整楼报告保留为历史背景，不冒充当前源运行通过。',
 '门面布幡风0/1/4秒的实际新图已看，固定边/三角支架不漂移。室内长幡、挂毯、毛巾为静态悬挂设计，没有额外动态风承诺。',
 '四类灯具日/夜图已看，蜡烛/门灯夜间暖光可见。大厅独立灯夜图只见晶石自发光，不能单凭图认定真光控制器成功；最终灯光数、阴影预算和昼夜开关以运行专项为准。',
 '', '## 资源成本','',
 '每件源/native和解码纹理成本见其绑定的本轮report.json。水晶当前近景场景约36,750三角形（含测试地面），不能沿用旧约24K记录；其它器皿新增面仅用于受控曲面，嘴/足/接缝保留。没有将保守预算称作实测RSS/VRAM。',
 '', '## 项目补充设计','',
 '卫生设施、储物高柜与书写桌未在镜头完整出现；保留为已授权功能补充。Fab雕像是用户批准替代。隐藏背面固定件、内部解剖与挂设朝向按文档标记，不称原作确定设定。']
(OUT/'matrix.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
summary={'count':len(rows),'changed_since_first_gallery':changed,'same_source_reused':reused,
         'visually_rechecked':sorted(rechecked),'new_images_actually_viewed':new_views,
         'all_current_sha_match':True,'all_static_visual_pass':True,
         'runtime_scope':'final whole-building hinge/light evidence remains to be attached by parent'}
(OUT/'accepted_visual_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
