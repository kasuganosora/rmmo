# 真实贴图导入：保真边界与质量选择（2026-10-29）

实际图审发现：当前自动 DXT1/DXT5 导入不能一概称为无可见损失。功能、共享预算、CPU 编码、首次使用等合同通过，不等于画质通过。正式资源和原生树模型没有被本测试改写。

## 第一轮真实图像证据

外部根 `D:/code/rmmo_runtime/review_artifacts/editor_full_map_20261028_01/texture_quality_01/`。`run_texture_quality.py` 在私有桌面逐个启动候选 4.7.2 引擎 `3d65b357…`，真实 HTTP `import_surface_material` 发布素材；复用实际上传的 Texture2D，与原图创建的 Texture2D 使用同一材质参数、平面 UV、相机、灯光和曝光。`review_editor_texture_quality.gd` 没有预先生成替代 DDS 或修改生产材质。每例前后引擎、代码、输入 SHA 一致，无脚本或引擎错误。

三种 2048² RGB 来自默认包现有 natural_fieldstone、natural_red_brick、natural_sand PNG。布料为 1254² linen_v2.png，真实非 4 倍尺寸回退；没有缩图。它们是实际内容素材，不代表已证明都被 axel_town 引用。

树叶取自已经验收的 compact 树实际 SCN `707f53fb…ee00.scn` 的 Foliage/slot0。解码完整 mip 的 RGBA SHA `3d7ff9f6…52a60cc` 与此前 native 记录相同，原尺寸 3072×2048。只在外部目录导出 level0 PNG 再通过编辑器导入；不读取原 GLB，也不覆盖原生树贴图。额外对照沿用该树 alpha scissor 0.45、cull disabled，和正式面材质 alpha blend 的对照分别记录。

| 图像 | 实际 GPU 格式 | 观察/结论 |
| --- | --- | --- |
| 不规则石铺 | DXT1 | 石片和灰缝位置保持，但特写色阶、细纹和中央石片的明暗观感有可见变化，不能无条件画质通过 |
| 红砖 | DXT1 | 砖缝和大轮廓保持，颗粒/色阶及细裂纹特写有可见变化，不能无条件画质通过 |
| 沙地 | DXT1 | 当前亮度下接近浅奶白，特写细颗粒有轻微变化，不能凭近景相似放行所有细节 |
| 亚麻布 | PNG 原像素 | level0 RGBA 和近中远/特写四组渲染 PNG 逐像素一致；1254² 原尺寸及原像素回退管线通过，不是整体美术评定 |
| 松针叶片 | DXT5 | scissor 特写细针局部变粗，孔隙、针尖和局部叶簇轮廓改变；alpha blend 的细丝/透明边缘也有轻微变化，不能替代整树画质验收或覆盖源纹理 |

root 实际查看前三类与布料各近景/特写两组 source/published，共 16 张原尺寸有损 WebP Q90；它们的中远图仅本地逐像素比较，没有冒称人工查看。已有编辑器子任务 `/root/logging_audit` 实际查看叶片 14 组共 28 张 Q90，覆盖 blend/scissor 的近中远、细节、亮暗背景和投影。每张转换回执、原 PNG/上传 WebP SHA 与逐项观察在各自 `evidence/manual_review.json`、`manual_review.md`；精确像素 PNG 保留本地。

数值只描述差异，不作为自动画质通过阈值：石铺 level0 RGB 绝对误差均值 3.30/255，红砖 4.55/255，沙地 3.59/255；叶片 alpha 最大差 31/255、均值 0.836/255，level0 按 0.45 截断有 12,831 像素改变判定。它们不是图像质量分数，不能替代观察；WebP 也有损，所以保留 PNG 进行精确计算。

## 已交付：明确的保真选择

UI 文件选择框提供“保留原像素”和“有损压缩（节省显存）”；当前 3D MCP `import_surface_material` 增加可选 `compression: "source" | "dds"`，默认 `source`，两者调用同一服务。用户已明确确认此默认策略。已有 DDS 和原生资源不自动改写，不增加运行时图像质量检查或为了编码而缩放尺寸。

