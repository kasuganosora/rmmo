# 2026-10-25：纹理阶段第一轮

用户明确“白模阶段结束，开始上纹理阶段优化”。实测起点为已推送的 `7657696b`，
包含 `d296a3b9` 的native源身份清理与后续白模稳定性修改；各launch记录实际HEAD。
白模最新收尾见 `axel_cold_read_attribution_20261025.md` 最后两节：covered48ms下
cold-index N10 median8.381s、p95/max9.784s；返回代码尖峰已有后续修复，帧间等待
另列，当前native路径未复现AV。不得把更早10.730s/190.361ms样本冒充当前基线，
也不把历史AV归因写成已修复引擎根因。依用户指示结束白模专项，转入纹理。

## 分阶段恢复与测量合同

第一步恢复地图表面、地形及预制件的原有材质/纹理；导入模型继续使用既有裸native几何
和白色材质，HUD/天气/角色等外围仍关闭。这是部分纹理阶段，不是完整游戏或全部模型
材质恢复。原生裸几何不包含模型材质绑定表，后续模型材质需离线导出独立绑定数据，不能
切回GLB运行时导入，也不能直接启用历史过期compiled资源。

`--map-texture-stage` 单独选择native几何，取消全局白化；与全白/禁纹理开关互斥。
程序材质保留真实通道及着色。沿用背景桌面、同引擎和同地图，固定测试灯光。native
模板只对原有白色native模型保留，真实surface_paint仍走完整适配器，避免略过绘制语义。
对应模型worker工作区继续计入准入。纹理交互发布保持普通2ms预算，白模6ms单独判定；
遮罩预算未调整。派生几何缓存有独立namespace，离线裸几何writer仍要求原白模导出配置。

主时间继续从pipeline开始到当前需求连续3帧就绪；阶段额外检查像素消费者和共享输出
排空。实际GPU材质/纹理绑定审计在首次3D恢复后进行，不进入full-ready计时。
计数、diagnostic profile与普通运行分组，不把一次样本称作p95。

`tools/run_axel_texture_phase.py` 保存完整命令、引擎/源码/地图SHA、owned PID、实际
优先级、结果及失败日志，拒覆盖旧样本。所有GPU运行使用 `run_godot_background.py`。
cold-index仅指派生目录失效；native产品、纹理磁盘缓存和OS缓存保留，不宣称物理冷盘。

## 首个复现：已准备像素绕过上传分片

`Deferred._publish_ready` 原来只在 `prefab_texture_packet.is_empty()` 时执行
`MaterialPublication.step`；启用后台/共享像素反而直接同步恢复整组材质与上传纹理。

独立GPU红测 `prepared_material_red.log`：9通过、3失败，无脚本/引擎错误。已耗尽
本turn预算时仍允许一个强制推进单元，但该单元上传了3个唯一纹理并实例化组件，
`material_preparation_units=0`。因此后台解码并没有限制主线程的后续上传工作。

修复让prepared/shared packet进入同一分片器；提取并复用HousePrefab原有的纹理安装/
来源版本/驻留ticket/过期材质处理作用域，每次调用结束恢复临时全局像素表。CPU图片
仍由已准入job持有，逐纹理上传、逐材质完成后再实例化。取消/失败沿用job回收路径。
`prepared_material_slicing_enabled` 只供对照旧路径，默认开启。

切片设置状态由同一job持有，最终 `publish_prepared` 也接续该状态。同一源代际只做一次
完整失效处理，后续只临时安装像素表。跨片检查实际热/弱纹理与目标材质拥有的代际；
resident-only packet 同样检查，不能因 `images` 为空就借到另一个版本的弱缓存纹理。
这个边界先由 `prepared_resident_red.log` 复现为60通过/3失败，再修复。

独立GPU末轮 `prepared_material_final02_verification.json`：分片64/0、像素准备75/0、
原有材质分片46/0、驻留8/0。旧单元3次上传+1节点→新单元1次上传+0节点，累计仍3次；
完整设置一次，最终提交仍复用；同像素/mip/法线/alpha/零热预算/取消/源代际隔离通过。
既有像素准备测试中，旧“trusted map磁盘变动必须失败”的断言已与既有mounted合同
对齐：显式严格模式仍拒绝，同一磁盘变动在trusted mounted快照模式继续成功。
保留修正前73/1日志，不把更改测试口径称作新生产修复。

## 首次实图诊断（中间代码，不能混入最终ABBA）

`map_diag_01` 功能通过，engine为历史c593版本，正式地图SHA和测量中源码不变。
未主动清缓存，实际派生目录报告 `stale_index`，与之后命中的普通样本分开记录。

- loader 11.066s，entry 14.419s，当前需求完整就绪31.652s。
- 首次真实3D绘制35.158s，完整就绪后另有3.504s恢复绘制等待；未证明是某个GPU驱动
  或引擎函数，不能隐藏在full-ready定义之外不记录。
- 实际绑定审计：3943 GPU surfaces，其中1502含纹理、3202非全白、145个纹理对象。
  这只是绑定覆盖观测，不代表完整模型材质恢复。原尺寸1440×900的WebP quality90已
  实际查看，地面草地与石路有纹理，导入模型仍白。
- 104条prefab路径、111个准备packet、7次continuation；其中92个任务images/output/
  decoded全0，命中驻留974次，仍累计47.330s worker工作，其中read_sha23.140s、
  final_sha21.667s。全部任务两类SHA为34.555s/31.408s；均是并行累计，不能相加成wall。
- 实际paint上传85次，提交累计0.513s、最大35.458ms。报告不支持“主要慢在上传”判断。
- 派发出现510.243ms/583.679ms；原报告没有header、ticket、offer分段，不能先归因于
  某个同步I/O或扫描函数。已补可选计时，普通运行不开启。

## 删除驻留/共享消费者的重复纹理认证

用户再次明确：不是必需的纹理校验直接去掉。正常mounted加载不再逐consumer读文件
认证、最终交接再认证或派生缓存写入再认证。本次操作的SharedPool只保存标量
`path→source SHA`，首次从真实文件字节建立派生缓存身份，之后比较已拥有的身份。
不会直接把前一地图仍存活的GPU票据当作本次文件身份。IO与hash不持有pool mutex，
并发首次miss允许少量重复读取，避免把一个worker的磁盘等待扩散给其他worker。

新的加载操作开启新pool；同queue无jobs重新配置也换pool，在途任务不会被换池。
取消/释放后consumer不可借用身份，冲突的后续digest不能覆盖第一次身份。真实codec
尺寸、字节/格式和内存准入上限继续检查。独立API默认严格，显式审计与ABBA开关保留
旧路径；mounted语义沿用资源包快照，不承诺跟踪加载期间的外部文件修改。

`texture_identity_red01` 先保留旧8消费者source8+final8、3项失败的复现。
`texture_identity_green02` 新27/0；100消费者×3源×2方向：旧source300+final300，
新source3+final0+persist0，后续身份命中297。源读取29700→297字节。
独立微测304.023→235.264ms，不用作实图速度结论。并发首次miss实际3次，取消、
新pool同路径新内容、严格模式换源拒绝、同queue重配置隔离通过。
既有shared/resume headless30/0，prefab preparation headless63/0。

仍未移除的成本明确保留：初始RuntimeTextureCache的源身份/派生cache checksum；
像素被回收后leader即使命中派生磁盘缓存仍先读取源文件；各房屋的同步header计划与
票据目录扫描。不能把上述100消费者微测解释成任何地图完整生命周期永远只读3次。

## 冻结代码后的普通ABBA

A同时开启 `--legacy-publication --legacy-source-reads`，B采用新发布分片与操作内源身份。
各臂2次，同引擎、源码和地图SHA，纹理/OS缓存保留、派生几何缓存关闭；不宣称物理冷盘。
先跑 `white_02` 留同机白模参照，再A1/B1/B2/A2，之后单独 `map_diag_02` 开细计时。
每次功能通过、源码/地图不变；N不足稳定性验收，只报告范围/中值，不报告加载p95。

| 样本 | 当前需求完整就绪 | entry | 撤罩后10秒平均FPS | 逐帧p95 / max | >50ms帧 | 恢复3D到首绘 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | 25.144s | 9.870s | 148.15 | 9.644 / 73.037ms | 1 | 62.152ms |
| B1 | 18.627s | 10.005s | 144.91 | 9.926 / 66.506ms | 1 | 67.142ms |
| B2 | 18.115s | 9.739s | 143.11 | 10.049 / 64.673ms | 1 | 50.984ms |
| A2 | 24.790s | 9.812s | 145.60 | 9.873 / 68.094ms | 1 | 74.385ms |
| white_02（单次参照） | 7.509s | 3.918s | 165.79 | 9.348 / 61.975ms | 1 | 48.036ms |

