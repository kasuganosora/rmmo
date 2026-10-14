# 公会与街景模型正式素材库导入 · 2026-10-13

用户在候选验收后明确要求“都需要进行导入”。64 个验收版本现已全部导入内容编辑器正式默认资源包；2026-10-14 完成正式目录逐件编辑操作复验，64/64 件、4,546 项检查、0 失败。

## 导入结果

- 公会 53 件：主楼、告警塔、51 件独立家具与陈设；街景 11 件。
- 正式素材库从 116 条增至 180 条，原有 116 条记录逐一保留。
- 全部具有中文名称、分类、编辑器生成的缩略图、正式原生缓存及纹理成本记录。
- 复制的是已经验收的实际导出，64 个源文件及目标文件的 SHA 一致。旧的隔离验收报告及其 SHA 保留。
- 正式目录为 `D:/code/rmmo_runtime/packs/default/assets/library.json`。正式城镇地图没有改动。

|编辑器分类|本次导入数量|
|---|---:|
|公会建筑|2|
|公会织物|4|
|公会灯具|4|
|公会陈设|5|
|公会家具|29|
|公会卫浴|9|
|街景建筑|5|
|浅溪踏石|5|
|植被|1|

## 验证记录

- [冻结导入清单](../formal_import_manifest.json)：源文件、实际 SHA、中文名称和分类、逐件验收证据。
- [正式导入回执](receipt.json)：64 件导入成功、原目录保留、正式地图不变、缓存与缩略图身份。
- [真实编辑器复验](editor_verification.json)：在正常正式共享目录中发现资源，以临时地图逐件验证，`completed=true`、`passed=true`、`verified_count=64`、`failures=0`；[逐件记录](items/) 完整保留。HTTP 列表含 12 个内置模块，因此总计 192 项，与文件素材库 180 条不是同一口径。
- 导入通过编辑器共用的 `Library.import_file` 业务操作执行；真实 HTTP MCP 检查覆盖工具发现、正式资源搜索、放置、撤销重做、活动件及保存重开。未添加新的公开导入 API。
- 美术画面、LOD、风场和完整活动检查引用同 SHA 的 [公会验收](../acceptance/README.md) 与 [街景验收](../../required_street_recheck_20261013/reference_review.md)，不把字节相同的正式复制当作重新制作。

保存重开复验还修复了运行时光效被错误加入碰撞的问题：公会的 8 个烛焰在异步重开时曾增加 8 个 body。现在烛焰及光晕显式排除拾取与行走碰撞，真实灯具仍保留原行为，20 项 headless 回归通过。修复后主楼前后均为 2,151 个 body；既有 native 生成器和导出 SHA 未变。见 [具体诊断](diagnostic/editor_verification.json) 与 [回归日志](light_effect_picking_headless.log)。早期未通过记录保留在 `history/`，不冒充最终通过。

## 磁盘成本与可恢复缓存整理

64 份正式 GLB 共 **846,839,092 字节**；正式 native 共 **1,526,541,622 字节**。序列化结果与隔离目录会有少量字节差异，源文件 SHA 保持一致。以上为实际磁盘大小，不是实测 RSS 或显存。

正式导入前缓存仅余约 9 MB。核对全部现用及恢复元数据后，将 61 个无引用旧派生文件移入可恢复隔离目录，共 1,793,337,269 字节。源模型、正式索引、恢复索引和 footprint 均保留；没有提高 8 GiB 上限。导入后 native 文件合计 8,313,924,049 字节，剩余 276,010,543 字节。此处不声称新增了自动缓存回收功能。

- [精确缓存审计](../../guild_formal_import_20261013/cache_preflight.json)
- [移动回执及恢复路径](../../guild_formal_import_20261013/cache_quarantine_receipt.json)

## 使用范围

本次完成正式素材库交付，可以从上述分类搜索和放置。正式城镇位置安排、整楼房间/楼层/屋顶隐藏登记、四扇折叠工具间门的动作、室内反射与间接光，以及正式城镇性能和夜景，仍属于后续场景接入。正常柜门及已登记活动件的既有功能保留。

