# 3D 云层空间感：研究与接入建议

2026-10-02。本文保留调研阶段的资料与方案；后续体积云已接入，实际交付、参数和限制以 [3D 体积云](world3d_clouds.md) 为准。

## 当前问题与选择

`scripts/world3d/weather_sky.gdshader` 使用视线方向投影的二维 fBm 噪声、颜色和透明度合成云层。没有真实云底/云顶、体积厚度、相机平移视差或沿光线的自遮挡。当前天气对主光的整体衰减也不等于空间云影。因此优先升级几何空间和光照模型，继续增加二维噪声频率不能解决这些缺失。

建议使用 **低层轻量体积云 + 高层二维薄云**，以 Godot 官方 MIT 示例作为移植起点，参考 Nubis 的建模和美术控制。现有二维云保留为低画质回退。地面云影是后续独立集成项，不能将天空 shader 完成视为云影完成。

## 可复用资料

| 资料 | 用途与边界 |
| --- | --- |
| [Worley：A Cellular Texture Basis Function，SIGGRAPH 1996](https://itn-web.it.liu.se/~stegu76/TNM084-2019/worley-originalpaper.pdf) | 三维细胞噪声的原始论文；适合云团轮廓和侵蚀细节，本身不是气象模拟。 |
| [Perlin：Improved Noise 作者参考实现，2002](https://cs.nyu.edu/~perlin/noise/) | 连续噪声基础；参考算法，复制实现前另查许可证。 |
| [Horizon 实时体积云，SIGGRAPH 2015](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn) / [完整演讲 PDF](https://www.advances.realtimerendering.com/s2015/The%20Real-time%20Volumetric%20Cloudscapes%20of%20Horizon%20-%20Zero%20Dawn%20-%20ARTR.pdf) | Perlin-Worley 形状、细节侵蚀、高度剖面、光线步进与近似散射的工程参考；公开演讲不是 Decima 引擎源码。历史性能数字不能用作本项目预算。 |
| [Nubis：Authoring Real-Time Volumetric Cloudscapes，SIGGRAPH 2017](https://www.guerrilla-games.com/read/nubis-authoring-real-time-volumetric-cloudscapes-with-the-decima-engine) | 云层创作、天气变化和生产管线参考。 |
| [Godot 官方 Sky Shaders 示例](https://github.com/godotengine/godot-demo-projects/tree/master/3d/sky_shaders) / [体积云 shader](https://raw.githubusercontent.com/godotengine/godot-demo-projects/master/3d/sky_shaders/sky_volumetric_clouds.gdshader) / [MIT 许可证](https://raw.githubusercontent.com/godotengine/godot-demo-projects/master/LICENSE.md) | 首选代码基线：已有云层射线求交、密度采样、光照积分和低分辨率合成；仍须适配世界尺度、现有天空和性能预算。引入时保留授权声明，并检查所用贴图来源。 |
| [Godot Sky shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html) | 世界相机位置 `POSITION`、半/四分之一分辨率子通道、背景与 cubemap 分支的正式接口。 |
| [Sunshine Clouds 2](https://github.com/Bonkahe/SunshineClouds2) | MIT、基于 Compositor 的备选实现，可参考降采样与合成；截至调研时，作者的 [Godot 4.7 兼容问题](https://github.com/Bonkahe/SunshineClouds2/issues/32) 仍未关闭。本项目为 4.7.2，不能直接认定可用；未在本机验证该插件。 |
| [Nubis³，SIGGRAPH 2023](https://www.guerrilla-games.com/read/nubis-cubed) | 可穿行的体素云及加速方案；暂不作为地面城镇视角的首期范围。 |

## 生成和绘制方案

生成分成几层控制：二维天气分布决定哪里有云、覆盖率和云型；低频三维噪声塑造大体积；高度剖面控制平云底及隆起云顶；更细的噪声侵蚀边缘。薄卷云使用独立高空层。噪声纹理预生成并复用，避免每个像素现场计算大量多层噪声。

体积云使用固定世界坐标和真实高度范围，沿视线步进累计密度及透射率。沿太阳方向估算遮挡，并使用适量散射近似，形成亮边、暗部和层次。夜间需要独立校准月光与环境光，不能简单沿用白天云色。云被雷电照亮需要将空间雷电事件接入密度光照，现有闪光不能自动等同于云内散射。

按视觉收益依次完成：

1. 云底、厚度、世界锚定和运动视差；验证远近、地平线和山体轮廓。
2. 自遮挡、逆光亮边、黄昏与夜间受光；避免纯白平面或灰色噪点。
3. 高低云层分离、风向漂移与天气平滑过渡。
4. 使用同一云密度场生成地面移动云影；独立确认地形、建筑和特殊材质的光照接入方式。
5. 雷电对云体的局部照亮，以及反射环境的更新策略。

## 接入现有天空与同步

保留 `weather_controller.gd`、连续昼夜和现有星空/流星实现。官方示例中的重复天空逻辑应拆除，不整体替换现有世界时钟或夜空。

云体可以半分辨率绘制，星星和流星继续全分辨率合成，通过云透射率正确遮挡。半分辨率是宽高各减半，即约四分之一像素；它不自动提供时域重投影。反射 cubemap 使用单独的低成本路径和受控更新频率。

服务器仍决定共享天气、时间和风。接入时先复用并核对现有协议：世界种子/版本、云覆盖和云型、风场、演变时间锚点；若缺少云底和厚度等必要字段，再同时补齐 mockserver、客户端和 Go 服务端交接文档。参数名称和范围应在实现时正式定稿，本文不建立新网络协议。

客户端根据同一世界位置、种子和服务器时间计算云形与漂移；中途加入和断线重连不重启云动画。风改变时使用连续位移锚点，避免直接用“当前风速 × 从开服起的时间”导致云层跳动。服务器不传输逐帧三维纹理；各端可使用不同采样质量，但宏观云分布应一致。湿润度和积水继续由本地计算，不增加服务器持久化或强制同步。

## 性能、交付与验收

官方示例默认采样数不可直接当成目标配置。低档使用现有层云，中档尝试半分辨率与较少光照采样，高档再增加细节和采样；采用空区跳过、透射率提前终止，并单独测量天空与反射更新成本。未实现时域缓存前，不承诺已有时域稳定性或低步数无噪点。

先在固定镜头、固定天气/时间下比较原版与新方案，记录目标设备、分辨率和 GPU 帧时。至少覆盖晴天积云、阴天、暴雨、夕阳逆光、夜间星空/流星、空间雷电、快速转动和平移相机；检查地平线条带、建筑轮廓漏光、噪点、云层跳变，以及两客户端的云形/演变一致性。

Windows GPU 验证通过 `tools/run_godot_background.py` 在不激活的独立桌面运行，使用临时地图。若新增编辑器云参数，必须同步当前 3D MCP schema、业务校验及文档，完成真实 HTTP 合法/非法调用、无副作用失败、撤销重做、保存重开；不重新启用二维 MCP。
