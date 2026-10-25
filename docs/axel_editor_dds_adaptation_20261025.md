# DDS 派生纹理与编辑器适配复核（2026-10-25）

基线：`4c2ba020`。本次与引擎 StandardMaterial3D 闲置 shader 缓存优化分开验证。
没有改地图、模型几何、源 PNG/JPEG/WebP。完成外部候选对照后，已按清单更新正式包中
74 源的 88 个派生 DDS；原文件均有 SHA 备份。最新状态与自定义 shader 接入边界见文末。

## 已修复问题

| 问题 | 原因 | 修复与边界 |
|---|---|---|
| DirectX 法线方向错误 | `.flip.dxt5.dds` 使用 `ImageOps.flip`，反转了图像行 | 仅将 G 改为 `255-G`，保留 R/B/A 与 UV 行位置；原图不修改 |
| DDS 缺少 mipmap | Pillow 每次只保存顶层，旧头部 mip 数为 0 | 离线编码完整链到 1×1，写正确 mip flags/caps/级数；颜色 BC1/BC3，法线候选 BC5 |
| 重建后仍读旧透明版本 | 不透明新 DXT1 与旧 DXT5 共存，运行时优先 DXT5 | 显式 `--overwrite` 全部要求编码成功后才清理同角色废弃编码；单文件先编码、再原子替换，保留同源另一角色 |
| 刷新后找不到新 DDS，或继续使用旧路径缓存 | `Paint.refresh_sources()` 漏掉 `_sidecar_cache` | 与现有材质/纹理强弱缓存一起清正、负 sidecar 缓存，不增加每次文件查询 |
| 总上传字节漏计 DDS | 压缩分支只计上传次数 | DDS 字节同时加入 `paint.texture.upload_bytes` 总计和 `paint.texture.sidecar_upload_bytes` 分项；缓存命中不重复计 |

没有新增纹理校验、包 hash 扫描、加载前认证或运行时生成 DDS。

## 编辑器入口的实际关系

当前 UI `surface_paint_panel.gd` 和 3D MCP `import_surface_material` 都调用
`SurfaceMaterialLibrary.import_texture()`。该业务方法解码用户选择的图，按 PNG 内容 SHA
发布到独立路径；材质目录 metadata 再引用该路径。像素变更后重新导入会得到新纹理路径和
新材质 ID，旧 PNG 与旧 DDS 继续支持旧引用。没有把新内容写到旧哈希路径。

本轮测试走真实 `import_texture()`，验证内容变更、再次导入、保留旧 PNG/DDS、重开目录解析
新旧引用、未变化导入复用身份。没有改 UI/MCP schema 或新增业务能力，因此不把这组业务层
回归冒称新 HTTP 功能验收。

`PoseSave.refresh_export_sources()` 会调用 `Paint.refresh_sources()`，但目前生产代码没有
调用前者，仅有兼容回归用例。此处不据此虚构“已有 UI 刷新按钮”，也不额外添加该能力。
受管包继续使用不可变内容约定；手工原地覆盖已发布哈希文件不属于导入流程，不通过每帧
stat/hash 去掩盖该外部破坏。

DDS 生成器仍是显式离线打包工具，不是编辑器每次导入自动运行的编码器。没有 sidecar 的新
导入纹理沿已有 PNG 路径加载；离线打包后新会话、或显式来源刷新，可以发现新 DDS。

## 复现与验证

证据根：
`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/editor_dds_20261025/`

- `baseline_red02/tests.log`：用 Git HEAD 原生成器，5 项测试中 3 项明确失败：末级仍为
  16×8、法线 G 最大偏差 126、旧 DXT5 未移除；2 项已有保留行为通过。
- `cpu02/fixtures.json`：候选 Python 7 项通过。包含完整 mip 编码、透明/不透明、12×8 非
  2 次幂、正确法线、格式切换、保持源 SHA、未允许覆盖时保留，以及编码/临时写入/原子替换
  三处故障注入；每次失败都保留之前有效目标 DDS，临时文件清理完成。