完整就绪中值 **24.967→18.371s，减少6.596s（26.4%）**。这是两个修复累计组合的收益，
不能分摊为各单项收益。entry没有明显改善，稳态FPS也没有改善证据。纹理恢复增加着色/
地形材质工作，此表只代表该几何测试宿主与相机，不能当完整游戏FPS。

- source读取1476次/5.166GB→103–108次/0.356–0.367GB；计数字节仅此read阶段，
  不能冒称全进程磁盘物理读取量。final SHA1476次→0次。
- worker累计77.22–79.35s→11.38–11.44s，存在并行/嵌套，不能当作wall相加。
- 有效工作一致：共享像素实际生产61份，GPU表面3943、带纹理1502、独立纹理145。
  初始收尾pool outputs/consumers/retained_bytes全0。
- 加载阶段>50ms帧数由A的51/53变为B的72/74，最大由411–501ms变374–395ms；
  更快完成不代表加载页长帧已解决。撤罩后稳态各有1帧>50ms，没有栈证据不能归为OS。

`map_diag_02` 18.379s功能通过；dispatch子段header最大15.423ms、累计334.882ms/185次，
ticket最大2.182ms、累计25.599ms/106次，offer最大0.425ms、累计4.924ms/106次。
本轮未重现先前500ms的同一子段，不能认定500ms由header或ticket造成、更不能标为修复。
该诊断初始terrain worker6.089s、join wait4.590s，texture decode1.323s，build5.769s；
有包含/并行关系。初始terrain准备/等待仍是候选；后续返回测试发现更严重的主线程发布
尖峰，先处理该已复现问题，不继续盯25.6ms总票据扫描。

完整汇总见 `stage_summary_abba01.json`，普通与diagnostic、源码版本分别分组。

## 纹理卸载与返回：仍不合格

`map_traverse_01` 使用同一冻结版本，开启frame-split与纹理细计时，属于诊断样本。
功能通过、engine正常退出、源码/地图SHA不变；entry9.949s、完整就绪18.611s。

| 阶段 | 帧p95 | 最大帧 | >50ms帧 |
| --- | ---: | ---: | ---: |
| departure | 13.624ms | 116.387ms | 1 |
| unload | 4.527ms | 117.293ms | 2 |
| return | 12.841ms | 1367.812ms | 16 |
| reload | 28.355ms | 488.947ms | 9 |

返回1367.812ms帧覆盖同一时刻publish1365.390ms（stage总1365.918ms、dispatch0.064ms）；
后续847ms帧也主要是publish。reload488.947ms对应publish471.810ms。这些是代码发布链
长帧，不能归为OS空闲。departure/unload的112.606/109.817ms previous_draw墙钟与
3.821/7.399ms process则先保留为绘制/呈现等待候选，没有栈证据不能直接归因资源释放。

初始到返回结束，runtime_image_lookup从0增到25、texture.image从24增到49；后台准备
之外仍出现同步读图。源码确认普通terrain/road不进入PrefabTextures.sources，预制件的
surface_paint也被漏掉；非prefab发布同样没有像素作用域和逐纹理预算。该缺口需先在独立
测试复现，再修复两端；当前累计计数尚不能证明25次全部属于最大1365ms发布，官方profiler
正在建立函数与长帧对应关系。

卸载/返回实际驻留373→0→373、native units503→0→504、碰撞体2147→0→2147；
最大2151-spec建筑和63/63地形确实退休，返回missing parts/terrain/invisible均0。
far/return末尾admission jobs/bytes为0；退出包含一个在途worker及57,426,944字节，退出后
worker/jobs/admission/lookahead/loading context/retirement/templates全0。最终截图仍为
1440×900 WebP quality90，SHA为`8f42a599fe6f5b4ebadf3b1a045994b05c01af8d58a8d5c872a41b47cd88e418`，
已实际查看；不以功能与清理通过代替长帧性能验收。

`map_traverse_official01` 使用官方script profiler（top128，native attribution关闭），
正常优先级32、loopback collector、私有桌面。client/collector均exit0，source/map/engine
SHA前后一致，无script errors；编译warning单独计数。fullready23.342s只作诊断，不能混入
普通加载样本。观察帧N对应官方N−1，保留相邻帧交叉核对：

- 返回N24175=1461.449ms，对应官方N24174 process1460.239ms：
  `_publish_ready`1457.595 → `WorldDocument._mesh`1457.269 →
  `SurfaceMaterials.texture_error`1453.773 → `_texture`1441.395 →
  `RuntimeTextureCache.image`12次1362.101ms。其中checksum12次611.237ms。
  函数存在包含关系，不能求和；已证明同步像素读取发生于主线程发布前的纹理预检查。
- 另一返回N24232=1326.526ms：`_mesh → RiverMaterials.apply/terrain →
  TerrainRegions.mask`1297.382ms。这是第二个独立CPU热点，不能全部归入纹理读盘。
  初始MapLoader有后台mask准备，流式Chunk准备却没有，返回时在主线程兜底重建。

完整官方消息、帧对齐和top128边界见`official_chain_review.json`及对应analysis。

## 返回链补齐与进一步删重复读取（独立证据）

`test_texture_source_coverage.gd` 旧3通过/5失败，新8/0：统一从
`SurfaceMaterials.definitions`收集terrain层/过渡/height、道路路缘、prefab覆盖、banner及
bridge/rock/fortification材质，按路径/法线方向去重，保留256源可选预备界限。目录generator
本来就包含该脚本SHA，变化自动使旧派生目录失效，不修改作者包。

`texture_retired_leader_red01` 对同pool已释放像素后的20轮×2方向，派生缓存命中40次
仍完整读源40次；`green01`为43/0，读源40→0，逐字节核对全部mip。known identity先查
派生缓存；缺失/截断/错误代际只读受影响方向，新操作同路径换源和严格诊断仍读取新来源。
这轮43项冻结证据在sources枚举修改之前，最终组合需另跑；现有shared回归30/0，prefab
回归63/0（后者运行期间sources变化，收据明确保留，不当作最终冻结验收）。

后续`texture_cache_trust_red02→green01`32/0：普通两种像素cache读者的payload全量SHA
各1→0，mounted第二次header读取1→0，严格诊断各保留1。普通游戏/编辑器信任资源包
及自身原子生成的派生缓存，仍检查缓存代际、容器/格式/尺寸、mip长度和实际解码输出
上限。正常路径不再保证发现所有“结构合法但像素位变化”的损坏；缺失、截断、错误
结构/格式/身份仍回退解码。不能把删除全量认证写成完整保留所有位损坏检测。
`RuntimeTextureCache`初次源身份读取尚未更改。最终同源组合回归43+63+30通过，
`texture_trust_regressions_final01.json`记录source SHA前后一致。

地形mask独立`streamed_terrain_mask_review.json`：真实Chunk worker红14/1→绿32/0。
新worker一次生成132,098字节RG8遮罩；fixture109.060ms仅作CPU定位，不冒充整图收益。
主线程20次复用、fallback生成0，逐像素一致。白模/禁纹理不新增mask工作；实际queue
接收和discard后Image弱引用及lease归零。固定mask与最大halo/构建临时数据落在原有
terrain 1MiB固定保守余量内。既有terrain load9/0、selected context15/0、Chunk24/0。
真实返回阶段是否消除该尖峰仍需整图复测。

进一步去掉`WorldDocument._mesh`对可信、immutable、effects=true加载的额外
`texture_error`全声明预检查；实际材质创建、后台像素错误及解码边界继续存在。
`test_trusted_texture_preflight.gd`使用strict下有效的prefab：完整材料表有合法图片，
实际geometry只引用null槽。红14/2→绿16/0，可信加载原来为未绑定纹理主动读图1次，
现在0次。strict、mutable交互及offline导出仍各1次，源图字节和实际CPU几何不变。
这与把预检查挪进worker不同：可信加载直接不再做这次无必要预检查。

