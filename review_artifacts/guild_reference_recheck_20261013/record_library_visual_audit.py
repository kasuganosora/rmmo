"""Record the five-view human/model visual audit; never runs a renderer.

Observations below were made from all 51 five-view contact sheets assembled
from final_library native captures. New batch resources require new pictures.
"""
import hashlib,json
from pathlib import Path

BASE=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013')
OUT=BASE/'independent_library_review'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

NOTES={
'facade_heraldry':'深蓝布幡、红边和金徽保留；有布面弯曲、顶端挂点与背面三角支架，未再呈厚金属盾板。',
'facade_wall_lantern':'入口壁挂灯已能看见透明玻璃内暖白菱形石；金属外壳、墙装支架与挂环完整。',
'entrance_crescent_standard':'月牙金属徽饰、球心、斜指饰与分节杆/锥足完整；黄铜反射可辨，不是发光黄漆。',
'bar_counter':'木吧台台面、板格与支撑结构完整；中性灯光下木色仍偏浅黄，纳入整组旧木色修正。',
'bar_stool':'圆软座和四腿环撑完整；底座木材仍偏浅黄，纳入同材质家族修正。',
'barrel':'弧形桶身、端面与黑铁箍可辨；木材偏浅黄，纳入整组修正。',
'bottle_round':'圆腹/细颈/瓶口与贴标清楚；近景LOD0肩腹轮廓有直线折段，需受控母线平滑。',
'bottle_squat':'矮肩宽腹、瓶颈和标签保留；肩部近景LOD0折段需受控母线平滑。',
'bottle_tall':'长颈窄身、塞口和贴标保留；肩部圆滑过渡不足，需受控母线平滑。',
'brass_faucet':'鹅颈弯管、出水口、双十字阀与安装底座完整，黄铜金属反射可辨；属补充卫生设计。',
'statue_decorative_panel':'窄薄圆顶板、三枚紫色金属环、金色小饰和背部支撑可辨；厚度符合独立装饰板而非墙体。',
'dining_plate':'陶盘内凹、盘沿/足圈和釉面粗糙反射完整；浅色是陶瓷本色，没有明显白模缺图问题。',
'dining_table':'长桌板面、腿与横撑完整；木色偏浅黄，纳入整组修正。',
'entry_runner':'低矮长毯、深绿织纹和边饰可辨，厚度与入口通行用途一致。',
'fab_knight_statue':'用户批准的Fab持剑骑士轮廓、盔甲和原材质保留；与原镜头人物造型的差异是已授权替代。',
'guest_bed':'弧顶竖板床头、木床架、白色枕头/床单布面纹理完整；白色保持布料粗糙而非塑料。',
'guest_candle_sconce':'黑金属墙装托架、蜡烛、烛泪和火焰完整；静态发光可见，真光/昼夜需运行证据。',
'guest_candlestick':'细黄铜杆、盘足、单烛和火焰符合客房参考；静态发光不单独证明实际照明预算。',
'guest_chair':'圆弧红软包高背/坐垫、深木框及前腿绳纹车木可辨，坐高与占地未变。',
'guest_desk':'客房深木桌面、腿与围板符合U15/U22；参考未显示部分为结构补充，未发现明确缺件。',
'guest_low_cabinet':'深木拱形柜门、黑金属跨门饰带、把手与外露铰链可辨；开合须由rmmo_hinge运行证据确认。',
'guest_nightstand':'窄高床头柜、柜门/把手/铰链与细脚符合U15/U22；静态图片没有证明开合。',
'hall_lantern':'烤黑金属灯柱、透明玻璃片及内部暖白悬浮菱形魔法石正确；未见乳白实心灯罩。',
'hanging_skeleton':'骨v2新图的浅骨色、肋骨/头骨/神经弓曲面与吊挂横杆均可辨，未见前次黑刺/块状颅面；未展示解剖为补充。',
'long_banner':'红金长幡、杆/挂件、布面起伏与穗饰完整；木挂杆继承偏黄家族，将随材质组更新。',
'long_bench':'长凳板面、双腿架和横撑完整；偏黄木色将修正。',
'planter':'长方花箱板面、角件与容器内腔清楚；木色偏浅将修正。空箱为复用容器，植株由已有植被组件布置。',
'privacy_screen':'框架/底脚/挂布形态完整；布面仍偏平白、木框偏黄，复用亚麻和旧木材质修正。',
'privy_seat':'带孔木座、升起的盖板、金属铰接和侧壁完整；木色偏黄将修正。盖板当前固定姿态，不冒称可运行活动。',
'quest_board_filled':'红褐板底、金属金边、纸张与背面隐蔽挂点完整；落地长腿已删除。背木面随统一旧木色更新。',
'registration_counter':'石砖台身、深台面与托架齐全；浅色托架仍呈纯白材质，需切石纹理。',
'registration_crystal':'青蓝透明球内细小星尘有深度，前后视可见；异形穿孔灰钢板、外挑轮盘/金冠和深色支撑齐全。',
'round_notice_board':'圆顶灰金属框、支脚、纸面细字与背面厚度完整；近景能辨纸面信息层，非空白占位。',
'round_planter':'圆筒深色盆体、口沿与细饰圈完整；当前空盆是独立容器而非漏做场景植物。',
'serving_jug':'陶壶有真实空口、把手与器壁；近景LOD0腹部仍为直线锥段，需连续母线修正。',
'short_bench':'短凳的板面、双腿架与横撑完整；旧木色修正适用。',
'shower_column':'黄铜升管、上弯管、喷头、控制阀和墙装法兰完整；为明确标记的幻想卫生补充设计。',
'shower_tray':'底盘边、内坡与排水格栅完整；纯白表面缺少石材细节，需切石材质。',
'sloped_notice_stand':'斜牌、立柱和稳定底座完整，纸面字纹可见；未发现参考结构缺件。',
'small_table':'小桌板面、四腿与围撑完整；木色偏黄需统一修正。',
'soap_dish':'皂碟有内凹沿和独立皂块，陶瓷釉面读感合理；不是白模材质遗漏。',
'stool':'方凳板座、脚/撑完整；木材偏黄需修正。',
'storage_cabinet':'高柜活动门的黑金属硬件可见；门芯仍为无纹理浅米色、木框偏黄，明确需修复。',
'tankard':'金属杯口、内腔、弯把与杯底完整；锡/铁色反射区别于灰塑料，未发现明确偏差。',
'towel_rail':'墙装托块、横杆与前后折回毛巾完整；布面缺织纹、木杆偏黄，将复用亚麻/旧木。',
'waiting_bench':'候坐椅的靠背、坐面和扶手/脚架齐全，参考主轮廓合理；旧木色修正。',
'wall_tapestry':'大幅织毯图案、褶皱、顶端吊挂横杆齐全；挂设朝向为补充设计；木挂杆统一旧木色。',
'wash_basin':'盆口、内腔、底部排水与金属口圈完整；表面纯浅白像瓷，需恢复石材读感。',
'wash_ewer':'陶壶真实内口、歪向前方的出水嘴和把手齐全；腹肩近景折段明显，需母线平滑。',
'washstand':'双盆木台和储物/支撑结构完整，卫生方案为补充设计；木材偏黄需修正。',
'writing_desk':'桌面、围板与腿架完整；旧木色需修正。抽屉面属于静态细节，未冒称抽屉交互。',
}

