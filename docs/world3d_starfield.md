# 3D 程序星空：分布与渲染 v2

2026-10-02。生产实现是 `scripts/world3d/star_field.gdshaderinc`，由 `weather_sky.gdshader` 共用。这是受天文渲染资料启发的游戏程序星空，未导入真实星表，不对应真实星座，也不是对 Gaia 数据的拟合。

## 参考资料与取舍

| 论文 / 技术文档 | 本项目采用的原则 |
| --- | --- |
| Jensen 等，SIGGRAPH 2001，[A Physically-Based Night Sky Model](https://graphics.stanford.edu/papers/nightsky/) | 区分恒星位置、星等、颜色、银河背景与大气影响。论文使用真实星表和银河图像；本项目采用可由服务器种子复现的统计近似，未复现论文的整套物理模型。 |
| Snyder，USGS 1987，[Map Projections—A Working Manual](https://pubs.usgs.gov/pp/1395/report.pdf)，§24 Lambert Azimuthal Equal-Area；[PROJ LAEA 文档](https://proj.org/en/stable/operations/projections/laea.html) | 等面积投影避免把平面点密度误当成球面点密度。使用上半球到圆盘的 Lambert 等面积映射。 |
| [PBRT 4e：Spherical Geometry](https://www.pbr-book.org/4ed/Geometry_and_Transformations/Spherical_Geometry) | 以立体角衡量采样密度。PBRT 的方形等面积映射不是这里直接采用的圆盘公式。 |
| [Gaia Sky：Star rendering](https://gaia.ari.uni-heidelberg.de/gaiasky/docs/master/Star-rendering.html) | 用星等的指数关系控制亮度，而不是给每颗星相近的随机亮度。本项目使用视星等，不模拟距离或绝对星等换算。 |
| [Gaia EDR3 星密度验证](https://gea.esac.esa.int/archive/documentation/GEDR3/Catalogue_consolidation/chap_cu9val/sec_cu9val_943/ssec_cu9val_943_star_density.html)、[ESA Gaia 天空图](https://www.esa.int/ESA_Multimedia/Images/2020/12/Interactive_map_of_the_sky_from_Gaia_s_Early_Data_Release_3) | 星密度随天空方向、星等变化；银河平面、中央集中与前景尘埃不能只画成一条独立的亮带。 |
| Robin 等，2003，[A synthetic view on structure and evolution of the Milky Way](https://www.aanda.org/articles/aa/pdf/2003/38/aa3188.pdf) | 银河种群模型按密度抽样并包含 Poisson 波动。这里不把蓝噪声的均匀最小间距当成真实星空分布。 |
| [PBRT 4e：Sampling Theory](https://www.pbr-book.org/4ed/Sampling_and_Reconstruction/Sampling_Theory) | 小于像素的光源需要滤波。这里使用归一化的高斯像素足迹近似，避免相机移动时星点能量大幅跳动。 |

## 分布与亮度

旧实现把规则平面格子投影到天空，使用 `direction.xz / (1 + direction.y)`。相同平面点密度对应的球面密度在地平线附近约为天顶的四倍，并非有意的银河结构。

v2 对单位方向 `d` 使用 `p = d.xz / sqrt(1 + d.y)`。上半球对应单位圆盘，`dΩ = 2 dp.x dp.y`。逆映射是 `(p.x sqrt(2-r²), 1-r², p.y sqrt(2-r²))`，`r² = dot(p,p)`。因此基础候选点在立体角意义上均匀。

圆盘划分为每轴 256 格，在每格内用服务器 seed 的整数 hash 生成一个随机候选，再按方向密度稀疏接受。基础密度加上银河盘、中央集中项，并受有斑块的尘埃带衰减。平均接受率很低；这是稀疏分层 Bernoulli 近似，单格最多一颗，并非严格 Poisson 点过程。保留自然的小间距组合，不额外施加蓝噪声排斥距离。

视星等范围 `0.3～6.8`，按累计分布 `N(m) ∝ 10^(0.32m)` 反采样，让暗星多、亮星少。辐射相对强度使用 `10^(-0.4m)`，差 5 星等为 100 倍。星等范围、0.32 斜率、曝光 65、银河方向与各密度系数均是美术参数，没有宣称来自实测拟合。颜色是暖白到冷白、按亮度归一的调色板，不是黑体谱计算。

星点和银河微光使用相同的银河方向、中央集中、尘埃函数，避免亮带与星点密度脱节。地平线有简化消光；星点轻微闪烁且低空更明显。银河和星点固定于世界方向，云层按同步风场漂移。

## 滤波与成本

星点的角向高斯宽度为 0.0005 弧度，叠加由方向导数估计的像素足迹；足迹标准差约为 0.55 像素。扩大光斑时相应减小峰值，保存积分通量。这是实用高斯滤波，不是精确方形像素积分。

通常查询当前格与八个邻格，避免格子边缘切断星点。低分辨率时扩大到三倍标准差范围，最大半径四格；极低分辨率、超广视角仍是有界近似。64 像素天空反射贴图只保留银河微光，不绘制无法稳定解析的独立星点或短时流星。

## 同步与编辑器

协议不变：服务器提供 `seed` 与统一时间，客户端按相同版本的整数 hash 和分布算法生成星空。切天气、日夜和进出地图不会重抽种子；闪烁相位来自服务器时间。Go 无需逐颗发送恒星，也不需要移植这段 GPU shader。流星种类、亮度、位置、事件时间仍来自服务器指令。

同一种子在 v1 / v2 下的图案不同，联机客户端须使用同一资源版本；跨显卡不承诺浮点着色结果逐像素一致。此次未新增编辑器能力或参数，继续复用现有 UI / 3D MCP 的 `star_intensity` 和服务端同步约定，未增加本地随机种子设置。详见 [环境同步协议](world3d_environment_sync.md)。

## 验收

`tools/test_world3d_starfield.gd` 在真实 Vulkan GPU 上直接调用生产 shader include，并读取浮点像素，未另写 CPU 版算法作为自证。

- 种子 `12345678` 上半球 1917 颗；同 seed 结果相同，换 seed 结果改变。
- 五个等立体角高度带候选数：10323 / 10308 / 10276 / 10297 / 10281，最大相对偏差不到 0.3%。
- 视星等 `<3 / 3～5 / ≥5` 分别为 108 / 399 / 1410 颗；银河带单位面积密度约为带外 2.48 倍。
- 相差 5 星等的 shader 通量比为 100；四档分辨率、四种亚像素偏移下，单星滤波通量的最大变化约 0.51%。该指标验证点扩散函数，不代表所有场景中整幅天空完全无闪烁。
- RX 7900 XTX / Godot 4.7.2 / 1280×720 的一次暖机 GPU 采样中，天空视口中位用时约从 0.20 ms 增至 0.33 ms。它是画质改进的额外成本，不是性能提速；不同硬件、分辨率和功耗状态会改变结果。

后台测试命令（不会激活用户桌面上的窗口）：

```powershell
python tools/run_godot_background.py --timeout 150 --log D:/code/rmmo_runtime/starfield_quality.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_starfield.gd
python tools/run_godot_background.py --timeout 200 --log D:/code/rmmo_runtime/starfield_sync.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_sky_sync.gd
```

质量测试会输出 `weather3d/starfield_after.png` 美术预览；可选 `-- --baseline=<旧 shader 的绝对路径>` 输出同参数 before 图和计时。同步回归覆盖真实 HTTP MCP 发现、非法输入无副作用、撤销重做、保存重开，以及服务器种子、时间、普通流星、火流星和集中流星雨。