浅溪踏石按约 0.34 米示意水线验收；完全露出水下石身时的 UV 接带未作为任意干地巨石用途放行。详见 [完整复验及边界](../../../docs/axel_guild_reference_recheck_20261013.md)。

## 逐件目录

正式源文件通过下表链接打开，完整 SHA 及 native 身份在回执中；名称、分类与编辑器一致。

|分类|名称|正式 GLB|
|---|---|---|
|公会建筑|阿克塞尔冒险者公会（含室内陈设）|[axel_guild_repaired](D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb)|
|公会建筑|公会告警塔（黄铜号角）|[guild_alarm_tower](D:/code/rmmo_runtime/packs/default/assets/af248d5044ebad82c27a48d1f4b9be903cf884ea518d5f939b60699199db638e.glb)|
|公会织物|公会 · 盾形公会徽幡与三角挂架|[guild_facade_heraldry](D:/code/rmmo_runtime/packs/default/assets/a083202fa60be4bba3e43557313f1325f0656af6fdd7c2c759683c812f0a6119.glb)|
|公会灯具|公会 · 门旁魔法石玻璃壁灯|[guild_facade_wall_lantern](D:/code/rmmo_runtime/packs/default/assets/84cfe93ecd6fe48aeeb7b4094242b3d3dc5e3adaa63245d7d475d924eadea0ed.glb)|
|公会陈设|公会 · 门前黄铜弯月饰柱|[guild_entrance_crescent_standard](D:/code/rmmo_runtime/packs/default/assets/d74b82cf1c052cfa673654cd970379ccb0e8485dd3124e85a6d27e167dbaf39f.glb)|
|公会家具|公会 · 木吧台|[guild_bar_counter](D:/code/rmmo_runtime/packs/default/assets/89d31917ff1a65b70f90a607e270873a37023a338ad2ae315a538a8a915224d7.glb)|
|公会家具|公会 · 吧台软座圆凳|[guild_bar_stool](D:/code/rmmo_runtime/packs/default/assets/3f745126fa12238eecf8dfcc4d67238edbc97f0a5c0ffaa05b69e336b73df993.glb)|
|公会家具|公会 · 箍铁木桶|[guild_barrel](D:/code/rmmo_runtime/packs/default/assets/83823c26b5755cf0e23bff74dc4ca79442ee788168f2ced626e7898f7dd37dbf.glb)|
|公会家具|公会 · 圆腹酒瓶|[guild_bottle_round](D:/code/rmmo_runtime/packs/default/assets/1bd47e8ac9cb7b7b06deb8f4c215b37cc67f2539fba0fc334f98fd286ffdce25.glb)|
|公会家具|公会 · 矮肩酒瓶|[guild_bottle_squat](D:/code/rmmo_runtime/packs/default/assets/896631b61f9fdbfea77537079a24c101dfb4c8d5234c25678ee56a8a45a1750f.glb)|
|公会家具|公会 · 长颈酒瓶|[guild_bottle_tall](D:/code/rmmo_runtime/packs/default/assets/b95f36a2cbb78b8e312ddfbda7361ba793b748fe92e6f4cee5b93a4cb25156b9.glb)|
|公会卫浴|公会 · 黄铜鹅颈龙头|[guild_brass_faucet](D:/code/rmmo_runtime/packs/default/assets/0a7825e8030f4d157f62dc856f3745238453e719692ac94e00e9d3f854a02b01.glb)|
|公会陈设|公会 · 金属圆环装饰立板|[guild_statue_decorative_panel](D:/code/rmmo_runtime/packs/default/assets/2f220c0836aab68271e16351ce09801bed93923e885abb0b9bd6aa320e95814c.glb)|
|公会家具|公会 · 餐盘|[guild_dining_plate](D:/code/rmmo_runtime/packs/default/assets/eab4ffb5880e985153657b84215761ed19d15570dacd620ccb3cd3c0600fff90.glb)|
|公会家具|公会 · 长餐桌|[guild_dining_table](D:/code/rmmo_runtime/packs/default/assets/a593cbd225099815fcd740d80368592bb5631f200f1a3ab1103e58327c868a6e.glb)|
|公会织物|公会 · 入口花纹长毯|[guild_entry_runner](D:/code/rmmo_runtime/packs/default/assets/023d9a57b120a0347e97ac37b982de59d56e7aca34604dc6765772a5a0db01c4.glb)|
|公会陈设|公会 · 骑士雕像与基座|[guild_fab_knight_statue](D:/code/rmmo_runtime/packs/default/assets/98d3f80d52a3d8cd081fb308f28bd42bc8e41573cb15e6cac19ff3bf3136bca0.glb)|
|公会家具|公会 · 弧顶木床与白色床品|[guild_guest_bed](D:/code/rmmo_runtime/packs/default/assets/263184ee1a75f50c7b547c8665079b3092dd50132e225d574a63db66e58c9d9a.glb)|
|公会灯具|公会 · 单烛壁灯|[guild_guest_candle_sconce](D:/code/rmmo_runtime/packs/default/assets/74d9a8cb13a0b158e36b7d13c1a444f874b5959343089c39c7c9b49a71b5fa71.glb)|
|公会灯具|公会 · 细杆台式烛台|[guild_guest_candlestick](D:/code/rmmo_runtime/packs/default/assets/076787b9b1e25f4b24c32456809f27c8f25865d7b55c005653d20e3ac4c545c7.glb)|
|公会家具|公会 · 红色软包高背椅|[guild_guest_chair](D:/code/rmmo_runtime/packs/default/assets/2b149628b36b1d639326e76c470c3744fcc4cb5fe53f0cb66945b57013f6a9f3.glb)|
|公会家具|公会 · 客房木书桌|[guild_guest_desk](D:/code/rmmo_runtime/packs/default/assets/d10280d804018e80ff81250d18e8c484869fe725a1108bbb6f55e50557495c51.glb)|
|公会家具|公会 · 拱饰低柜|[guild_guest_low_cabinet](D:/code/rmmo_runtime/packs/default/assets/f2b7a3cf1938b15a8bc20e71e349ec4888253926443be90bf9d7a1f67ae0bb57.glb)|
|公会家具|公会 · 窄高床头柜|[guild_guest_nightstand](D:/code/rmmo_runtime/packs/default/assets/c65948bbe5c8063439c477fb512f4e54010310233a50c7455506d536a95ebea6.glb)|
|公会灯具|公会 · 大厅方柱落地灯|[guild_hall_lantern](D:/code/rmmo_runtime/packs/default/assets/9e83ddde3ff64a16d54b781240f5451e7bb8a1854323d905a2f79c9c95866eab.glb)|
|公会陈设|公会 · 大厅悬挂兽骨陈设|[guild_hanging_skeleton](D:/code/rmmo_runtime/packs/default/assets/c5838967f0f9db3de562a282b40b1b8f5509d869f29217c5503a8eb142adb97c.glb)|
|公会织物|公会 · 窄长穗饰垂幡|[guild_long_banner](D:/code/rmmo_runtime/packs/default/assets/7051da1cc77ee8e947a302653f4019e8ec95c4dbf101815dbc84985a791f124f.glb)|
|公会家具|公会 · 长餐凳|[guild_long_bench](D:/code/rmmo_runtime/packs/default/assets/2d037ae15113553678c153ca414b0fdfd45497c9624a9d36c74bea21f09b355d.glb)|
|公会家具|公会 · 室内长方花箱|[guild_planter](D:/code/rmmo_runtime/packs/default/assets/41e05192fa7dcc33c48f811c8f858cadfe2480b7b50900a7ee4cd63e54f164cd.glb)|
|公会家具|公会 · 木框布面隔屏|[guild_privacy_screen](D:/code/rmmo_runtime/packs/default/assets/ff9cb1455f93e77b462989053b49f120e276a8ee4f82ec2a3bd6ffb1a78d7d3a.glb)|
|公会卫浴|公会 · 木座厕位|[guild_privy_seat](D:/code/rmmo_runtime/packs/default/assets/b5bee2fa2bf9ede1fe25f14fc3efb71aa73013c724791dba6deea43daf55cc60.glb)|
|公会家具|公会 · 任务招募板·张贴版|[guild_quest_board_filled](D:/code/rmmo_runtime/packs/default/assets/8a727f225e9df00e8c9c7a231590eaa1f79ead7039a6452094443052d76be2fc.glb)|
|公会家具|公会 · 登记石柜台模块|[guild_registration_counter](D:/code/rmmo_runtime/packs/default/assets/115478727663d7afcbb77d7a5e10fd34bd36d5119487624f17e3fe2a86a06bf0.glb)|
|公会陈设|公会 · 水晶登记装置|[guild_registration_crystal](D:/code/rmmo_runtime/packs/default/assets/70502045e78d6c971f79e09bfa576e8cd94b3da99794582a6eb4575c5d6e3bf7.glb)|
|公会家具|公会 · 圆顶告示立牌|[guild_round_notice_board](D:/code/rmmo_runtime/packs/default/assets/d72ca0399e5536ed3a93c122602e96597343cf13a1ae465c132e6c8a88fc9d75.glb)|
|公会家具|公会 · 圆柱盆栽容器|[guild_round_planter](D:/code/rmmo_runtime/packs/default/assets/da06657b1475e783b19195ce3ff1d8ae38fcfa6b7b15537f534601c2535cd91a.glb)|
|公会家具|公会 · 陶制酒壶|[guild_serving_jug](D:/code/rmmo_runtime/packs/default/assets/54ffd6ce979868b415981fabcf10a85ce93e8544a5d51e2024c4456fe311d4d1.glb)|
|公会家具|公会 · 短餐凳|[guild_short_bench](D:/code/rmmo_runtime/packs/default/assets/bfa48ab9a2958ac7b9672f153936792eeea7ea647210d6e2107928f8b817dee7.glb)|
|公会卫浴|公会 · 黄铜淋浴立管|[guild_shower_column](D:/code/rmmo_runtime/packs/default/assets/943d33a1916d5653e8540df1b827fbeb663d8ab9535592405b56bbfbe4d8324a.glb)|
|公会卫浴|公会 · 石质淋浴底盘|[guild_shower_tray](D:/code/rmmo_runtime/packs/default/assets/cb2ce1c08b1e4914e9cf11344d140d6e2e5638f0c9a4331760e985d13bb77f30.glb)|
|公会家具|公会 · 斜面告示架|[guild_sloped_notice_stand](D:/code/rmmo_runtime/packs/default/assets/adf416ebe7accad94ea8f0f5a9b51c909a191078b4dabedba686c57d908b7c71.glb)|
|公会家具|公会 · 小餐桌|[guild_small_table](D:/code/rmmo_runtime/packs/default/assets/5f511670ca351fb512cd239271a4562a5f2bd3467102b3819451f027a86927c7.glb)|
|公会卫浴|公会 · 陶制皂碟|[guild_soap_dish](D:/code/rmmo_runtime/packs/default/assets/0c513f95b197d6f5a185929e7132c63b4a8f0decb80d1e2d3dbfc2e666ed3ff1.glb)|
|公会家具|公会 · 方凳|[guild_stool](D:/code/rmmo_runtime/packs/default/assets/5ae5609a5dddecc6c711ac04f8039fd2cd16ac97692a7af25daefbcb74df8e5e.glb)|
|公会家具|公会 · 储物高柜|[guild_storage_cabinet](D:/code/rmmo_runtime/packs/default/assets/ae42db2ce4ec35e5fa86227a6daa497c53e9bc1ab66021ee349ba41333f86809.glb)|
|公会家具|公会 · 带柄酒杯|[guild_tankard](D:/code/rmmo_runtime/packs/default/assets/66e15114e4ed4093279205128a510e48abf68ef6a015c7d49b1bc48169fe58ef.glb)|
|公会卫浴|公会 · 毛巾架与垂巾|[guild_towel_rail](D:/code/rmmo_runtime/packs/default/assets/a35c857ad09621571cee2013e25e66ad99c0121b43954a5a564757bda6fb4d3b.glb)|
|公会家具|公会 · 靠背候坐长椅|[guild_waiting_bench](D:/code/rmmo_runtime/packs/default/assets/51df6e99f613d911b220ac22989ff7b8197a07b7b8acb1d0082c3d7119bf582a.glb)|
|公会织物|公会 · 大幅壁挂织毯|[guild_wall_tapestry](D:/code/rmmo_runtime/packs/default/assets/8bce65c13015667ccb3362436fa938ae5935e3cebad0598424cd4bfe9b9446b4.glb)|
|公会卫浴|公会 · 独立石质洗手盆|[guild_wash_basin](D:/code/rmmo_runtime/packs/default/assets/5bd1ccb41e13cf134c9aa3d659247f954a2ffc181d096b2ea2b19551f6e39c80.glb)|
|公会卫浴|公会 · 盥洗陶壶|[guild_wash_ewer](D:/code/rmmo_runtime/packs/default/assets/ac3760eec42cef8ad03c6a9d6bba7bfdf408ef97946c74a4e268635d5122cb95.glb)|
|公会卫浴|公会 · 双盆木制盥洗台|[guild_washstand](D:/code/rmmo_runtime/packs/default/assets/8e33f32078d4c50fe3a34fc01c3e2e2306fd5281cc885fe258bfc8d9859931c6.glb)|
|公会家具|公会 · 书写桌|[guild_writing_desk](D:/code/rmmo_runtime/packs/default/assets/5cb57118cf1ffe4a6a0bb5aa81893a5e28a32ccbec464dd88d58fa819e2fa430.glb)|
|街景建筑|S12 外挑双柱大拱门|[s12_projecting_arch](D:/code/rmmo_runtime/packs/default/assets/11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be.glb)|
|街景建筑|S12 山墙高窄雕饰板|[s12_gable_relief](D:/code/rmmo_runtime/packs/default/assets/d0ca66d5b04913d4bc9ffd56fcc01bb2f4761332dc28fcd98337ad21026dd240.glb)|
|浅溪踏石|S12 水中厚踏石 a|[s12_water_step_a](D:/code/rmmo_runtime/packs/default/assets/d27cf4e6b42475ae47cb0ca2dff552fb5cfcea93883f6320487d960b19947426.glb)|
|浅溪踏石|S12 水中厚踏石 b|[s12_water_step_b](D:/code/rmmo_runtime/packs/default/assets/c62cd67aec2fff506c22c99fd1be91afeca927ca631f3aed969b83edc2e0fe41.glb)|
|浅溪踏石|S12 水中厚踏石 c|[s12_water_step_c](D:/code/rmmo_runtime/packs/default/assets/3b8d246e8e203e5bef698807b2039ecadac59db40bcc8a7d309fac8c73f25d84.glb)|
|浅溪踏石|S12 水中厚踏石 d|[s12_water_step_d](D:/code/rmmo_runtime/packs/default/assets/30fa42f5c279bcd17c08c0ab35c3d15d9654a607774209214c283d4ea5e4ada8.glb)|
|街景建筑|S12 下水石阶台 3级|[s12_landing_steps_3](D:/code/rmmo_runtime/packs/default/assets/eb25ce8429af57f7bfcb6e0e2ce12b1b4a460ad49fb17da0b0567b49c393403d.glb)|
|街景建筑|S12 下水石阶台 4级|[s12_landing_steps_4](D:/code/rmmo_runtime/packs/default/assets/0711766e3b6adb7a4f3916888e5497e6732faea878bb7eb19ea1be1ebac5e543.glb)|
|浅溪踏石|S12 四石示例组合|[s12_water_steps_four](D:/code/rmmo_runtime/packs/default/assets/1a10e99776c92700eace749fab92595474cf42850a7294ab97d679cc59e54cbe.glb)|
|街景建筑|S12 拱门及雕饰板安装验证立面|[s12_facade_installation_demo](D:/code/rmmo_runtime/packs/default/assets/3cd6d9c7e9b1ca0078f3faffd534821f97d025e90bf8f9c5338ccfc71082189d.glb)|
|植被|S10 写实红果阔叶树|[s10_redfruit_broadleaf](D:/code/rmmo_runtime/packs/default/assets/28f99fef1a9a78bf8ae4fa68127eeabb8687b35b8a84e1d1d8fc6d5bfcc15c67.glb)|
