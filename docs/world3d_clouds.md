# 3D 体积云

2026-10-02。游戏与 3D 编辑器共用 `weather_controller.gd` / `weather_sky.gdshader`，默认中档体积云。算法与噪声素材基于 Godot 官方 MIT Sky Shaders 示例，固定版本和哈希见 `tools/cloud_assets.json`；授权保留在 `docs/licenses/Godot-clouds-MIT.txt`。技术出处见 [调研](world3d_cloud_research.md)。

## 已实现

- 世界坐标云底与厚度，相机平移视差；云团使用 Perlin-Worley 体积噪声及高频侵蚀，高度剖面形成平云底和隆起云顶。
- 光线步进、Beer 透射率、沿日月方向的自遮挡与近似散射；晴天、雨雪和雷暴通过现有云覆盖率连续变化。高空薄云使用独立层。
- 空间雷电按服务器事件的闪光强度，在落点附近照亮云体；这是局部散射近似，不是完整的云内电弧模拟。
- 云在半分辨率通道绘制，星空、月亮和流星继续全分辨率合成，并受云透射率遮挡。反射 cubemap 单独采用 12 步简化云；64 像素 radiance 和增量更新保持现有设置。
- 固定方向抖动打散射线采样层纹，没有逐帧随机噪声、额外客户端随机流或时域历史依赖。

## 编辑器与 MCP

| 字段 | 默认 | 范围 | 语义 |
| --- | --- | --- | --- |
| `cloud_altitude` | 600 | 200～3000 | 云底世界 Y 坐标，米；不是相机相对高度 |
| `cloud_thickness` | 550 | 100～1800 | 云体垂直厚度，米 |
| `cloud_scale` | 2400 | 400～8000 | 三维噪声空间尺度，米 |
| `cirrus_amount` | 0.22 | 0～1 | 高层薄云量；高度为云顶再加 2500 米 |

现有 `get_environment` / `set_environment` 自动使用共享 schema，UI 和 MCP 经过同一环境操作、文档校验、撤销与保存。没有新增工具或重新启用二维 MCP。

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"set_environment","arguments":{"cloud_altitude":850,"cloud_thickness":700,"cloud_scale":3200,"cirrus_amount":0.4}}}
```

旧地图缺省使用默认云参数；云覆盖率继续由 `weather` 和 `weather_intensity` 决定，避免另设一组与天气冲突的覆盖值。

## 本地画质与资源

系统设置 → 画面 → 性能 → 云层画质，选择低、中、高。`GameSettings.cloud_quality` 保存到本机配置，取值 `low` / `medium` / `high`，默认 `medium`。三档使用同一云密度场，只改变视线/光照采样数（20/1、48/3、80/5）；宏观云形不因画质档位重新随机生成。

噪声纹理位于外部内容根的 `assets/weather/clouds`，128³ 基础噪声和 32³ 细节噪声转换成共享 ImageTexture3D，仅首次使用加载。部署新内容包时运行：

```powershell
python tools/install_cloud_assets.py D:/code/rmmo_runtime
```

安装器固定上游 Git 提交并验证 SHA-256，附带授权与来源记录，运行时不联网。资源缺失或尺寸错误会给出提示并回退到原有层云；这是资源异常回退，正常低画质仍使用共享体积云。素材不放入 `res://`，不能仅复制代码而遗漏外部内容包。

## 服务端契约

四个新字段属于 `environment` 的地图配置，mockserver 通过已有环境 schema 和快照路径保存、验证、下发；Go 服务端需补齐同名默认值和范围。当前客户端严格验证完整环境快照，服务端须一起更新。

继续复用快照 `seed`、`wind_origin`、`transition_at`、`source_profile`、`server_time` 与天气过渡。无需新增逐帧消息、独立随机云事件或三维纹理传输。

`seed` 通过整数 LCG 生成三维噪声偏移：连续三次 `state=((state^(state>>16))*1103515245+12345)&2147483647`，每轴 `(state%65536)/65536`。完整 31 位种子参与整数运算，避免先转 GPU float 导致相邻大种子相同。噪声纹理版本必须随内容包一致。

漂移采用现有 `Profile.drift_at` 的积分结果；shader 使用 `world_xz - drift/0.0006`，因此正风速向世界正方向搬移云形。天气或风切换时由已有 `wind_origin` 连续锚定，中途加入不从零重播。编辑器预览也使用其隔离的权威实例计算漂移。

`cloud_quality` 不属于服务器 `environment`；湿润度、积水仍是本地状态，不新增服务端持久化。

## 验证与边界

`tools/test_world3d_clouds.gd` 包含真实 HTTP 工具发现、合法/非法参数、失败无副作用、单事务 UI 更新、撤销重做、保存重开，以及双客户端时钟/种子一致、风切换连续、非法快照原子拒绝。GPU 验证生产 shader 的静态稳定、种子差异、移动视差、位移方向/尺度、厚度、高空薄云和局部雷电照明，并生成晴天、阴云、雷暴、夕阳、夜晚截图。

```powershell
python tools/run_godot_background.py --timeout 240 --log D:/code/rmmo_runtime/clouds.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_clouds.gd
```

目标是地面城镇视角。云目前绘制在天空背景，未做穿云时对前景几何的体积遮挡，没有时域重投影；低档远云细节比高档粗糙。云对地面和建筑的空间投影仍是独立后续项，不能把现有天气对主光的整体衰减当成地面云影。

### 本机验收记录

Godot 4.7.2，Vulkan Forward+，AMD Radeon RX 7900 XTX，1920×1080，隔离天空视口。预热后测量 40 帧，同时持续更新漂移参数，GPU 时间中位数 / P95：低档 0.477 / 0.502 ms，中档 0.848 / 0.920 ms，高档 1.468 / 1.580 ms。这是该测试天空视口的 GPU 时间，不是复杂城镇整帧时间或相对旧版的净增量，也不是其他硬件的性能保证。

- `clouds_acceptance.log`：全部通过，含真实 HTTP、生产 shader 的 GPU 像素验证，以及相反日月方向在黄昏的连续性。
- `clouds_environment_regression.log`：连续昼夜、湿润/遮雨、雷电与雷声回归通过。
- `clouds_weather_regression_final.log`：雨雪、天气中断/过渡、运行时地图切换及场景 GPU 回归通过。
- `clouds_starfield_regression.log`：星空分布、亮度、抗锯齿能量和全分辨率天空回归通过。
- `test_world3d_sky_sync.gd`、`test_world3d_wind.gd`、`test_game_settings.gd`：权威快照、风与本地云画质持久化回归通过。

日志位于本机 `D:/code/rmmo_runtime`，截图位于外部内容根 `review_artifacts/clouds3d`；不覆盖用户地图。正式 Go 服务端的四字段契约已交接给“重写 Go 服务端地图寻路”会话，本任务验证的是 mockserver 与客户端。
