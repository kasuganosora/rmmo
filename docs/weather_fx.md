# 天气美术与粒子验收

> 本文为旧二维天气的历史说明。当前三维游戏与编辑器使用 [3D 天气与美术](world3d_weather.md)，不加载下述屏幕空间粒子。

天气入口仍为 `MapField.set_atmosphere()`，使用原来的天气配置、昼夜调色和 HUD 层级。
此次只修改天气渲染和混合，不改变采集奖励或地图素材。

## 表现与资源

- 小雨：2×18 的渐变雨线，220 粒子，轻微倾斜。
- 暴雨：2×28 的渐变雨线，360 粒子，较强斜风与速度；闪电峰值透明度从 0.45 降到 0.22。
- 雪：四层共 529 粒子——180 颗远景细雪、260 颗中景雪、65 颗近景柔焦雪、24 颗旋转六角雪晶。各层有不同速度、尺寸与风摆相位，雪晶用生命周期亮度起伏产生少量闪光。
- 雾：128×64 径向渐变，18 个漂移雾团，加低透明度底色，减少整屏灰白遮挡。
- 基础纹理由 `weather_fx.gd` 内的 GradientTexture2D 定义，六角雪晶由 `snow_crystal.gdshader` 绘制，以屏幕像素控制大小；不再依赖外置天气 PNG 的透明边距与缩放约定。
- 所有粒子有生命周期透明度曲线，发射区域覆盖视野；雨/暴雨按 60 Hz 模拟，雪/雾按 30 Hz 模拟。天气仍为屏幕空间效果，没有新增地面溅水或逐屋顶遮罩。

## 更新与过渡

固定参数仅在初始化设置；发射区域只随视口尺寸改变。缓存混合结果，稳定天气不重复构造字典。
连续切换使用当前混合粒子权重，重复收到相同目标不重启过渡。
进入室内、屋檐下和关闭天气特效时立即隐藏存活粒子并暂停内部模拟，清除闪电；设置变化立即同步音效。

## 复验

使用 Godot 4.7.2：

```powershell
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path D:/code/rmmo --script tools/test_weather.gd
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path D:/code/rmmo --script tools/test_weather_gather.gd
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path D:/code/rmmo --script tools/preview_weather.gd
```

2026-09-24：天气及采集测试通过。实机预览使用 Axel256 编辑器试跑地图，角色 (112, 120)，1440×1000，Forward+，AMD Radeon RX 7900 XTX。
截图写入 `user://weather_preview/`，包含五种天气及各自间隔 0.5 秒的第二帧，供检查粒子运动与 HUD 层级。

`tools/bench_weather.gd` 可选加载 `res://._weather_baseline.gd`，然后与当前实现比较。基线为修改前 `weather_fx.gd`。
每种天气执行 10,000 次稳定状态 `_process(0)` 加 `display_modulate()`；首次重做一轮原版约 51.6–53.7 μs/次，新版约 2.2–3.4 μs/次。这组数据采于四层雪景增强之前，不能作为新增雪景的性能验收。
这仅衡量脚本更新成本，不包含粒子模拟、GPU、音频首建、过渡状态或大地图流式加载，不能当作整体 FPS 增幅。
