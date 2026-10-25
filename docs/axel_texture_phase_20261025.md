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

## 离线 DDS sidecar：上传量降 75%

按授权对现有 pack 纹理做**附加式**离线 GPU 压缩，不修改源文件：

- `tools/generate_texture_dds_sidecars.py` 生成 `.dxt1.dds`/`.dxt5.dds` 与 normal
  的 `.flip.dxt5.dds`；源 PNG/JPEG/WebP 不变，删除 sidecar 即回退。
- 现有 pack 扫描 631 张：写 655 个 sidecar，66 张因尺寸不是 4 的倍数跳过。
- 修正 Pillow 的 DDS `pitchOrLinearSize`（Godot 期望 DXT block linear size）。
- 运行时 `SurfaceMaterials._texture` 优先加载 sidecar；`_prefab_texture_plan`
  不再为已有 sidecar 的路径派发 shared-pixel GPU 纹理任务。

`map_traverse_26`（带 texture profile + screenshot）：

- upload_bytes 约 **2.29GB → 564,742,192**（约 **-75%**）
- sidecar uploads 124，sidecar upload 累计 226ms，max 15.4ms
- material 累计 378ms（旧约 9s）
- full-ready 18.611s；截图地面/石路纹理正常，failures 空

5 个普通 sidecar 样本 full-ready：17.264、17.613、18.742、19.294、18.611s；
reload max 45–55ms（旧 192ms），但 return 仍 353–672ms。也就是说 sidecar 主要
降低了纹理上传/重载，未消除 Stream.sync 的 return 几何尖峰。源地图/纹理未改；
sidecar 是可选离线资产，需要随 pack 一起分发。

## 证据

外部目录：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/`。

本轮不修改正式地图、源纹理、模型几何或native产物，不做降分辨率/有损压缩。材质
分片的受影响项验证使用相同图片的实际GPU回读，检查完整mip、normal方向、alpha及
共享身份；这不代替之后完整模型材质阶段的画面验收。
