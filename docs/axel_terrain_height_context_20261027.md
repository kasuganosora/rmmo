# 地形过渡高度图回退构建（2026-10-27）

`River.terrain` 的过渡材质cache miss中，即使 `context.image` 已是后台准备的padded Image，原实现先遍历高度并调用 `Image.create_from_data` 作为 `Dictionary.get` 的默认参数；GDScript先求值参数，导致构造的fallback随后被丢弃。现在仅缺少image键时构造fallback；显式null仍按原语义返回null。诊断参数 `--without-lazy-terrain-height` 可在同一版本切换旧行为，`--texture-stage-profile` 统计仅过渡开启且material cache miss时的实际prepared/fallback次数。

证据目录 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/`。`terrain_height_red01.log` 旧eager路径产生4项预期失败，最终 `terrain_height_final04.log` headless 37/0；`terrain_height_gpu_final05.log` 私有桌面56/0，核对缺键、geometry-only、空context、显式null、prepared Image身份和padding、RF纹理读取字节、缓存命中。实际 helper 固定输入 ABBA：40次×16641高度，旧144.065/126.443ms、新0.029/0.027ms，准备图命中时fallback 40→0；这是独立内核测试，不代表实图收益。

## 累计真实地图 ABBA

`map24` 两个候选一起切换：A同步图片退休且旧高度fallback，B后台退休且高度fallback惰性；既有 native cache sort 在四组均开启。私有桌面、新进程、普通优先级、不清系统缓存；完整就绪保留需求/作业/合批连续三次清空，且共享输出及跨pool退休租约均清零。

| 样本 | 入口秒 | 完整就绪秒 | 返回 / 重载 1% low FPS | 卸载 / 返回 / 重载最大帧 ms | 三阶段 >50ms 帧数 |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 4.759 | 12.775 | 48.719 / 36.754 | 31.710 / 31.792 / 51.197 | 0 / 0 / 1 |
| B1 | 3.853 | 9.730 | 38.760 / 32.989 | 32.676 / 41.956 / 40.159 | 0 / 0 / 0 |
| B2 | 3.769 | 9.442 | 45.920 / 29.840 | 30.375 / 52.921 / 45.663 | 0 / 1 / 0 |
| A2 | 4.025 | 9.897 | 38.823 / 33.330 | 54.106 / 43.686 / 43.840 | 1 / 0 / 0 |

四组 exit0、功能/共享输出/退休租约最终清空；主地图文件和796份被测脚本SHA一致，不证明外部所有DDS/native侧车、项目设置和插件未变。GPU审计均3943 surfaces、3202非白、1502带纹理、145独立纹理，不等于全部作者纹理通过。1Hz观察到其他Blender进程，无法剔除干扰或定量解释波动。A1慢样本保留；四组不足以计算p95或证实稳定小于10秒。开启组不证明返回或重载low改善，B2低于A2且仍有52.921ms返回帧，不能因为其他阶段无>50就算解决。

四组初始同为229组、2564对象、231次build、3923次prepare、2724次pack；全路线异步时序不同，不能把build/pack差异直接相减当优化收益。初始高度prepared命中63，旧路径fallback 63次、新路径0次；全路线prepared126，旧fallback126次、新0次。后台退休B1/B2各146份图片分12批，worker累计61.534/75.379ms、单批最大11.041/20.061ms；这是后台墙时，非额外CPU或可直接节约时间。B1/B2逻辑共享峰值531,189,304字节，A1为503,227,144、A2为531,189,304；不等于RSS/VRAM，不能断言长期峰值改善。两组同时切换，不能把加载差异归因于某一项。`analysis25_summary.json`、`analysis25_peaks.json`、`verification26.json`、`map24_sources/`和各样本原始文件保留。