发布扩展的审查边界：optional texture plan仍可能只覆盖部分方向/格式。新预上传只固定
packet.images或resident_textures里确切存在的key，不凭同路径SHA把未准入的另一法线方向
也加入；未覆盖项保持原最终绑定后备并记录有界skip计数，不宣称所有WebP或超预算对象
已经实现后台准备。独立partial-plan反例先复现额外同步读取/强pin，再加此守卫。

Shader代际首次fixture红灯卡在前置条件，不能作错误像素证据，失败日志保留。修正为真实
Chunk几何及按目标UUID等待后，`streamed_shader_effective_red.log`为98/1：仅旁路目标
shader guard时，A的最终真实WorldDocument确实误用B的像素/身份；收据记录精确还原SHA。
修复仅在目标terrain shader cache命中时比较其实际纹理与当前prepared/retained owner，
不读文件、不每slice扫描全缓存、不清除无关shader。

## 修复后真实地图复测（map_traverse_03）

当前工作区的纹理修复冻结后复测一次普通 map traverse（无 texture-profile/screenshot）：
entry 9.698s、完整就绪 **18.513s**、failures 空、源码/地图 SHA 不变。ABBA 的
24.967→18.371s 收益仍在；这一次不能冒充 N10。

返回阶段原先 1367.812ms 的 **publish 链已消失**：本轮最大返回帧 322.6ms 中
publish 只有 5.351ms，主要变成 `geometry_tick_us=311.236ms`，即
`WorldStream.sync` 的单次 apply；另有 220.1ms 帧对应 geometry 213.659ms、
reload 172.1ms 对应 geometry 169.001ms。`stream_cursor=1`、`stream_jobs=73`
说明仍有一个大的 indivisible apply 没有分片。unload 仍有 108.7ms，process 26.4ms、
Deferred 全空，属于下一类待归因长帧。纹理 read SHA/重复预检查已不再是这帧主因。

因此当前纹理阶段状态是：**加载/重复校验收益成立，1.37s publish 尖峰已修，
但 322ms 的 Stream.sync apply、172ms reload apply 和 108ms unload 仍未通过。**
下一步应先给 `_sync_work` 的单次 apply 加 path/spec/阶段计时，再把大
building/terrain apply 切成分片，而不是继续删 SHA。

## 去掉重复 SHA 后的大 apply 归因

正常 trusted 纹理路径已不再读源文件算 SHA：`TextureCache` 使用 path identity，prefab 缓存使用
版本 4 path identity；strict 诊断仍做 content SHA。`test_texture_cache_trust` 32/0，
`test_texture_source_coverage` 8/0。首轮换 namespace 会重建 24 张缓存，warm 后正常。

`map_traverse_07/08` 的真实 map 仍保留大 apply。给 `_spawn` 加阶段计时后，慢点明确是
`PreparedCpuUpload.restore`：

| job | restore | materials | total `_spawn` | surfaces |
|---|---:|---:|---:|---:|
| obj_1020 | 455.2ms | — | 459.2ms | 8 |
| obj_320 | 314.8ms | — | 324.1ms | 9 |
| fort_..._baked_54 | 211.8ms | — | 216.1ms | 4 |
| axel_bridge_4 | 214ms | — | 217ms | 3 |
| axel_terrain_05_06 | 188.4ms | — | 191.7ms | 2 |
| river_... | 152.3ms | 41.5ms | 198.2ms | 3 |

也就是说剩余长帧不是 publication，也不是 SHA，而是主线程 `ArrayMesh` 的
`set("_surfaces")` 上传（8 surfaces 的 obj_1020 就 455ms）。materials 只在 river 额外
41.5ms。当前应该把大 prefab/terrain 的 `PreparedCpuUpload.restore` 改成有界逐 surface
安装/隐藏至完成，而不是继续动纹理身份或缓存校验。

本次 `map_traverse_08` 功能通过，entry 10.200s、full-ready 18.935s，源码/地图不变。

## 分 surface install 试验（未达目标）

把大 `CpuMesh` 的 `restore` 改为逐 surface `ArrayMesh.add_surface_from_arrays`，视觉先隐藏，
完成后再显示。`map_traverse_11` 功能通过（entry 10.090s），但：

- full-ready **20.927s**（比未切片的 18.7–18.9s 慢）
- return max **274.7ms**，仍有 **11 帧 >50**
- reload max 177.6ms，unload 136.1ms

最大帧从 513ms 降到 274ms，但每片 surface 本身仍约 50ms，且隐藏等待使完整就绪更慢；
这不是可接受的净优化。结论：`ArrayMesh` 单 surface 上传在主线程上仍是 indivisible，
需要 worker/prepared-packet 或按材质/顶点更细的引擎级提交，而不是 GDScript 逐片 install。

## restore 内部：几何很小，材质才是主因

`map_traverse_12` 打开 `CpuMesh.restore` 的逐 surface 计时（`cpu_restore_profile`）：

| 样本 | geometry_us | material_us |
|---|---:|---:|
| surface 3，8928 顶点 | 1,483 | **197,999** |
| surface 0，72 顶点 | 28 | **190,069** |
| surface 0，961 顶点 | 100 | **186,257** |
| surface 0，9 顶点 | 72 | **174,641** |
| surface 4，1344 顶点 | 117 | **163,930** |
| surface 6，1120 顶点 | 97 | **158,751** |
| 大 surface 27,042 顶点 | 27,434 | 9 |
| 大 surface 1,120 顶点 | 17,109 | 7 |

即 455ms 的 `restore` 主要花在 **`surface_set_material`**（约 150–198ms/面），几何
`add_surface_from_arrays` 通常只有 0.1–1.5ms，少数大面 17–27ms。此前逐 surface 安装
把几何拆开却仍每面付材质成本，所以失败。下一步应缓存/预热 material 的 GPU texture/shader
提交，而不是继续切几何。

## 材质成本是每材质首次提交

`map_traverse_13` 在 restore 行里加入 material/RID：

- 15 个慢 surface 对应 **15 个不同 material instance**；
- 只有 **10 个不同 albedo RID**，其中两个 surface 共用同一 albedo RID，仍各花
  164.7ms/159.5ms；
- material 150–223ms，geometry 0.1–31.8ms。

因此不是同一材质重复绑定，也不是 albedo 纹理上传；更像每个不同
`StandardMaterial3D` 首次建立 uniform/shader 提交。下一步需要确认是否是 shader
variant 编译，并把材质预热/提交移出 `_spawn` 关键帧；继续切 surface 几何无效。

## 纹理上传量是材质停顿的上游

`map_traverse_13` 的 paint profile：

- `paint.texture.gpu_cache_miss=176`
- `paint.texture.upload_bytes=**2,331,942,169**`（约 2.33GB）
- `paint.texture.upload` 176 次、累计 884ms、max 41.8ms
- `texture.image.upload_prepare` 226 次、累计 1.333s

`surface_set_material` 的 150–223ms 没有对应同一 albedo 的重复提交，单个 upload
调用也只有 ≤42ms；因此 150ms 级停顿更像 GPU 上传/队列背压，而不是 GDScript 几何工作。
下一次优化必须针对 **2.33GB 的驻留上传**（可见性/lazy、共享或压缩表示），否则继续在
`_spawn` 内拆几何/材质只会改变停顿位置。

## VRAM 压缩试验：不可用

按新授权试过对上传 Image 做 S3TC/BPTC `Image.compress`：

- `map_traverse_14` full-ready **68.610s**（明显回退）
- `paint.texture.upload` 累计 **89.4s**、max 6.33s
- `paint.texture.upload_bytes` 仍约 **2.248GB**，并没有真正减少驻留量
- 功能虽通过，但没有性能价值

已撤回压缩路径。结论：Godot 4.7 的运行时 `Image.compress` 在这里是昂贵的软件压缩，
不能作为加载优化；若要压缩，必须离线生成 GPU 压缩资产，或改引擎上传路径。

## Lazy placeholder 试验：不可用

按新授权试过 materials 先用 neutral placeholder、纹理上传进入 4ms 主线程队列：

`map_traverse_15`：

- entry 11.224s
- 完整就绪 **缺失**
- `demand_settling.extra_ms=90,050`
- 仍有 `admission.jobs=44`（shared_pixels 32、ready 12）、`pending=1949`、
  `unpublished=1417`
- failures：`all current geometry demands and batches settle`、
  `origin full-ready missing before unload/return`

lazy 占位没有接入 shared-pixel 的 lease/完成语义，worker 仍持有图片，Deferred 队列
永远不 idle。已撤回，不能把 placeholder 直接塞进材质。