- `cpu03/fixtures.json`：扩展为 8 项通过。地图依赖打包可显式传 `process(..., normal=True)`，
  保证哈希文件名的法线仍按材质声明生成正确 G 反转版本，不依赖文件名带 `normal`。
- `headless04.log`：Godot c593 的 DDS 原生 CPU 解码及业务回归 66 项通过，覆盖完整 mip
  长度、最小解码 texel、刷新缓存、上述真实编辑器业务入口、上传簿记。Headless 不证明 GPU
  上传成功、渲染速度或画质。
- `baseline_red/tests.log` 保留早期测试夹具错误（对旧工具调用新 helper，且 mip 头部 0 未按
  单级解释），随后以 `baseline_red02` 的实际公共生成行为失败为准。
- 第一版 Godot 测试误调用未绑定到脚本的 `Image.get_image_from_mipmap`，超时后已修正；
  后续用实际 mip offset/解码字节核验，不能把第一次超时作为产品失败或已通过。

运行入口：

```text
python tools/test_texture_dds_sidecars.py --output D:/外部新目录
godot --headless --path <本工作树> --script res://tools/test_compressed_texture_sidecars.gd -- --fixtures=D:/外部新目录/fixtures.json
```

每个源/候选的实际文件 SHA、尺寸、全部压缩 mip 字节均存放于对应 `fixtures.json`。
这些字节是资源尺寸与上传预算，不是实测 RSS/VRAM。

## 历史计量更正

`map_traverse_26` 的 `paint.texture.upload_bytes = 564,742,192` 只计非 DDS 分支。
不能由此宣称总上传量从 2.29 GB 降低约 75%。旧耗时和原始文件保留；累计计数修复以后
需要重新测量总字节，不能改写旧样本假装已经重跑。主纹理日志已就近标明此纠正。

完整 mip 链使 DDS 通常比仅顶层多约三分之一字节；实际成本以新产物为准。
当前引擎 ABBA 使用同一批旧 DDS，因此仍能对比引擎变更，但不证明新 mip 资源性能已验收。

## 交付边界

| 项目 | 状态 |
|---|---|
| 临时派生资源审计 | 通过，绑定 fixtures SHA，源图保持不变 |
| Godot 解码与缓存合同 | 通过；真实 GPU 回读另验 |
| 编辑器现有导入/目录重开 | 通过业务层回归；UI/MCP 业务入口未改变 |
| 正式 axel 旧 DDS 修正 | 已完成只读依赖盘点；因法线候选画质不通过暂未改写 |
| 近中远、法线受光、过滤画质 | 4 个代表材质 Vulkan 对照已看图，BC3 法线不通过，详见下文；透明边缘不在本轮代表覆盖范围 |
| 全图加载、卸载、返回与工作量 | 主线程负责，不能把本组 fixture 结果冒充整图收益 |

BC1/BC3 本身是有损压缩。补齐正确通道和 mip 合同不等于旧 DDS 已完成画质验收，亦不
改变原有模型碰撞、LOD、编辑、保存或活动件语义。现有包只应按当前地图可达纹理源逐项
转换，不扫描或重生成全包无关资产；迁移须保留旧 sidecar 字节/SHA 与可回退路径。

## 实际地图依赖与 GPU 画质复验

`map_inventory01.json` 为只读依赖盘点：2369 条记录、1065 个唯一 paint definition、
85 条唯一源/变体路径；74 条选中 DDS 全部缺少 mip。选中 DDS 合计 178,267,392 B，
60 DXT1 / 14 DXT5。这里是地图声明可达闭包，不冒充一次遍历的实际 124 次上传请求。
地图 SHA 始终为 `667091a1e0b299f44d0ad1e9bb5d247fd1bec74603b3ac9dd401d494f418e8e4`。

