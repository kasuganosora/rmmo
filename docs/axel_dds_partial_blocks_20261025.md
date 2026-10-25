# DDS 非整块尺寸读取复现

本轮在排查未走 DDS 的地图纹理时，发现 11 个剩余源中 10 个为 1254×1254。未缩放这些原图、未新增这批正式 sidecar；先独立检查读取器。

Godot 4.7.2 的 `modules/dds/texture_loader_dds.cpp::_dds_load_layer` 对压缩纹理先执行 `w += w % 4`、`h += h % 4`，然后用改变后的尺寸计算整个 mip 链。这既不是正确的向上取整，也会把 1254→627→313 的逻辑 mip 尺寸改变为 1256→628→314。图像层仍按原始 1254 尺寸校验数据，导致读取失败。

按照 [Khronos 的 compressed image copy 说明](https://docs.vulkan.org/guide/latest/image_copies.html)，Vulkan 图像可以含边缘不完整压缩块；内存按块分配，但图像及各 mip 的逻辑尺寸不变。[Microsoft DDS 文件布局](https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dds-file-layout-for-textures) 也给出按每一级 width/height 向上取块的计算式。本轮只验证项目使用的 Vulkan，不声称 Direct3D 对所有基级尺寸具有同样支持。

## 独立红测

`tools/check_dds_partial_blocks.py` 在项目外生成固定颜色 BC1/BC3/BC5，完整 mip，尺寸 4×4、12×20、1×1、5×5、6×6、7×7、7×11、1254×1254；不通过正式包装器的尺寸过滤，不修改美术源。

`tools/test_dds_partial_blocks.gd` 检查加载成功、逻辑尺寸、mip 数、逐级块字节数、解压后的中心/边角颜色；GPU 模式再上传并完整读回全部 mip 字节。

原 eaec 引擎：**24 项中 9 项失败**，分别为 7×7、7×11、1254×1254 的三种格式。1254 BC5 正确大小 2,104,704 B，旧读取器分配 2,105,968 B，触发 Image data size mismatch。失败日志保留，没有归咎于原纹理资源。

证据目录：`D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_submit_review_20261025/dds_partial_blocks/`，`before.json`、`before.log`、输入 DDS 和原 C++ 文件均保留。

## 修改范围

`tools/engine_patches/godot-4.7.2-dds-partial-blocks.patch` 删除对基级逻辑尺寸的修改，沿用现有每级块数取整；其余 DDS 格式、线性大小检查和材质生命周期不变。以 shader residency 已通过的 eaec 为父构建，产物单独放 `engine_dds_candidate/`，不覆盖 eaec 对照样本。

本补丁本身不缩减当前地图上传量；原有生成器仍保留非 4 倍数尺寸过滤，这 10 个源还需后续包装、画质验证后才能接入。不能把读取器微测通过写成真实地图已获得额外 DDS 收益。

## 绿测与构建身份

候选构建成功，385.25 秒；exe SHA-256 `52f532a05155b18e9614b48531e5fe136bea3a76fc240466adfe7110e0fbaee6`，匹配 symbols `6676a000873b495668301f37af4e3020b595e81cdd9e0b88867cebaebfa9175f`。除本 DDS cpp 外沿用父构建，`engine_dds_candidate/launch.json`、`build.log`、`result.json` 保留命令、源码与产物身份。

`dds_partial_green_cpu01/result.json`：**24/24 通过**，无脚本/引擎错误。然后将同一 manifest 设为 GPU 模式，使用私人桌面 Vulkan Forward+ / RX 7900 XTX 运行同一脚本：`gpu_result.json` **24/24 通过**，所有压缩 mip 的 GPU 上传后读回字节完全一致，`gpu.log` 无错误。读取、逻辑尺寸、每级字节数、解压边角颜色和上传合同均通过；没有据此替代真实资产的有损压缩画质检查。

复现：`python tools/check_dds_partial_blocks.py --engine <exe> --output <new external directory>`；追加 `--gpu` 在不激活的独立桌面验证真实 GPU。GPU 不能与其他地图性能样本并跑。

最终候选又通过完整地图加载/卸载/返回/重载及白模回归后，已于 2026-10-25 18:55 安装到 `D:/tools/godot` 的两个 GUI 入口，并复制匹配 `.debugsymbols`。旧 eaec exe/symbols/说明/manifest 保留在 `_backup/dds_partial_blocks_20261025/`；安装前确认该目录没有运行进程，未结束用户进程。安装后读取 SHA 与上述构建完全相同，两入口 `--headless --version` 退出 0。console launcher 保持原字节。

`installed_dds_engine_20261025.json`、安装目录 `dds_partial_blocks_build_manifest_20261025.json` 保存前后身份。`patched_build_manifest.json` 的当前文件表已按实际安装字节重建；先前检查移入历史记录，避免把旧版本的碰撞/符号检查标成新版本的直接验收。