## 纹理 source budget / placeholder 试验：仍不 settle

`map_traverse_16/17/18` 试过 prefab texture source budget（32/1）并让未准入路径使用
neutral placeholder：

- budget 32 时 upload_bytes 从 2.33GB 降到 **0.623GB**，但 entry 11.2s 后
  `demand_settling.extra_ms=90s`，完整就绪缺失；
- `admission.jobs=38`，其中 shared_pixels **26**；`pending/unpublished` 仍约 1.4k/0.9k；
- budget 1 仍然 90s 不 settle。

原因是 placeholder 只阻止了材质消费；已派发的 shared-pixel job 依旧持有图片和 lease，
Deferred 队列无法 idle。预算本身能把上传量降约 73%，但不能绕过 lease 完成语义。
必须改 `_shared_images`/Deferred job 的准入与释放，而不是继续在材质计划上加跳过。

## 可见集 full-ready：早期样本是假阳性

`map_traverse_20/21` 曾看到 full-ready 13.330s/12.168s（phase=`white_stream_origin`），
但当时 `visible_ready` 没有要求 demand candidate revision 已经刷新，只看到了当时
已发布的子集，属于提前放行。

加入 `_candidates_revision==_demand_revision` 后复查：

- `map_vis_01`：18.924s
- `map_vis_02`：19.774s
- `map_vis_03`：19.531s

这些样本 phase 都是 `white_origin_demand_settle`，与旧全量 18.7s 同级，**没有
可靠收益**。12.168/13.330 不能作为优化结果，也不能拿那张 screenshot 证明可见纹理
在 12s 已就绪。可见集门控保留为正确性约束，但当前 prove 不到加速。

之前 0.623GB upload budget 的 90s 不 settle 仍是 lease 层问题；这两条不能混为成功。

## visible-ready N8：无收益并回退

正确 revision gate 下 8 个普通 map traverse 样本：

18.924、19.774、19.531、20.612、22.312、26.355、22.890、22.557s。
中位约 20.1s，最大 26.4s；旧全量 baseline 18.732s。可见集门控没有降低加载，
反而更慢，且 N8 不是 N10。已将 `World3D` 生产 gate、probe visible-ready、
texture source budget/lazy 实验路径全部撤回；保留的只有 trusted SHA 删除和
profile/文档。2.33GB 上传与 450–513ms 长帧仍未解决。

## 离线 DDS sidecar：历史采样（上传总量口径已更正）

按授权对现有 pack 纹理做**附加式**离线 GPU 压缩，不修改源文件：

- `tools/generate_texture_dds_sidecars.py` 生成 `.dxt1.dds`/`.dxt5.dds` 与 normal
  的 `.flip.dxt5.dds`；源 PNG/JPEG/WebP 不变，删除 sidecar 即回退。
- 现有 pack 扫描 631 张：写 655 个 sidecar，66 张因尺寸不是 4 的倍数跳过。
- 修正 Pillow 的 DDS `pitchOrLinearSize`（Godot 期望 DXT block linear size）。
- 运行时 `SurfaceMaterials._texture` 优先加载 sidecar；`_prefab_texture_plan`
  不再为已有 sidecar 的路径派发 shared-pixel GPU 纹理任务。

`map_traverse_26`（带 texture profile + screenshot）：

- 当时的 upload_bytes 记录为 **2.29GB → 564,742,192**；原“约 -75%”结论
  因 DDS 分支漏计而撤销，不能把该数值当作压缩后的全部上传量，见下方复核。
- sidecar uploads 124，sidecar upload 累计 226ms，max 15.4ms
- material 累计 378ms（旧约 9s）
- full-ready 18.611s；截图地面/石路纹理正常，failures 空

5 个普通 sidecar 样本 full-ready：17.264、17.613、18.742、19.294、18.611s；
reload max 45–55ms（旧 192ms），但 return 仍 353–672ms。也就是说 sidecar 主要
降低了纹理上传/重载，未消除 Stream.sync 的 return 几何尖峰。源地图/纹理未改；
sidecar 是可选离线资产，需要随 pack 一起分发。

## 2026-10-25 编辑器适配复核与计量纠正

复核 `4c2ba020` 发现，DDS 分支只计 `paint.texture.sidecar_uploads`，没有把
`side.image.get_data_size()` 加到 `paint.texture.upload_bytes`。因此历史
`564,742,192` **仅覆盖未走 DDS 的上传**，遗漏的 DDS 总字节未保存在该累计计数中。
原始日志、样本和耗时保留；不能靠补代码倒推成“已重新测得总量”，也不能继续宣称
总体下降 75%。新代码将 DDS 上传同时计入总量，并单列 `paint.texture.sidecar_upload_bytes`。

生成器还存在三个明确的正确性缺口：`.flip` 法线做了图像上下翻转而不是 G 通道反转；
DDS 只写顶层，丢失原路径已有的 mipmap；透明源改为不透明后，旧 DXT5 可能继续优先于
新 DXT1。候选修复先在临时目录完成，以下引擎测试时地图 sidecar **尚未重新生成**，避免混入引擎
shader 复用 ABBA。补齐 mip 链会增加压缩文件和上传字节，通常接近额外三分之一；应以
重新生成后的实际文件统计，不能沿用旧资源成本。

编辑器 UI 和当前 3D MCP 的 `import_surface_material` 均复用
`SurfaceMaterialLibrary.import_texture()`，它把解码后 PNG 发布到内容 SHA 路径。
重复导入发生像素变化时换新路径，旧 PNG/DDS 不覆盖，旧 sidecar 缓存不会跨路径命中。
显式 `Paint.refresh_sources()` 现补清正、负 sidecar 缓存；未增加运行时 stat/hash、
全包校验或未存在的 UI 刷新功能。

DDS/BC1/BC3 属于**有损压缩**。早先截图不能代替完整法线、透明边缘、近中远过滤和 mip
验收。后续固定 Vulkan 近中远/斜光对照发现 BC3 法线黑斑/噪点不合格；同块预算的
BC5(RG) 在 natural_dirt、sandstone_floor、outdoor_flagstone、solid_timber 四个代表
候选通过，并验证候选材质保存重开。该代表试验时正式包未转换，其他法线留到后续逐项视觉复验。
运行时已补齐 normal 角色键贯穿入口、准备、发布、弱缓存、失效及真实等待后的续作；
不能让 BC5 误用于同源颜色图。旧 DDS 固定测试期间的一次真实地图 prime 暴露续作仍
重建双元素请求，独立两 worker 队列红测复现后修为三元恢复，32 项通过；该失败
prime 不作为性能样本。生成器也改为保留同源另一角色的 sidecar。
详见 `docs/axel_editor_dds_adaptation_20261025.md`。

后续按明确的 74 源清单完成正式派生文件迁移：88 个 DDS 均有旧字节/SHA 备份，实际
安装 88 文件共 **328,566,704 B**，退役 34 个 normal-only 旧 DXT；源图片/地图 SHA
未变。54 个颜色 DDS 顶级块 payload 保持原字节，仅新增 mip；20 个实际选用法线均做
StandardMaterial3D 固定近中远/细节及保存重开对照，BC5 未见非预期损失。实际目标 SHA
与画质候选一致，凭据为 `editor_dds_20261025/map_stage01/published.json`/`reviewed.json`。

最终自审另补 BC5 自定义 shader 合同：地形 6 层和水此前直接使用 B 通道，会把 BC5 的
缺省 B 当作真实 Z。实际 `River.bind`/地形 shader 红测 144 项中 78 失败，修复后 144 项
全过，像素平均误差从 0.098–0.170 降至 0.00034–0.00048；PNG 原路径 11 张前后画面
逐字节相同。每次纹理创建记一次格式 metadata、材质绑定记 uniform，仅 BC5 重建 Z。
这属于正确性和完整接入，不把增加 mip 所带成本误报为纯性能收益；最后实际地图累计
状态由主性能记录另行报告。

## 2026-10-25 累计复测与下一处卡点

本轮保留两项已独立证明的性能修改：原生 StandardMaterial 的有限闲置 shader 复用，地图返回变体创建从 17 次降到 10 次；地形遮罩只计算羽化带，17 个真实区域的精确线段查询从 48,237,376 降至 237,634，输出逐字节一致。固定旧 DDS 的 ABBA full-ready 均值 20.764s→13.392s，减少 7.371s。该因果证据不能代替下面新 DDS 的累计结果。