`conversion_plan01.json` 收窄到 74 个源和它们的 88 个现有 DDS 兄弟，备份范围总计
233,843,712 B；不备份整张地图。20 个 normal 源对应 34 个 DDS、123,736,320 B，
没有和其他材质通道混用；其余 54 个源对应 54 个 DDS。实际选中 DirectX flip 的 4 个源为
natural_dirt、natural_sand、lime_plaster、sandstone_floor 的 `normal.png`。这些旧 flip
解码图更接近垂直翻图而非 G 反转，证实错误派生文件已实际存在。

`tools/review_dds_materials.gd` 在独立不激活桌面，以相同 PlaneMesh、640×480 viewport、
相机、固定斜向 DirectionalLight、环境亮度和材质参数，分别渲染 source、legacy DDS、
candidate DDS 的 near/mid/far/normal_detail。GPU 主证据为 `gpu02/`：
Godot c593823d、Vulkan Forward+、RX 7900 XTX；共 48 张截图、24 个实际 ImageTexture
上传，退出 0。`gpu01/` 额外 OpenGL 对照保留但不混入主口径。全部上传图用技能工具
生成有损 WebP quality=90，原 PNG 仅保留本地像素对照；每张有 SHA/参数 receipt。

| 材质 | 新 BC3+mip 相对原图观察 | 结论 |
|---|---|---|
| natural_dirt | 翻转和 mip 改善旧错误；仍出现源图没有的粗黑斑 | 法线候选不通过 |
| sandstone_floor | 石缝方向恢复；细节受光仍出现额外噪点 | 法线候选不通过 |
| outdoor_flagstone | 远距颗粒减少；近距及单法线视图仍有黑斑/细节偏差 | 法线候选不通过 |
| solid_timber | 材质整体接近；单法线视图增加纹理噪点 | 法线候选不通过 |

这些现象来自派生 DDS 的编码与过滤合同，不能归因于原始游戏资源。修 G/mip 不能掩盖
RGB BC1/BC3 不适合法线 XY 独立数据的问题。当前不发布这些法线候选；原 PNG 通路可
正确反转 G 并生成 mip，作为保留画质的回退。BC5(RG) 只在外部临时目录试验，尚未改
运行时或正式 pack；不能因 CPU 误差较小直接放行。代表材质测试不等于整图画质验收、
真实编辑器 UI 保存重开或完整模型受影响项全部通过。

### BC5 外部候选

`gpu03_bc5/` 将同一批法线换成 BC5(RG)，颜色图仍为上一轮完整 mip DXT1。Pillow
输出 DX10 148 字节头；候选逐级取 148 字节后的块数据，改用 Godot 支持的 ATI2 头，
绝不能把扩展头拼入像素。Godot Forward+ 的 `scene_forward_clustered.glsl` 明确从
normal.xy 重建 Z，因此此角色不需存储原 B；这不是颜色图可采用 BC5 的依据。

4 个 2048² 法线均为 5,592,560 B（含 DDS 头），与同尺寸完整 mip BC3 相同。固定
近中远/单法线对比已看图：上述 BC3 黑斑与额外噪点消失，4 个代表未见非预期画质损失。
候选真实保存 `.res` 再重开后渲染，仍为 RGTC_RG 和 11 级 mip；GPU 回归退出 0。
这只支持代表候选，不等于剩余 16 个法线已经逐项验收或实际地图已经接入。

通用编辑器仍允许同源图作颜色和法线，当前 `path/flip` 身份不足以区分 RGB 和 RG
资源；必须把 normal 角色贯穿准备、发布、弱缓存、作用域和失效，而非全局优先查 `.bc5`。
该合同实现前不发布 BC5 到正式包；源码和地图仍保持冻结。

### normal 角色合同与实际续作漏接修复

运行时已统一 `SurfaceMaterials.texture_key/definition_texture_key/texture_source_path`：
颜色保留原 path；法线为 `path|normal`，DirectX 为 `path|normal|flip_y`。准备请求现在
显式携带 `[path, flip, normal]`；依赖目录升至 v6。入口预取、PrefabTextures、材质分片、
HousePrefab 的 tickets/作用域/失效、河流、编辑器准备和保存失效均使用此身份。
BC5 只在 normal 角色查找；同源颜色仍选 RGB DDS 或 PNG。已有对应 DDS 的编辑器/入口
请求跳过重复 PNG 准备。白模/discard 不产生纹理 lookup/decode/upload。

