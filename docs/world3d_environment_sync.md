# 3D 环境同步协议（MockServer / Go 接入约定）

2026-10-02 体积云已接入：共享环境新增 `cloud_altitude`、`cloud_thickness`、`cloud_scale`、`cirrus_amount`；客户端画质分档不进入服务器配置。资源安装、协议与真实 HTTP / GPU 验收见 [3D 体积云](world3d_clouds.md)。

后续扩展：连续昼夜沿用服务器时钟，雷电新增落点、形状 seed、强度和高度；详见 [环境效果扩展](world3d_environment_effects.md)。实时湿润/积水留在客户端，不添加湿润快照或服务端累积状态。

星空渲染 v2 使用等面积分布、银河密度与星等；协议仍传 seed 和时间，无需逐颗传星。客户端必须使用同一渲染资源版本，旧版与新版同 seed 的星图不同。实现与参考资料见 [星空分布与渲染](world3d_starfield.md)。

2026-10-02。运行时权威源是服务端：天气、天气过渡、风向 / 风速 / 阵风相位、云层位移、世界时间和昼夜时段、星空种子、流星 / 火流星 / 流星雨、闪电时间表。客户端不自行抽取天体事件，不用登录时刻重启流星。雨雪仍是相机附近的本地粒子模拟，服务器同步气候参数；不逐雨滴联网。

当前可执行实现为 `scripts/net/server/sky_module.gd` 和 MockServer 门面。真实 Go 网络传输由另一会话接入；不能把两个独立 MockServer 进程当成同一个共享服务器。编辑器预览使用独立的权威模块实例，F5 使用独立 PreviewServer，均不会修改游戏服务器。

## 服务接口

- `snapshot_world3d_sky(map_id)`：返回下面完整快照，名字保留 sky，但涵盖整个环境。客户端目前每秒读取一次；网络适配器可用订阅 / 推送并缓存最新快照。
- `try_set_world3d_environment(map_id, changes)`：使用 EnvironmentSettings schema 校验，返回 `{ok, environment}` 或 `{ok:false,error}`。MockServer 中是可信游戏脚本 / GM 调用；Go 必须加管理员 / 剧情权限，不能让普通玩家任意改全地图天气或时间。
- `mount_world3d_sky(map_id,path)`：仅本地 MockServer 的地图注册钩子，从允许内容根内的地图读取初始环境。不是网络 RPC。Go 按服务端地图注册表加载初始配置，不能信任客户端传入的路径或环境。
- `issue_world3d_meteor(map_id,event)` / `issue_world3d_meteor_shower(map_id,command)`：仅可信服务脚本调用，不列入玩家请求 API。星空 seed 也仅由服务端 `sky_authority.configure(map_id,seed,rate,enabled)` 设置；切天气、日夜与玩家进出不重抽 seed。

`world.set_weather`、`world.set_night` 已改为请求服务端；接收广播后更新灯光、路灯、天空、风、雨雪。切图重新绑定 map_id；相同地图的服务端临时状态在再次进入时保留，地图文件不被运行时命令覆盖。

## JSON 快照

所有时间是同一服务实例的单调时钟，单位秒，重启用新 epoch。所有坐标是世界 Y 向上、米制；流星方向是单位球面方向，不随玩家或相机改变。

联网必须使用服务端分配的稳定 `pack/map` 标识，与地图 authored `map_ref` 对齐；当前 `prototype/map_<本机路径哈希>` 仅为本地检查地图兜底，不能拿不同机器的绝对路径哈希做共享地图 ID。

```json
{
  "ok": true,
  "map_id": "pack/map",
  "epoch": "server-session-unique-id",
  "sequence": 42,
  "server_time": 100.6,
  "seed": 12345678,
  "environment_revision": 12,
  "environment": {"...": "EnvironmentSettings.resolve 后的完整字段"},
  "source_profile": {"rain":0,"snow":0,"cloud":0.18,"sun":1,"fog":0,"storm":0,"wind":[2.5,0,0]},
  "transition_at": 99,
  "wind_origin": [0,0],
  "time_of_day_hours": 0,
  "time_speed": 0,
  "events": [{"id":"meteor-1","kind":"fireball","brightness":2.5,"start_at":100,"duration":1.2,"from":[-0.2,0.6,-0.7745966692],"to":[0.1,0.4,-0.9110433579]}],
  "lightning_events": [{"id":"flash-1","start_at":115,"position":[120,0,-80],"seed":918,"energy":1.2,"height":90}]
}
```

环境完整 schema 位于 `scripts/world3d/environment_settings.gd`，Go 不应维护缺字段的旧拷贝。新字段：

| 字段 | 范围 / 默认 | 规则 |
| --- | --- | --- |
| `star_intensity` | 0～2 / 1 | 夜间星空亮度，0 关闭星点与淡银河 |
| `meteors_enabled` | true | 允许流星效果及自然事件调度 |
| `meteor_frequency` | 0～12 / 3 | 自然事件每分钟频率，间隔乘服务端随机 0.65～1.35；0 关闭自然调度，仍可由服务脚本发事件 |
| `time_hours` | 0～24 / 白天12、黄昏18、夜晚0 | 初始化 / 手动设置的世界时刻；显式小时决定时段 |
| `time_speed` | 0～3600 / 0 | 游戏秒 / 真实秒；0 暂停，60 即24分钟一个昼夜 |