已完成编辑器/运行时纹理角色、刷新、后台只读查询、续作及 6 层地形/水 shader 适配。74 个源的 88 个 DDS 正式发布、旧文件 SHA 备份完整；20 个实际法线与 4 个实际自定义地形 shader 代表对照通过。尺寸、格式、完整 mip 合同及 PNG 分支字节不变等详情以专项记录为准。地图、源图片未修改。

最终先单独 prime 派生目录（19.656s，不进入下表），全组冻结生产脚本、shader 及已安装的 DDS；逐轮及前后来源检查均通过。普通优先级、未改 QoS、未清 OS cache，几何/边界/模型元数据缓存按既定夹具关闭。F1/F2 使用 eaec，F3 使用只叠加 DDS 读取修复的 52f532；没有据两个不同 exe 的时间相减归因。

| 样本 | 入口 | full-ready | 卸载 max / >50ms 帧 | 返回 max / >50ms 帧 | 重载 max / >50ms 帧 |
| --- | ---: | ---: | --- | --- | --- |
| F1 | 8.397s | 25.472s | 81.507ms / 9 | 85.605ms / 6 | 39.847ms / 0 |
| F2 | 5.542s | 13.893s | 35.796ms / 0 | 73.794ms / 1 | 45.496ms / 0 |
| F3 | 8.606s | 19.147s | 29.783ms / 0 | 73.664ms / 1 | 45.838ms / 0 |

所有功能断言通过，源脚本/地图未变；88 个已安装 DDS 前后 SHA 全部匹配。三轮均 shader 创建 10 / 复用 7；实际上传 **995,359,496 B**，其中 DDS **430,617,304 B / 124 次**，其余 **564,742,192 B / 46 次**。补齐 mip 及法线格式后，实际上传比旧 DDS 对照的 862,537,776 B 增加约 15.4%；这是恢复过滤/法线正确性的成本，不能宣称这轮上传进一步下降。此数是多阶段累计提交字节，不是峰值 VRAM。

F2/F3 均退休 504 单元 / 3677 specs；F1 为 503 / 3672，完整功能断言仍通过，但动态预测/时序工作量并非逐项完全相同。三轮不足以宣称 p95 稳定；F1 同一 eaec 比 F2 慢 11.579s，保留慢样本，原因未确认。F1 初始 shader 首次提交约 267–338ms，F2 约 156–187ms，说明不能把全部波动简单归为 DDS 字节增加。

返回 73ms 已定位到 Deferred **publication**：F2 71.527ms，F3 71.019ms；join 分别 24/18µs、sync 为零。本轮尚未取得这个发布子段的完整原生栈，不把它归为 OS 空闲或“仍在等上传锁”。F1 卸载提交最大 75.659ms；F2/F3 为 32.719/26.664ms，最大需求刷新为 39.992/22.583/31.615ms。下一处重点是发布的这约 71ms 及完整加载波动，已有工作量收益保留。

新引擎白模单次回归入口 3.002s、full-ready **7.176s**，纹理上传计数为零，功能通过；这是一次正常缓存条件下的入口测试，不重新宣称 cold p95 或白模卸载全量验收。F1 地图截图按原尺寸 lossy WebP quality90 保存、绑定 SHA 并查看：道路/地表可见，导入建筑仍白色占据较大画面。该图不等于完整模型贴图、全部地形或天气画质验收。

新增发现并修复了 MockServer 同步/提前访问时的资源回调互等；独立红绿及两次退出泄漏警告边界见专项。它不计入关闭 MockServer 的地图性能收益。

专项入口：

- `axel_editor_dds_adaptation_20261025.md`：编辑器、法线、mip、资源发布与画质。
- `axel_material_shader_residency_20261025.md`：GDB、原生 shader 生命周期、ABBA。
- `axel_terrain_mask_band_20261025.md`：重复计算、逐字节 oracle、地图 ABBA。
- `axel_dds_partial_blocks_20261025.md`：非 4 倍数尺寸读取红绿、Vulkan、安装的 exe/symbols。
- `axel_mock_server_shader_wait_20261025.md`：启动互等、同步与提前访问回归。

当前未处理完：纹理完整加载波动；返回 publication 约 71ms；卸载慢样本；提前访问用例的偶发 4 ObjectDB 退出警告；10 张 1254×1254 源的 sidecar 转换接入（引擎已修，生成器尺寸过滤仍在）；导入模型完整材质和外围系统仍未恢复。不能宣布纹理阶段完成。

最终证据：`material_submit_review_20261025/editor_dds_final_{prime,F1,F2,F3,white}.*`、`editor_dds_final_summary.json`、`editor_dds_final_assets_verified.json`、`editor_dds_final_slow_frames.json`、F1 WebP SHA/quality 收据。

## 2026-10-25 DDS 后台准备补齐

上一节“返回 publication 约 71ms”的下一轮证据和修复已完成，详见
`axel_dds_worker_publication_20261025.md`。官方 profiler 抓到真实 `_mesh → _texture`
同步读取 12 个 DDS；原来三个准备入口主动跳过 DDS，既没有提前读取，也没有走已有
逐张发布。现在游戏和编辑器复用 CPU-only BC1/BC3/BC5 完整 mip 读取，进入已有
去重、预算、取消和发布流程。未修改源图、DDS、地图或引擎。

固定同一 52f532 引擎和 88 个已发布 DDS，正常 ABBA 全部功能通过：

- full-ready 旧组 14.655/17.923s，新组 15.232/13.400s；均值 16.289→14.316s。
  两样本不足以证明稳定收益，B1 比相邻 A1 更慢的样本保留。
- 返回最大帧 72.411/100.043ms→41.344/41.874ms，返回 publication
  70.156/97.175ms→29.325/24.166ms；新组返回与卸载均零帧 >50ms。
- 上传仍 170 次，已有 DDS 的采用范围补齐使累计字节
  **995,359,496→721,332,072 B（-27.53%）**，主线程 DDS 重读为零。
- 新组仍有一帧重载 **51.271ms**，没有标成 OS 空闲或已解决。material miss、
  最终路径/来源身份检查次数反增，专项明确列出，后续需继续精简。

接入时曾因 shared pool 假定 DDS 行存在 PNG cache_limit 而持锁报错、阻塞生产者；
该失败整图、GDB 栈和独立红测均保留，修正共享预算合同和锁范围后重新跑完整 ABBA。
独立压缩发布 115、共享压缩队列 27、原共享队列 32、CPU helper/editor 271、PNG
发布 103、材质发布 64、texture tickets 18、原 prefab pixels 63 项通过。

按用户提出的“网格加载同时把纹理准备在内存”的方向补了实际代码检查和独立测试：
MapLoader 初始入口已有并行，本轮让 DDS 也真正参与；后续 ChunkReferencePreparation
仍是几何后接纹理。两个真实完整建筑组各 8 次串行/并行对照，几何/像素指纹与工作量
相同；四样本中位数分别 316.682→279.789ms、317.446→189.704ms。该工具验证 CPU
重叠空间，**区块生产调度尚未拆分接入**，不能把单组收益换算为整图收益。下一实现
仍必须受同一 worker/内存准入限制并沿用共享生产者，避免线程和工作量乘法。

## 2026-10-25 区块网格/纹理并行正式接入

上一节的“区块生产调度尚未拆分”已由本轮完成，详见
`axel_chunk_texture_parallel_20261025.md`。原来的一个区块 bundle 同时持有几何和
像素准备，只有总 worker 额度允许且本任务是唯一像素 producer 时拆为两条 CPU
任务；半完成归还执行槽，完整 join 后才移交发布或回收，未增加输出字节预算。

同时消除两项重复工作并修正取消接管：

- 每操作按唯一纹理角色复用 header plan；整图约 4000 个请求键只读 85 份唯一
  元数据，累计主线程规划约 2s→89ms，目录预留 16MiB 从同一预算扣除。
- 失败像素生产者可在完整工作区重新准入后移交原共享 lease；可信包首次/重试
  不因是否带 revision 分裂成两个共享身份，旧 worker 未 join 前不提前释放。
- 官方 profiler 重载捕获一次材质失效中的 937 次网格材质扫描。按本次通知内的
  Material 身份复用结果；独立 512 网格压测定义检查 1536→32，中位数
  12.254→2.958ms，下一次编辑仍重新观察定义。