发现并保留一次真实地图失败：根线程 `mask_map_prime.json` 在最后 18 个需求永不收敛，
失败任务 `reference:building:building_f3f5fa678d191bff9d66` 的第二包报
`Invalid prefab texture preparation plan`。此前首包和分片回归不能覆盖真正的 pending
消费者续作；`_resume_pixel_jobs()` 仍手写双元素请求，estimate row 也未记录 normal。
该地图样本不作为性能结果，没有通过增加超时掩盖。

`continuation_red02.log` 在真实两 worker 队列中强制 producer 等待，consumer 提前完成
引用并 park；正常 producer 和取消 producer 两种路径均复现同一错误（24 通过/2 失败，
无脚本错误）。补 `row.normal` 并从 row 恢复三元请求后，`continuation_green.log`
**32/32 通过**，包括 OpenGL normal（flip=false 不能推断角色）、续作、取消重试、资源
与 admission 清零。初次 `continuation_red.log` 因断言失败后夹具继续取已移除 job 而
产生附带异常/退出泄漏；改用有界失败清理后的 red02 作为有效红证据。

其余最新回归：

- `variants01/red.log`：同源颜色/两种法线的 9 项中 5 项失败；`regression03` 的新测试
  18 项全绿，含强弱缓存、来源刷新、prepared generation、BC5 不串颜色、零白模纹理工作。
- `regression02/test_prefab_texture_preparation.log`：65 项通过；`regression03` 源身份
  回归通过（100 consumers 的严格旧路径 600 次 SHA 读，对照 mounted 3 次源读），仅作
  工作量合同，非本轮计时收益。
- `regression03/test_compressed_texture_sidecars.log`：97 项通过；trusted texture
  preflight 16 项通过。
- `gpu_contract01`：真实 GPU tickets 18、prepared publication 64、streamed publication
  99 项通过；编辑器 terrain/prefab 两组真实 HTTP 打开、保存、重开均零失败。故意损坏 PNG
  的 codec 错误是夹具预期，未删除这些日志。

严格可变源夹具显式设置 `verify_packages=true`；生产继续信任受管包。另修复已有
trusted standalone 准备末尾把 path identity 拿去和文件 SHA 比较的矛盾：现在检查同一
path identity，不额外读文件 SHA。旧回归因默认策略漂移的失败、RGTC 解压只有 RG 两字节
而旧夹具仅允许 RGB/RGBA、Windows 路径斜杠比较误报均保留日志并明确修正夹具。

### 生成器跨角色保护与待执行迁移

`cpu_roles_red/tests.log`：先颜色后法线、先法线后颜色两种顺序都复现另一角色 DDS 被删。
现在普通生成器只清理自己角色的格式：normal 可以移除旧 `.flip.dxt*`，保留无 flip 的
DXT；color 只处理 `.dxt1/.dxt5`，保留 BC5。完整编码成功才清理，失败保留原目标。
只有地图角色审计确认 normal-only 后，迁移才可退役其旧无 flip DXT。
`cpu05_roles/fixtures.json` 的 **11 项 CPU 回归全通过**，并补无覆盖许可时非整块尺寸
源也不能删除已有两种角色 sidecar。

`tools/migrate_map_texture_sidecars.py` 已准备（尚未运行）：stage 仅处理清单 74 源，复制
88 个旧 DDS 到外部 SHA 备份，生成候选，不改包；生成 20 个实际法线的 source/legacy/
candidate GPU manifest，继续逐项检查剩余 16 个法线。publish 要求原图/地图/旧 DDS、
备份及待发布候选仍匹配已审查 SHA，再逐文件原子替换；normal-only 旧 DXT 退役也有
精确备份，失败回滚本次已修改文件。该迁移 SHA 检查只发生在离线写入边界，不进入游戏。