服务端保留 `clock_hours/clock_at`，`hours = mod(clock_hours + (server_now-clock_at)*time_speed/3600,24)`。6:00～17:00 白天、17:00～20:00 黄昏、其余夜晚。跨时段由服务器更新环境 revision，`transition_at` 采用准确边界时间，不能采用每个客户端收到消息的时间。开启 celestial_cycle 时，客户端按同一时钟连续计算日月轨迹和光色；三档 preset 留给路灯等离散状态。该周期是游戏美术模型，不是天文星历。

客户端用请求发送 / 接收的本地单调时刻计算 `offset = server_time - (sent+received)/2`，随后按 `local_now+offset` 采样。真实传输必须保留真实 RTT / 收包时间，推荐低 RTT 采样；不能把老缓存的 server_time 冒充刚收到的时间。服务端建议至少提前2秒分发事件，快照包含未来65秒及尚未结束的事件，晚加入 / 重连立即计算当前进度。时钟误差受网络延迟不对称影响，不能承诺跨设备逐像素、零毫秒误差。

同 epoch 下 sequence 严格递增；客户端拒绝重复、乱序、倒退时间、错误 map_id、畸形环境 / 轨迹和已退役 epoch。变更失败不改文档 / 服务器状态。新 epoch 清除旧事件，重新同步种子和时间。

## 过渡、风和闪电

服务端切天气时在 `now` 采样旧过渡，保存为 `source_profile`；目标为 `Profile.sample(environment)`。混合权重 `u=clamp((now-transition_at)/weather_transition,0,1)`，使用 `u*u*(3-2*u)`；0秒立即到达目标。中途再次改天气必须从当前状态继续，不能退回上一个整档预设。

阵风系数 `0.82+0.12*sin(server_time*0.7)+0.06*sin(server_time*1.9)`。云层从 `wind_origin` 接着位移：过渡部分使用共享的16段中点积分，之后使用阵风解析积分，系数0.0006。精确参考 `weather_profile.gd:at/drift_at/gust_integral`，禁止按客户端帧数累计，否则晚加入者的云不同。

雷电事件新增 position / seed / energy / height。闪光包络 0～0.06 秒为1，0.11～0.19秒为0.25，其余0，再乘 energy。服务端自然间隔9～19秒，事件间隔至少0.4秒；离开雷暴或关闭闪电清理未来事件，已发生事件保留25秒供距离延迟雷声使用。客户端按服务器指令绘制世界空间折线、分叉及范围照明，雷声按距离/343延迟。字段范围、权限、去重和边界见环境效果扩展文档；旧版只有 id/start_at 的雷电事件不再被新版客户端接受。

## 流星、火流星、流星雨

单事件必需字段：`id` 非空唯一字符串、`start_at` 非负秒、`duration` 0.4～3秒、`from/to` 为 y>0.05 的单位方向，夹角0.01～0.8弧度。`kind=meteor|fireball`（默认 meteor），`brightness` 0～5（默认1）。普通流星蓝白细尾；火流星暖橙色粗尾、头部光晕。强度包络 / 轨迹相位由服务器时间确定，亮度不在客户端随机。最多64个保留事件、同一时刻最多8条；超过上限拒绝，不静默截断。自然事件约8%为火流星，亮度普通0.65～1.25、火流星1.5～2.8，由服务器一次抽取后广播。

集中流星雨命令例：

```json
{"id":"shower-1","radiant":[0,0.8,-0.6],"start_at":300,"count":8,"interval":0.25,"kind":"fireball","brightness":2.5}
```

`count` 1～24、`interval` 0.1～3秒、radiant 为同一单位辐射方向。服务端一次生成全部独立轨迹及编号 `id/index`，原子验证并加入共享时间表；客户端不从 radiant 再次随机生成。非法批量不改变事件列表或服务端 RNG 状态。

GPU 在世界方向上画最多8条流星，云与地平线雾遮挡，雨雪 / 浓雾降低能见度，白天不显示；流星不进入慢更新的天空反射 cubemap。个人关闭天气特效可隐藏动态事件，不改变共享服务器状态或事件进度。恒星位置由服务器 seed 固定，微弱闪烁由服务器时间驱动；不使用客户端 TIME 或随机种子。

## 验收

`tools/test_world3d_sky_sync.gd`：两个不同本地时钟的客户端、晚加入、过期 / 重复 / 乱序 / 错图 / 畸形事件、服务器环境原子失败、打断天气与云位移连续、时间倍率跨黄昏边界、同屏流星雨类型亮度、真实 HTTP MCP 的发现 / 合法非法 / 撤销重做 / 保存重开，以及后台 GPU 星空、普通流星、火流星。

```powershell
& 'D:/tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path D:/code/rmmo --script res://tools/test_world3d_sky_sync.gd
python tools/run_godot_background.py --timeout 200 --log D:/code/rmmo_runtime/sky_sync_gpu.log -- D:/tools/godot/Godot_v4.7.2-stable_win64.exe --path D:/code/rmmo --script res://tools/test_world3d_sky_sync.gd
```

Go 接入还需做真实多连接广播、鉴权、重连快照、网络延迟 / 乱序、跨图隔离、共享时间服务和同一条流星的双客户端并排验收；不能只复制客户端 shader。不要覆盖或移除 MockServer，它继续用于离线开发与编辑器试玩。