独立红绿、PNG/DDS 两 worker 阻塞/取消/退出、原有 493 项准入、真实 GPU 材质
发布及编辑器 HTTP 保存重开都通过。所有整图保留不稳定/慢样本：map02 两项累计
候选 full-ready 15.081/14.886s，但取消接管后的 map03 又出现 25.159/19.951s，
不能据均值宣称稳定提升。最后追加材质失效复用的 map05 完整就绪
**14.219/15.865s**；卸载 max 43.036/60.327ms（>50 为 0/1），返回
61.040/53.151ms（6/1），重载 86.552/52.741ms（7/2）。功能和回收全部通过，
170 次 / 721,332,072 B 上传不变；这些仍包含未解决长帧，完整边界见专项。

当前已明确的剩余方向是需求刷新约 35–48ms、初始合批收尾和原生材质/网格提交，
而非只继续增加像素线程。官方 profiler 保留加载 cover 内 468.577/158.449ms
的 surface_set_material 区间和 316.490ms 的 batch upload Object.set，内部仍
需进一步原生栈归因。后台/嵌套累计函数耗时不能相加为主线程或总加载时间。
卸载、返回、重载的所有最大帧和 >50ms 帧数按样本列出，纹理阶段尚未完成。

## 合批尾段 / 原生 shader 提交（接续）

见 `axel_batch_tail_respv_20261025.md`。逐阶段时间线表明合批尾段有空闲预算交接
缺口，但不能解释全部入口后等待；另保留一次首次纹理 header plan 2.134s 的主
线程阻塞。GDB 已将部分 `surface_set_material / _set_surfaces` 定位到引擎
re-spirv 的解析、内联、排序及重复 TLS 查找。

TLS 局部引用候选在 32 份真实 shader 输入上约减少 32% 处理时间，逐字节输出
一致，原版与候选各 768 项通过（每组 6 线程）。真实 GPU 材质/合批回归通过。cover 下 idle 纹理
尾段接入原有 streaming + batch 共享 6ms，交互预算不变，13 项新测试通过。

完整 A/B/B/A 的候选 **16.588/11.521s**，对照 **12.184/12.034s**，不能
宣称整体稳定通过。两引擎都执行过后的补充 warm 对照候选 **11.318/11.332s**，
对照 **12.435/11.908s**，平均少 **0.847s（7%）**。所有慢样本保留，不作为
cold/p95。GPU 上传仍 170 次 / 721,332,072 B；候选 reload 各两帧 >50ms，
最大 **62.158/57.916ms**，这组低帧仍待优化。该阶段引擎候选先保留独立目录。
完整帧分布、工作量和测试宿主修正见专项文档。

后续原始 UV 路径去掉未使用的面投影与重复变换构造，37 项逐字节对照通过；
32,768 三角形组件微测约 38.5 → 0.93ms。修复明确失败纹理通知未撤销磁盘
像素缓存的问题，不增加正常加载校验；CPU 13 项、GPU 35 项、编辑器 HTTP/UI
76 项通过。修正了旧编辑器测试仍假定 reference glTF 烘焙运行纹理的合同。

`map22` 同候选引擎、只切换 UV 的 ABBA：候选完整就绪 **11.197 / 11.166s**，
对照 **13.419 / 11.385s**；首轮对照入口偏慢，不把整个差值归给 UV。重载 p99
对照 **35.303 / 37.019ms**，候选 **33.486 / 34.512ms**；1% low 均值约
**25.574 → 27.034 FPS（+5.7%）**。候选卸载/返回/重载无 >50ms 帧，但四组
就绪后均有一次 **52–59ms draw 等待**，无该帧栈，仍未结案。每组 GPU 上传
170 次 / 721,332,072 B，所有最终预算和 worker 归零。不是 cold/p95 稳定性结论。

上述回归后已把 TLS 候选 exe、别名和匹配调试符号安装到 `D:/tools/godot`；
旧文件逐字节备份到 `_backup/respv_tls_20261026/`，安装 SHA/版本检查通过。
仍需解决首次 header IO、卸载同步 join/导航移除，以及 paint 拓扑/边界重复工作。

## 异步纹理头部读取（2026-10-26 接续）

见 `axel_async_texture_headers_20261026.md`。首次 source metadata 读取接入现有
worker/byte admission，按来源共享、乱序完成、取消后保持计费直到退出。独立
暂停一个 worker 时另一个可完成并继续接活；256 来源恰好 256 次读取、配额归零。
CPU 相关回归及 GPU 107 项通过，未改变材质、地图或上传格式。

完整 `map07` ABBA：同步完整就绪 12.089/11.128s，异步 11.067/11.355s，
范围重叠，不能断言稳定加载收益。主线程头部计划 max 12.6–16.9ms 改为约
0.4ms，异步派发 max 1.1–1.7ms；85 个唯一来源无重复读取，上传仍 170 次 /
721,332,072 B。但重载 1% low 均值 **27.47 → 25.65 FPS**，候选各一帧
50.1–50.2ms；保留退步样本继续查 geometry tick 与提交，不能称整体低帧改善。
卸载/返回无 >50ms；steady draw 等待及私有数组释放仍未结案。

## 卸载后台准备实验与新热点（2026-10-26 接续）

详见 `axel_retirement_selection_20261026.md`。完成了分帧快照、共享预算内单 worker
准备、完成即归还槽位、取消后保留所有权、最终主线程提交的候选，并跑独立压测、
真实导航/索引回归、完整地图 ABBA 与官方 profiler。

结果没有证明净收益：正常地图卸载事务 max 仍约 27–28ms，候选另加约 34ms 快照
复制及 12–13ms 最终 equality。官方记录确认 join 降至 0.012ms，但核对成本替代了
等待。运行候选撤回至 b337b900，完整补丁及失败样本归档；此前有效优化继续保留。
本轮完整加载仍为 11.164–11.466s，不是低于 10 秒的完成结论。

新证据：重载帧内材质缓存裁剪调用 16 次 / 23.745ms，伴随 8068 次排序比较和重复
纹理属性读取；返回需求刷新仍达 44.502ms。优先独立复现重复缓存维护，再改候选集合
维护。对照出现一次 364.936ms 卸载帧（process 15.883ms），尚无该帧线程栈，
不能归为已确认的 OS/GPU 问题或计作候选收益。

## 材质缓存重复维护（2026-10-26 接续）

详见 `axel_material_cache_trim_20261026.md`。热缓存新增资源按唯一 ID 增量登记
成本，未超预算不再全量扫描/排序；job 已持有的纹理 ticket 先弱交接，实际使用
时再进入热缓存。256MiB 预算、失效和最后引用释放语义保留，生产不新增资源校验。
先恢复整包热引用再裁剪的失败候选及其退步数据完整保留，没有仅凭微测放行。

最终独立测试 5780 项、七组 GPU/编辑器回归 321 项通过。`map10` 完整 ABBA：
全量核算 386/378 → 35/35 次，成本读取减少约 88%；GPU 上传保持 170 次 /
721,332,072 B，最终所有 worker/像素/retirement/admission 归零。
正常完整就绪候选 11.058/11.240s，对照 13.384/11.162s（首轮入口偏慢）；
重载 1% low 两组均值均约 26.479 FPS，**未证明稳定加载或整体低帧收益**。
候选卸载/返回无 >50ms，但重载仍有 50.235ms，静止段仍有 51.5–62.3ms 未归因帧。

官方 profiler 另证缓存裁剪累计 340.547 → 56.468ms、单帧 max 23.745 → 11.593ms。
重载的新证据是 `_candidates` 17.397ms、`_collect_meshes` 6.892ms；测试工具
`track_membership` 也可达 16.042ms，须区分生产与测量路径。返回需求刷新 max
31.947ms、首次 cover 内材质提交 327.871ms、私有数组释放仍待后续处理。
本轮按工作量收益保留，目标继续，不等同纹理阶段已达标。

## 根节点变化与重复区块计划（2026-10-26 接续）

见 `axel_stream_adoption_20261026.md`。辅助节点变化过去会重新遍历整张场景树，
并丢弃区块增量计划。现按新增子树登记，空 adoption 保留已有游标；真实新模型、
显式失效、离树后重入及删除修复仍保留。撤去会增加约 15ms 释放成本的逐节点退出
监听。独立语义与关联逻辑 170 项、GPU 流程 179 项通过；修复旧测试接口和缺少
native 产物的测试 fixture，没有恢复游戏 GLB fallback。

