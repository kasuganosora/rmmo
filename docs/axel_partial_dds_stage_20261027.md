# 部分压缩块与地图声明纹理候选（2026-10-27）

`material_trace34` 的 obj_377 法线上传输入来自1254×1254 PNG，正式路径没有DDS侧车；这不是源资源质量问题。旧离线生成器对任一边长不被4整除直接跳过，尽管当前engine09对部分块已有支持。生成器现按每级mip向上取整块数，保留源尺寸，支持BC1/BC3/BC5；内容哈希文件名不含角色，自动化需按地图声明传入normal而非文件名猜测。没有改游戏运行时的可信资源包校验。

`partial_gen_red01.log` 旧实现预期失败，`partial_gen_green10.log` 13/13；包含5×5、6×6、7×11及1254×1254的完整mip、边缘采样、角色/翻转、重复角色与失败写入。当前真实engine09上 `partial_engine09_cpu01` 与 `partial_engine09_gpu02` 各24/24，含BC1/BC3/BC5和逐级Vulkan上传/读回；是合成像素数据，不能代替目标素材画质。

真实屋顶PNG外部临时复制的同源SHA与候选在 `actual_normal_benchmark40/`，暖OS缓存12次CPU ABBA：PNG解码/mip/上传准备中位33.834ms（32.636–52.605），BC5计划/读取中位2.246ms（1.716–2.617）。实际mip逻辑字节8384072→2104704，非RSS/VRAM。私有桌面GPU 12次ABBA ImageTexture.create_from_image中位4.414→0.533ms；逐次1.640–12.344 vs 0.497–0.667ms，完整mip读回字节/格式通过；force_sync只刷新命令，另记get_image读回，不当GPU完成指标。测试无地图、材质或场景视觉，不可换算整图收益。法线base mip数值角误差均值0.754°、p95 2.288°、p99 6.262°、最大15.915°，不足以作为真实场景画质通过。

`tools/stage_map_dds_sidecars.py` 是Windows限定的离线包外候选生成工具：依据 `audit_map_dds_sidecars.gd` 的source、normal role、DirectX flip声明去重，同SHA同角色共用一个编码结果。输入真实资源包只读，输出新建外部stage；已有首选侧车分 header_usable/selected_unusable 且不覆盖，前者不证明新鲜度。完成时核对产物字节/SHA并最后创建COMPLETE；失败保留无COMPLETE的外部目录，不删除不确定身份的文件。句柄及路径边界、源与工具变化、角色/翻转/现有文件、失败及并发替换由 `stage_cleanup_green12.log` 20/20覆盖，独立只读复审无新确定性阻断。该工具没有发布功能，离线阶段一致性检查不等于游戏启动时再认证资源。

`actual_dds_audit41.json`：2369记录、1065唯一定义、85个声明纹理变体，其中11个无侧车（8色、2 OpenGL normal、1翻转normal）；范围仅地图/预制件paint，不包含导入模型材质。包外 `actual_dds_stage42/` 依据清单生成11个目标映射/6个共享候选blob，74首选header可用，COMPLETE存在、六个blob SHA复核通过；正式资源包未写。若未来接入，需要先验证实际shader/场景视觉与alpha/normal、资源代际、游戏与编辑器读写，不能将本stage或数值误差当完整画质/性能验收。

## 屋顶法线临时视觉对照

`actual_normal_visual43/` 使用外部复制的原始屋顶albedo、roughness和normal，以及与stage42 SHA相同的BC5，在私有桌面用同一平面网格、StandardMaterial3D、UV、normal_strength=1、相同相机/光照/曝光比较近中远与掠射光；实际绑定PNG RGBA8和BC5 RGTC_RG，均完整10级mipmap，输入前后SHA不变。没有修改正式地图或模型。无损本地像素RGB绝对差均值近/中/远/掠射1.816/2.227/1.729/2.675（0–255），各p99为20/20/8/18，不等于可感知损失。近景和掠射光查看有损WebP quality=90副本，整体瓦片形状、颜色与明暗相近，局部受光与细纹有细微差异。全部原始截图、本地无损对比、Q90 WebP/参数及SHA见 `visual_comparison.json`、`capture_report.json` 与各 `.review-image.json`。该隔离平面不构成实际建筑、所有材质或整图画质验收，也不改变候选未发布状态。

## 其余五种候选的临时材质对照

`actual_remaining_visual44/` 对4种BC1（亚麻、屋顶albedo、屋顶roughness、土灰墙）和1种BC5 DirectX normal，在外部临时目录逐字段比较，其他纹理、相机、几何、UV、灯光与曝光保持相同。GPU 11个材质绑定、44帧无失败；实际四BC1为格式17、BC5为格式21，输入与候选SHA在运行结束不变，四个color源本身RGB/候选alpha=255、该测试使用的材质透明模式disabled。屋顶roughness按真实RED通道比，base mip误差均值1.99/255、p95 6；DirectX normal实际绿通道翻转一次，包含未翻转对照，角误差p95 9.16°、p99 18.14°，非美术阈值。

不同视距屏幕RGB平均/95分位差：亚麻近景1.15/3、屋顶albedo中景5.08/18、屋顶roughness掠射0.24/1、墙面近景0.97/3、石板normal掠射2.21/6（0–255）。我查看了同尺寸有损WebP quality=90的屋顶颜色中景和掠射光，整体结构相近但局部颜色及细节有差异；布料在测试曝光/UV下太淡，尚不能判断布纹损失。原始无损图仅作本地像素分析，WebP参数、SHA、输入/实际绑定在 `visual_comparison.json`、`capture_report.json`、各图 `.review-image.json`。此隔离平面不是实际建筑、其他角色或整图验收，不发布候选。