同路径同模式的订阅共享准备；明确选择不同模式时产生独立产品。保真路径不调用 DDS 编码器，规范 PNG 为 `<content_sha>.source.png`；DDS 路径保持原命名与身份。保真材质 ID 使用 `source_` 前缀，避免与历史纯十六进制 DDS ID 碰撞。地图继续保存材质定义和纹理路径，保存重开不会误选同内容 DDS。共享预算、旧 owner、撤销语义及最后订阅取消后的在飞回收继续保留。

本轮还复现并修复了并发 HTTP/UI 导入完成回调冲突：本机 4.7.2 的 `CallableCustomBind::_equal_func` 比较原 callable 和绑定参数数量，不能用不同绑定参数值区分信号连接。改为每个消费者只连接一个处理器，用 request ID 分发；HTTP 请求、连接和反向索引一起清理。它不需要额外引擎补丁。

证据均位于 `editor_full_map_20261028_01/`，保留失败样本：

| 验证 | 结果与范围 |
| --- | --- |
| `quality_choice_red_02` | 旧 API/schema 缺少质量选择，4 项失败；`red_01` 是夹具类型声明解析错误，不作产品红测 |
| `quality_choice_green_01` | 初稿并发信号连接冲突，5 项失败；保留超时日志 |
| `quality_choice_collision_red_01` | 初稿 source ID 可与 DDS 特殊名称组合碰撞，2 项失败；改用独立前缀 |
| `quality_choice_green_02` | 真实 HTTP 发现、同源同名并发去重、两种产品、非法模式无副作用、UI 回调、涂刷撤销及保存重开 **39/0**；HTTP owner/DDS 刷新回归 **28/0** |
| `quality_choice_green_03` | 协调器 **44/0**、普通物件纹理保存重开 **48/0** |
| `quality_cpu_green_01` | headless worker **49/0**，包括保真路径编码调用 0、RGBA 等价与独立身份 |
| `quality_disconnect_green_02` | 两个真实 HTTP 客户端共享 producer，断开一个不取消另一个；停止服务清空回调/索引，在飞任务保留预算直到回收，0 失败 |
| `installed_quality_01` | 同一质量选择测试通过实际 `D:/tools/godot` 入口，0 失败、无脚本或引擎错误，运行前后身份稳定 |

另保留两个无效运行边界：一次 runner 未传必需的 `--root`；一次将仅用于 headless 的编码故障注入测试运行于 GPU，产生两条预期原因断言失败，随后按正确模式重跑 49/0。断线测试首轮在队列准入前读取 lease，更新夹具为等待实际准入；没有把它写成生产缺陷修复。

## 保真模式的真实图像复验

`texture_quality_source_01` 使用上述同一批五种输入、相同镜头灯光及原生叶片 SHA，真实 HTTP 导入全部成功，无脚本/引擎错误，运行前后身份一致。五张原始 RGBA 均完整保留，**30 组 source/published 固定画面本地 PNG 逐像素一致**；各 source 基线也与前轮相同。

root 实际查看石铺、红砖、沙地、布料各近景与特写共 8 张发布结果 Q90；已有编辑器子任务实际查看叶片 10 张关键结果图，覆盖 blend/scissor 的近景、特写、亮暗背景与投影，核对全部 28 张转换回执。完整像素对照不冒称所有视角均被人工重新查看。记录在各例 `evidence/manual_review.json/md`。

保真导入通过的是原像素与这些固定画面的等效，不是新美术质量、完整树形或连续风动画验收。布料和沙地原图本身偏亮的观察保留。DDS 的内存带宽优势仍可显式选择，但有可见损失的素材不能默认替换。报告里的 GPU image bytes 是读回图像 mip 数据长度，不能冒称实测进程 RSS 或显卡分配量。