`map09` 完整 ABBA：对照完整就绪 11.456/11.217s，候选 10.904/10.766s；本组均值
**11.336 → 10.835s（-0.501s / 4.4%）**。重载 1% low 均值 **25.024 → 27.283 FPS**，
但卸载 1% low 略退步，候选仍有一帧 50.920ms 重载帧；不是稳定 p95 或低于 10 秒
的完成结论。完整树扫描 6/5 → 1/1，adoption 均未发现新 spec；上传仍 170 次 /
721,332,072 B，最终全部预算与 owner 归零。

官方 profiler 的 collect 累计 16.066 → 0.010ms，adopt 16.402 → 0.373ms。
仍有受控删除后一次 20.729ms 完整候选计划，下一步先复现并修复该计数交接，
再继续需求刷新 37.530ms、卸载 join 10.421ms / 导航移除 14.153ms、以及首次
cover 内材质提交 335.572ms。保留正常静止段 56–58ms 未归因样本及入口失败记录。

## 2026-10-26：自身卸载切帧不再丢弃计划

见 `axel_stream_owned_removal_20261026.md`。修复 `_apply` 慢于 10ms 提前返回时
遗留的旧子节点计数；只在已知直属节点删除事务中扣减，保留未知删除/显式失效
修复，不引入逐节点退出监听。独立语义与逻辑 190 项、GPU 179 项通过。
20 次卸载额外选择 69,790 → 0，额外同步约 336 → 0.29ms。

真实地图受控复现确认：同样注入一次 11ms 卸载等待，对照下一帧重选 3,940 个
候选、游标退回 0；修复保留 3,941 项计划、游标 1 → 14，卸载全量候选扫描为 0。
这是调用链修复证据，不能把受控诊断帧 40.107 → 11.353ms 冒充正常帧提升。

正常 `map06` ABBA **没有显示总耗时/FPS 收益**：完整就绪均值
10.643 → 10.840s，重载 1% low 27.099 → 25.713 FPS；卸载/返回均无 >50ms，
候选仍有一帧 51.399ms 重载及 62–64ms 未归因静止样本。上传均为 170 次 /
721,332,072 B，全部样本功能通过；慢样本和失败夹具记录完整保留。

本轮保留的是已复现的重复工作收益。下一步重点为需求刷新 36.716ms（self
25.494ms），继而卸载导航/索引提交、初始材质提交 310.420ms 和重载 native
网格上传 30.546ms；不得据此宣布目标完成。

## 2026-10-26：复用候选槽位与未变化调度表

见 `axel_demand_catalogues_20261026.md`。实际返回快照和 GDB CPU 回放确认了
重复 Dictionary/Variant 工作；候选哈希槽位复用，精确相同的 owner、rank、
priority、path 才复用调度表。错误/发布/重试间隙先复现再补失效，发布游标和
预算语义保留。独立逻辑 1262 项、GPU 179 项通过，末次清空改动后再复验 67 项。

同一真实输入直接对比上一提交原始源码，24 次刷新均值 **103.438 → 89.670ms
（-13.3%）**，输出与输入工作量一致。正常 `map14` ABBA 候选槽位插入由
263424/249718 降为 3717/3973；全部纹理唯一来源 85、上传 170 次 /
721332072 B 不变，最终共享像素与 owner 归零。移动异步工作次数并非全部相等。

完整加载均值 **10.865 → 10.827s**，不足以认定显著加载收益；重载 1% low
均值 **26.389 → 26.974 FPS**，返回则 **49.725 → 48.713 FPS**。候选卸载/
返回/重载无 >50ms，静止段仍有 54.141/56.526ms 未归因帧，未达整体完成条件。

官方 profiler 的需求刷新 total 累计 **5770.965 → 5757.658ms**，max
**36.716 → 38.888ms**；新比较函数的成本已包含其中，不能用 self 下降掩盖它。
下一轮优先处理仍可复现的实际材质提交 **310.778ms** 与初始尾段关键路径；
需求刷新、卸载同步等待与静止尖峰继续保留为未解决项，不重复无效隐藏 mesh 预热。

## 2026-10-26：shader 交接复制、RD 锁与候选容量漏验

见 `axel_shader_transfer_20261026.md`。GDB 复现主线程在 RD mutex 等待，
同时 worker 在 shader container 解码/re-spirv 解析；源码确认该 CPU 工作仍
在设备锁内。去掉两次解析结果深复制可减少工作，但不能视为解除这条等待链。
带 GDB 的超时失败和 367/289ms 未归因普通帧完整保留。

engine06 的直接 move 增加了捕获样本 vector 容量 8.7%，整图未证明收益。
engine15 尝试 `shrink_to_fit`，GPU 三组和 shader residency 36 项均通过；
整图 copy/shrink-move/shrink-move/copy 的完整加载为
16.117/17.289/11.111/10.897s，前两组存在已观察到的其他 Blender 任务重叠。
候选两次卸载/返回/重载无 >50ms，但仍有静止/离开尖峰；不能宣称稳定改善。

原生计时进一步暴露了独立测试的编译选项缺口：Godot 的 `-fno-exceptions`
使本机 libstdc++ 的 `shrink_to_fit` 成为空操作，engine15 未真正恢复紧凑容量。
已在同选项测试中复现并改成显式数组构造/交换，容量恢复与 copy 一致，46 份
优化结果 SHA 相同，交接中位 1.49–1.68 → 0.42–0.46ms。
仓库保存修正版补丁，隔离 engine22 已构建、三组 GPU 和 36 项 shader
residency 复验通过，首次地图 15.264s 单独保留。固定 ABBA 四组功能通过，
完整加载均值 10.955 → 10.839s，重载 1% low 27.032 → 26.950 FPS；不能宣称
稳定整体提升。候选返回仍有 52.335ms，其中需求维护 29.240ms；静止仍有
54.450/57.587ms。上传都为 170 次 / 721332072 B，异步模型/实例次数并非相等。
本轮按工作量收益保留补丁；默认安装仍为 `0f0bf446…`，未替换常用引擎。
最终候选原生诊断保持相同 688 个容器，入口+stream 数据交接累计
280.218 → 70.761ms（-74.7%）；该值含后台且与壁钟重叠，不当作整图省时。

后续优先分离锁外 CPU 准备与锁内资源提交，并验证独立任务、失败清理和实际
GPU 输出。目标继续，加载和低帧均未完成验收。

## 2026-10-26：shader 拆锁实测及碰撞调试外观的重复 BVH

见 `axel_shader_cpu_prepare_20261026.md`。每次调用私有的 Vulkan container
解码 / re-spirv 准备已从 RD 锁拆开；固定工作量压测壁钟均值 447.899 →
293.178ms，真实单 worker 暂停试验中另一 worker 完成 128 次创建、主线程
持续推进。GPU 及错误 / 重试检查通过。但补测整图完整加载均值 10.896 →
11.242s、重载 1% low 26.931 → 24.657 FPS，没有整体收益，候选不安装。
含其他 Blender / Godot 重叠的上一组慢样本也保留，不拿独立试验代替整图。

返回重载 GDB 又捕获主线程 BVH 重建：节点绑定传播默认 debug color，
虚调用凹多边形 `_update_shape`，让已接收的后台准备产品再次被 faces-only
物理更新取代。见 `axel_collision_debug_refresh_20261026.md`。改为只调用
Shape3D base 的调试 cache 刷新后，同操作 GDB 计数 BVH **40 → 3**，
调试刷新 **40 → 40**；四组各 49 项独立语义检查和 149 项 GPU 回归通过。
绑定独立负载约 30ms → 0.043–0.046ms。整图四组功能通过，但全程出现
其他 Blender / Godot 重叠，性能不作为严格对照；候选仍有 78.765ms 返回
和 70.890ms 重载帧。已修正 PID 重用导致的负载归属问题，原记录保留。
shader 拆锁在最终候选默认关闭、保留显式开启方式；碰撞修复默认开启。
最终默认配置再通过 198 项检查，但首次地图烟测 **22.334s** 尚未归因。
候选保留，默认引擎尚未替换；不能将独立工作量收益当作整图目标完成。

## 2026-10-26：关机前暂停交接

用户要求本轮收尾后停止，记录摘要与下一轮方向；目标按用户要求暂停，
不启动新一轮地图测试、编译或 GDB 捕获。整体加载与 low 帧优化尚未完成。

### 工作区与已保存成果