当前正式 DDS 仍未转换；根线程进行固定旧 DDS 的 mask ABBA，期间暂停 GPU、编码和
压测。迁移脚本仍待小型事务失败回归，不能把已写代码当作已执行/已发布。20 法线实际
SHA 画质与最终地图加载/卸载/返回复测完成前，不宣称整个资源包通过。

### 跨 white/纹理模式目录与事务回归补充

初版 `Prep.sources()` 为 white/discard 提前返回空表，会把诊断模式的空依赖写入可复用
目录；`modes_red.log` 8 项中 3 项失败，明确复现 white 构建后切纹理仍读到空依赖。
修复后作者声明枚举与渲染模式无关，只在 estimate、编辑器请求、DDS lookup 和上传入口
抑制真实纹理工作。`modes_green.log` **8/8 通过**，包含真实临时地图目录保存再读；
白模 producer 的 decode/source read 均为 0。`normal_final.log` 扩展为 **19 项通过**。
最终源快照以这次修正为准，已有 v6 错误目录由 generator fingerprint 失效，不兼容复用。

`migration_test01/tests.log` **5 项通过**，覆盖所有 1/2/3 号替换失败、第二个旧文件
退役失败的精确回滚、源变更与候选变更在任何写入前拒绝、stage 不改包、成功发布的
实际安装 SHA/bytes 与候选逐项一致。全部为外部 16×8 临时图片；没有执行正式 74 源
迁移。发布凭据现在记录实际读取的 `installed` 明细，成本不取自未核对的声明值。

### 后台入口与来源刷新并发修复

最终代码复核发现 `MapLoader._parse()` 在 Thread 中调用 `_start_texture_prefetch()`。
新增 DDS 跳过准备逻辑若调用有缓存的 `Paint.has_compressed_sidecar()`，会与主线程刷新/
发布同时访问全局 Dictionary。`sidecar_worker_red.log` 用实际入口复现 worker 改写主线程
缓存；修复抽出不读写共享字典的 `compressed_sidecar_path()` 只读磁盘选择函数，worker
只用它，主线程原缓存继续 memoize 同一选择函数，未增加全局锁。
`sidecar_worker_green.log` 的 2,000 次 worker probe 与 77 次主线程来源刷新并行通过；
两种 DDS 角色均未额外创建 PNG worker。`normal_worker_final.log` 的 19 项合同通过。

### 74 源派生文件发布与实际法线画质

`map_stage01/manifest.json` 只包含上述依赖清单：74 源、88 个旧 DDS 精确备份、88 个
候选。原图与地图均只读。候选中 54 个 color 顶级块 payload 与旧 DDS 逐字节相同；
只补 mip，未混入颜色编码格式变化。88 个文件的逐级块字节与完整 mip 长度匹配。

`map_stage01/gpu_review/` 使用 `eaec8870dd5940aefff21510bbd559e316e4aa3abe2985738206a9ac0348d73c`
引擎、Vulkan Forward+、RX 7900 XTX：20 个实际选用法线 × source/legacy/candidate ×
near/mid/far/normal_detail，共 240 张本地 PNG。20 个候选材质均先保存 `.res`，再无缓存
重开后渲染，重开后 RGTC_RG、完整 mip。源/候选 SHA、安装候选 SHA 和有损 q90 WebP
凭据绑定在 `map_stage01/reviewed.json`、`normal_review.json` 和 `contact_receipts.json`。

逐项检查 20 张四距离 source/candidate 对照图，均未发现源图之外的黑斑、额外颗粒、
受光方向翻转或远距细节异常。mossy_grass、icelandic_jagged_slate、natural_dirt、
natural_sand、outdoor_short_grass、outdoor_flagstone、castle_rubble、stone_tiles_facade、
solid_timber、fine_plaster、worn_planks、lime_plaster、sandstone_floor、relief_20261014、
5 份 material_textures 哈希来源、automatic_limestone_kerb_readable 均有各自 SHA/截图。
这里只证明 StandardMaterial3D 固定条件下的材质对照，不把它等同所有自定义 shader。