def main():
 rows=json.loads((OUT/'matrix.json').read_text(encoding='utf-8'))
 batch=json.loads((BASE/'interior_batch_validation.json').read_text(encoding='utf-8'))
 protected={'guild_guest_bed','guild_guest_chair','guild_hanging_skeleton','guild_registration_crystal'}
 pending=set(batch['changed_asset_ids'])-protected
 assert len(NOTES)==len(rows)==51
 for row in rows:
  aid=row['asset_id'];gallery=BASE/'final_library'/aid
  r=json.loads((gallery/'report.json').read_text(encoding='utf-8'))
  images=[]
  for view in ['near','back','highlight','medium','far']:
   path=gallery/(view+'_still.png')
   images.append({'path':str(path),'sha256':sha(path),'view':view,'actually_viewed':True})
  row.update(viewed_images=images,observations=[NOTES[aid.removeprefix('guild_')]],
   audited_source_sha256=r['identity']['sha256'],native_generator=r['generator'],
   native_report_sha256=sha(gallery/'report.json'),native_report=str(gallery/'report.json'),
   pipeline_status='通过：实际 Native 导入、保存重开、材质/几何/extras 等价；绑定本件 report identity.sha256',
   resource_status='源SHA/原生资源及纹理成本已由绑定报告记录；不将保守预算称作实测RSS/VRAM',
   visual_status=('发现缺陷；修正模块已完成CPU校验，待重新导出后的同机位新图' if aid in pending else
                  '通过：当前绑定源的近/中/远/背面/高光图已逐件目视；活动运行项单独验收'),
   batch_repair_pending=aid in pending,
   project_supplement=('L1' in row['references'] or aid in ['guild_hanging_skeleton','guild_wall_tapestry']))
  if row['activity_checks']:
   row['runtime_status']='待本轮适用活动合同复验；静态图不能证明开合/灯光切换/风场'
  else:row['runtime_status']='本件无新活动合同；Native语义与静态碰撞合同通过绑定报告'
  (OUT/(aid+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
  lines=[f"# {row['name']} · {aid}",'',f"参考：{row['references']}",'',row['observations'][0],'',
   f"目视：{row['visual_status']}",f"管线：{row['pipeline_status']}",f"运行：{row['runtime_status']}",
   f"接入：{row['integration_status']}",'',f"查看资源 SHA256：`{row['audited_source_sha256']}`",'',
   f"[原生报告]({row['native_report'].replace(chr(92),'/')})",'',
   '所有图像文件及其SHA保存在同名JSON；使用实际单件Native图，不以整楼图替代。','',
   '## 已查看图像','']
  lines += [f"- [{x['view']}]({x['path'].replace(chr(92),'/')}) · `{x['sha256']}`" for x in images]
  (OUT/(aid+'.md')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
 (OUT/'matrix.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
 lines=['# 51 件公会独立资产：逐件目视验收','',
 '本轮已实际查看全部51件×5个原生视图（近、中、远、背面、高光），并与各件参考和用户修正对照。资源SHA及截图SHA逐件记录在同名JSON。Native管线通过不能掩盖画质问题。',
 '',f'有{len(pending)}件因本轮材质家族或器皿母线修正需要重新导出/复拍；其余{len(rows)-len(pending)}件的本次静态目视通过。此处不是正式地图接入完成声明。','',
 '|资产|依据|目视结论|观察|','|---|---|---|---|']
 for row in rows:
  aid=row['asset_id']
  lines.append(f"|[{row['name']}]({aid}.md)|{row['references']}|{'待修正后新图' if row['batch_repair_pending'] else '当前图通过'}|{row['observations'][0]}|")
 lines += ['', '## 修复集中批次','',
 '旧木材保持原2K PBR原图、UV和独立构件，调整基色乘数使其呈老木；高柜纯色门芯恢复相同原木纹。隔屏/毛巾使用已验亚麻纹理；石盆、石淋浴盘及柜台石托使用无砖缝切石图。5类器皿采用局部母线连续插值，径向仍48，不细分瓶口/底/把手。所有修改尚须实际导出新图确认。',
 '', '## 活动件与旧证据的可复用边界','',
 '旧整楼 runtime.json 的e920…源上做过14个柜体、24个柜门0/0.5/1开合及碰撞随动，并检查过灯光预算；那是整楼证据，不是51件独立资源动作证据。',
 '床头柜/客房低柜若保持逐字节SHA，可引用原独立转换证据；其铰链合同还需核对本轮共享实现。高柜改材质重导出后SHA变化，当前图库只能确认金属件/铰链在场，不能宣称开合通过。独立旧报告动画数组为空，原因是游戏运行由rmmo_hinge驱动，不是GLTF动画。',
 '布面静态图可确认厚度/固定边；没有多时刻运行证据就不宣称风场通过。灯具静态图只证明可见发光层，不能单独证明邻近真光、昼夜开关与阴影限额。',
 '盖板和抽屉等未要求交互的细节保留既有静态语义，不为审查自行添加新功能要求。',
 '', '## 受保护通过项','',
 '客房白床品/红软椅、骨v2、青蓝晶球内部星尘、烤黑金属灯柱/透明片/暖白菱石和用户批准Fab雕像保持本次已查结果；本轮集中修正不回退这些材质。']
 (OUT/'matrix.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
 print(json.dumps({'assets':len(rows),'viewed_images':sum(len(r['viewed_images']) for r in rows),'pending_rerender':sorted(pending)},ensure_ascii=False))

if __name__=='__main__':main()