- 工作区：`C:/Users/luna/.codex/worktrees/map-load-render-review/rmmo`。
  `D:/code/rmmo` 是另一 checkout，恢复时不要混用。
- 分支：`codex/latest-map-runtime-review`；实现提交
  `b65c84a6b518c94998d00d550542ee405e0b8209` 已推送同名远端分支。
- 碰撞修复：调试颜色 / 填充更新仅刷新 Shape3D 调试数据，不再虚调用
  凹多边形几何重建。GDB 实际 BVH `_setup` 次数 **40 → 3**，调试更新
  **40 → 40**；保留后台初次准备、backface 编辑和几何编辑。
  独立绑定约 **30ms → 0.043–0.046ms**，最终默认配置 **198 项通过**。
- shader CPU 锁外准备：独立固定工作量均值 **447.899 → 293.178ms**，
  暂停一个 worker 时另一个可继续完成工作。但整图均值 **10.896 →
  11.242s**，重载 1% low **26.931 → 24.657 FPS**，没有整体收益。
  实现保留，最终候选默认关闭，仅 `RMMO_SHADER_PREPARE_UNLOCKED=1` 开启。
- compact shader transfer 保留已证明的数据交接工作量收益；碰撞修复默认开启。
  不能把独立压测收益当作真实地图验收完成。
- 详细机制 / 复现：`axel_collision_debug_refresh_20261026.md` 和
  `axel_shader_cpu_prepare_20261026.md`。

### 引擎与证据恢复位置

以下 `Q` 表示：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/collision_debug_20261026`。

- 候选 `Q/engine09/godot.windows.editor.x86_64.exe`，SHA256
  `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`；
  配套 symbols SHA256
  `3039c3ba7fbb71f965ec42cb9100a483a439e95b6cfda3ed194cfae54989db76`。
- 常用 `D:/tools/godot` **未替换**，已核对 EXE SHA256
  `0f0bf4469c70de8d051b1e6d22293ed508e077bf1c1a326c6291d50890e583e0`。
- `Q/install12.py` 只是准备脚本，**未执行**；先完成性能归因及安装事务 /
  失败处理审查，不能恢复后直接运行它。
- 引擎源码 `D:/tools/godot-profile-build/source/godot-4.7.2-stable` 不是
  Git 仓库；补丁已保存到项目 `tools/engine_patches/`，源码身份见
  `Q/sources08.json`。不要把源码变化与旧二进制样本混淆。
- `map07` 四组完整遍历均功能通过，但运行中出现其他 Blender / Godot
  负载，不能作严格性能对照。正确负载汇总是
  `Q/host07_summary_identity.json`；旧 `host07_summary.json` 有 PID 重用
  归属错误，禁止继续用于逐组归因。原始记录保留。

### 本次收尾补充的只读比较

对 `Q/first_default11.json` 与 `Q/map07_B2.json` 提取已有数据，未启动新测试。
两者不是受控 AB 对照，下面只用于选择调查点：

| 指标 | first_default11 | map07_B2 |
| --- | ---: | ---: |
| entry | 8.354262s | 3.931328s |
| 当前需求完整就绪 | 22.333824s | 10.475882s |
| asset_parse_wall | 1.424887s | 0.635434s |
| mesh_us | 1.748888s | 0.500154s |
| build_total | 2.191713s | 1.137442s |
| cpu_restore_profile 中 material_us 最大跨度 | **919.560ms** | **101.572ms** |
| 初始 paint.texture.upload 累计 / 次数 | 234.748ms / 85 | 172.984ms / 85 |

`material_us` 是记录到的调用壁钟跨度，不等于已经确认的主线程 CPU 工作，
也不能自动称作帧耗时。阶段包含、并行与等待关系尚待核对，不能把表中数字相加。
first_default11 没有独立 host 观察器，**22.334s 仍未归因**，不能宣称
已证明是修复回退、外部负载或驱动冷缓存。对照 B2 也不是严格冷启动。

### 下一轮按此顺序推进

1. 恢复后先检查 Git、候选 EXE / symbols、地图和脚本身份。固定当前完整
   就绪口径，保留第一条 / 慢样本，不删除旧结果或复用输出文件名。
2. 用 engine09 默认配置复测，关闭原生逐容器诊断；同步只读记录本次进程
   的 PID **和创建时间**、其他负载、CPU、磁盘 / 进程 I/O。记录进程与地图
   计时锚点。只等待适当测量窗口，不终止用户或其他会话的任务。
3. 优先拆解 **919.560ms 材质跨度及 22.334s 首次慢样本**：沿入口、后台
   准备、主线程发布、批次收尾定位关键路径，再用官方 profiler / GDB
   抓对应主线程和渲染线程，区分计算、锁等待、驱动首次提交及调度延迟。
   GDB all-stop 样本不能当普通帧率；避免密集全线程抓栈吞掉大量运行时间。
4. 对确认的原因建立独立复现后修复，再回真实地图做固定口径对照；继续处理
   需求刷新（已出现 73.450 / 55.828ms）和返回 / 重载长帧。分别报告完整
   加载、各阶段帧最大值 / >50ms 数量 / 1% low、模型 / 实例 / 上传工作量。
5. 碰撞补丁需要无明显竞争负载的整图对照后再决定常用引擎替换。shader
   拆锁保持 opt-in，不能只凭独立压测转为默认。现阶段也不能宣称 low 帧
   或总加载已达标；纹理范围仍是地图 / 预制件纹理，导入模型材质保持白模。

加载边界继续采用“地图加载计时开始 → 当前需求连续三帧几何、任务、合批及
共享像素消费者 / 保留字节清空”。几何 / bounds / metadata 派生缓存关闭，
native / dependency index 和纹理磁盘缓存保留、OS 缓存不清，不能标成物理冷盘。

收尾进程检查未发现 Godot、GDB、Blender、SCons、编译器或 Python 进程；
本会话没有需等待完成的测试、编译或调试器。未操作用户其他任务。

## 2026-10-26 晚：材质字段表复用完成，本轮停止

完整记录及下轮接手入口：
[`axel_material_schema_reuse_20261026.md`](axel_material_schema_reuse_20261026.md)。
用户要求做完本轮停止，保留未解决问题，等待恢复，不启动下一轮。

- 官方 profiler 确认材质打包 / 合批摘要重复构造完整原生属性表。现在共享
  最多 64 份只读字段名表，值实时读取；脚本 / 未审阅引擎版本回退原生枚举，
  保留元数据顺序、保存字节和合批摘要。最终 **7028 项通过**，另外 5 组
  缓存、材质和 GPU 回归通过，未改用户地图或资产。
- 整图 A1 / B1 / B2 / A2 加载为 **11.192 / 10.685 / 11.037 / 11.807s**。
  cache pack **138–179 → 33–47ms**，新路径仅构建 2 份字段表。
  保留工作量收益；样本不足以声称稳定低于 10 秒或 p95 改善。
- 新路径两条卸载 / 返回 / 重载均无 >50ms 帧，但静止分别有 **60.150 /
  63.006ms**，原因未确认。旧路径 A1 遍历与其他 Blender 重叠，不能据该
  组声称 low 帧提升。全套慢样本及负载身份记录保留。
- 恢复后首条 **17.118s** 对后续 **10.624s**：初始模型 / 实例相同，67 次
  纹理 header 累计 **6.178s / 0.068s**，合批 rebuild **286 / 217**。
  读取等待和额外构建是下轮首要复现方向；后台累计跨度不能相加为壁钟。
  更早的 22.334s / 919.560ms 样本仍未再现，未宣称根因已解决。
- 候选仍为 engine09 `40554844…`，本轮没有改 / 编译 / 安装引擎；shader
  CPU 拆锁保持默认关闭。所有本轮测试已正常退出，无需等待后台任务。

下一轮顺序：**可控延迟复现首次读取与重复合批 → 材质原生提交 → 静止及
遍历低帧归因**。继续先复现后修复，再固定就绪口径对照，不从头重跑已经
证明的微优化，不将独立工作量减少冒充整图目标完成。

## 证据目录

外部目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/`。

前述材质发布分片代码阶段不修改正式地图、源纹理、模型几何或native产物；后续 DDS
派生资产阶段另有有损压缩与上述待验边界。材质分片的受影响项验证使用相同图片的实际GPU回读，检查完整mip、normal方向、alpha及
共享身份；这不代替之后完整模型材质阶段的画面验收。