正式 `publish` 已完成，失败 0：安装 88 个 DDS，总 **328,566,704 B**；退役 34 个
normal-only 旧 DXT（含翻转版本），88 个旧文件仍在外部 backup。实际安装目标读取
SHA/bytes 与候选逐项一致；74 个源 SHA、地图 SHA 均未变。
`manifest.json` SHA 为 `c88c950817ebfbeb859a8d0781c483ac9375b74ad497ae9bb86d085bc250b09f`；
`published.json` SHA 为 `1b015aba42a96a358946abee43338c90df001ab520c4a99fc81b778458c748bb`。
这些文件字节不是实际 RSS/VRAM，也不是单次游戏上传量。

发布后的最终 diff 自审又发现 `river_terrain` 的 6 层直读/三向投影和 `river_water`
直接依赖 normal.B，BC5 需要重建 Z；StandardMaterial3D 的通过不能覆盖它们。已暂停
最终整图测试，先在实际自定义 shader 中红绿复现并补齐。wind/river_bank 使用
`NORMAL_MAP`，引擎明确重建 Z；旧 2D surface_lighting 消费自行拼合 RGBA，不走3D DDS。
正式包已保留可回退状态，在 shader 补齐与整图复测前不称完整接入验收通过。

### 自定义 shader 的 BC5 合同补齐

`custom_normals01/red02` 通过实际 `River.bind()` 和原 `river_terrain.gdshader` 渲染，
覆盖 base/sand/rock/region_a/region_b 的平面与三向投影，以及实际含 soil 的深度过渡。
144 项中 78 项失败，PNG 与 BC5 的平均 RGB 像素误差为 0.0977–0.1696。第一次 `red/`
因夹具对不存在的 uniform 调用 `bool(null)` 超时，已保留，不能作为产品红证据。

修复在创建 DDS ImageTexture 时记 `runtime_normal_xy`，River.bind 和 water 构造时
读取一次该 metadata 写 uniform。共享 `normal_texture_decode.gdshaderinc` 只对 BC5
从 XY 重建 Z；PNG/RGB 的作者 B 语义不变。地形 6 层的直读和 triplanar bump 均接入，
水波同样接入。没有每帧格式查询、GPU readback 或额外纹理工作。

`custom_normals01/green` **144/144 通过**，误差降至 0.00034–0.00048；water 的实际
shader 成功编译并继承 BC5 标记。11 张 PNG 对照图与修复前逐字节相同，SHA 记录在
`png_unchanged.json`。该固定环境像素证据比“代码应该不影响 PNG”更具体。
实际地图法线的自定义 shader 代表画面与最后整图复测继续单独记录。

实际材质代表补验现已完成：`custom_normals01/real_planar02` 与 `real_slope02` 使用同一
4 个实际 SHA（mossy_grass、icelandic_jagged_slate、natural_dirt、natural_sand），实际
`river_terrain`、固定光照、灰度 .55 和近中远/normal_detail；每组退出 0。候选 ShaderMaterial
同样先保存/重开，保留 `base_normal_xy=true`。8 张 q90 contact 均逐项看过，未见新增
黑斑、受光方向错误或过滤损失。这里覆盖平面上的两条采样分支，不冒充全部陡坡投影轴、
所有天气或最终地图构图验收。`real_contact_receipts02.json` 绑定图片 SHA/quality90；
两组 `gpu_decode.json`/manifest 绑定实际法线及保存资源 SHA。早先 real_planar/real_slope
使用白色时近中远出现高光截断，保留但以统一灰度后的 02 组作为材质细节证据。

补拍曾两次在打印 Vulkan 后、进入脚本前停住。`real_planar/startup_gdb03.log` 由根
线程 GDB 抓到主线程 MockHost 同步安装的 busywait、worker 等待主线程 MessageQueue
的 `connect_changed` 信号；不是地形 shader 编译锁。诊断进程在 detach 后主动停止，
不计入性能样本。图像 fixture 加 `--without-mock-server` 后两条渲染路径正常完成。
MockHost 问题由根线程独立红绿修复，不能用跳过测试宿主来冒称生产故障已修。

最终只读 diff 检查还核对了合批：`ground_batch_geometry` 遍历 shader uniform 计算
语义签名，派生材质使用 duplicate，因此新的 normal_xy 标记不会在合批中漏掉。
本轮无 UI/MCP 新能力，保留已有内容 SHA 导入、编辑/撤销/保存语义；同源颜色与法线
共用的准备、续作、弱缓存、来源刷新和 white→texture 目录切换已有上述红绿证据。
源码与派生 DDS 从此冻结，剩余最终地图性能/接入状态由根性能会话验证。本子任务没有
commit 或 push；没有把局部画质/逻辑测试解释成已达到完整纹理加载时间目标。

### 后续：DDS 也进入编辑器 CPU 准备 worker

根性能会话随后用官方 profiler 复现返回阶段约 83ms 慢帧：一次发布在
`WorldDocument._mesh → SurfaceMaterials._texture` 内同步读取/提交 12 张 DDS，
纹理 span 合计 73.443ms。之前“DDS 已经压缩，所以不安排 PNG worker”的判断漏掉了
DDS 自身的同步读取、Image 构造成本；编辑器 `TerrainTexturePreparation.requests`
也有同样的跳过分支。此项不修改纹理内容、编码格式或已发布文件。

新增共享 `compressed_texture_source.gd`，只负责 CPU 的 DDS 计划和读取：支持 2D
BC1/BC3/BC5 的 legacy 128 字节和 DX10 148 字节头，按每级逻辑尺寸计算压缩块边界，
准入完整 mip 链。尺寸、格式、长度和层数检查用于限制内存分配；不计算包 SHA，
不扫描像素、不展开 RGBA、不重建 mip，也不读写主线程 `_sidecar_cache`。
`read` 在同一打开文件上核对实际头与准入尺寸，直接把压缩块传入 Image；源身份仍由
调用方沿用 trusted 路径身份或 strict 原始源身份，未新增 DDS 哈希认证。

编辑器 requests 现在保留 DDS 请求，decode worker 先用共享 helper，失败/不支持时
继续原 PNG 路径；缺少原始作者源仍保持原失败行为。同源 color/normal/DirectX 变体
继续独立，BC5 不会作为颜色。根线程负责 Deferred/MapLoader/Prefab 准备与主线程
发布接入；本轮 MapLoader 复用了编辑器 decode，避免再维护一份不同的解码合同。

新增 `tools/test_compressed_texture_source.gd` 的独立证据在
`material_submit_review_20261025/compressed_editor_worker_01/`：

- `red.log`：269 项中 5 失败，复现编辑器 DDS 被跳过和主缓存被探测修改。
- `green.log`：**271/271 通过**。24 组合覆盖三种 BC 格式、两种头、1×1、7×11、
  16×8、1254×1254，Image 全 mip 压缩字节与文件 payload 完全一致。
- 18 类不支持/坏头/截断/超界输入及准入后的同大小尺寸变化均拒绝；包括 cube、
  volume、array、部分 mip、签名/头长和文件长度，不把这些拒绝当作资源质量诊断。
- 同源颜色/法线/flip、白模零准备、严格/可信源身份、坏 DDS 回退 PNG、缺源失败、
  编辑器 worker 不碰主缓存均覆盖。CPU 结果不是 GPU 上传或整图时间证据。

旧 `test_sidecar_worker_lookup.gd` 的“DDS 不应建立 worker”断言也随真实合同改为
“CPU worker 返回原压缩 mip、零 PNG lookup/cache、主线程刷新并发不污染缓存”。
旧 2,000 次只查目录的循环改成 32 次实际读取循环，避免把功能并发回归变成无意义
大文件 IO 压测；实测由根线程在整图 ABBA 完成后统一调度。生产代码已冻结，保持
最终地图对照的 source snapshot 稳定。
