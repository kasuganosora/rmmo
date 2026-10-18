# 真实服务器通信分支

分支：`feat/real-server-transport`，基于客户端 `c333a6466009d910957b2b05d8fc58ad2f81741f`。
Go 协议基准：`rmmo_server` 的 `01d1128c08bfcf47af964ecd2957eb16a011f29c`。
本分支只修改功能代码、配置和测试；不修改地图、角色、模型或纹理资源。

## 开关与连接

登录页展开“连接设置”，勾选“连接真实服务器”并填写地址。未勾选时继续使用
MockServer。切换只在退出登录后进行；真实服务器断开或返回错误时保持真实模式。
真实账号由“注册真实服务器账号”按钮创建，登录失败不会自动注册。

也可以使用启动参数：

```sh
godot --path /path/to/rmmo -- --backend=real --server-url=http://127.0.0.1:7777
godot --path /path/to/rmmo -- --backend=mock
```

配置优先级：项目设置 < 环境变量 < 命令行。命令行参数放在 Godot 的 `--` 之后。
环境变量为 `RMMO_CLIENT_BACKEND=mock|real`、`RMMO_SERVER_URL`。账号密码、Bearer token
和世界票据只保留在内存，不写入项目、日志或用户配置。

| 项目设置 | 默认值 | 用途 |
| --- | --- | --- |
| `rmmo/network/use_real_server` | `false` | 启动连接模式 |
| `rmmo/network/server_url` | `http://127.0.0.1:7777` | 服务端源地址 |
| `rmmo/network/request_timeout_sec` | `10` | 连接、RPC 和 HTTP 超时，限制在 1–60 秒 |
| `rmmo/network/movement_hz` | `20` | 方向意图发送频率，限制在 5–30 Hz |
| `rmmo/network/map_paths` | `{}` | 服务端地图身份到本地资源路径的显式映射 |

地址支持 `http` / `https` / `ws` / `wss`，不带路径；传输自动使用 `/ws` 和 `/v1/`。
HTTPS 对应 WSS，保留系统证书验证。HTTP 业务接口禁止跳转，避免跨源转发认证头。

## 地图配置

客户端和服务端必须安装对应资源包，但资源根可以不同。客户端从服务器返回的
`map_ref` 选择视觉地图，使用服务器的脚底米制位置加 0.9m 得到角色中心。
不能再以作者机器上的绝对路径、默认出生点或本地路径哈希替代服务器身份。

默认通过资源包目录查找唯一的 `pack_id/map_name`。存在不同版本、缓存地图或
自定义文件布局时，显式配置，例如在 `project.godot` 的 `[rmmo]` 段中：

```ini
network/map_paths={
"default/editor_yard": "packs/default/maps/editor_yard/map.gltf",
"prototype/shared_yard": "cache/world3d/p4_yard/map.gltf"
}
```

相对路径以客户端 `rmmo/content_root` 为根；绝对路径也必须位于该根内。
已有地图若声明 `map_ref`，必须与服务器返回值一致。缺失、歧义、越界或身份不同
会中止入场，不生成或覆盖用户地图。

服务端示例：

```sh
gameserver -content /path/to/server-content -map default/editor_yard
```

## 已接通的流程

- 二进制 Protobuf / WebSocket 注册、登录、角色列表和基础外观建角。
- `enter_world`、世界会话 v2、地图加载后的 Ready 票据、主动退出及重连。
- 服务器时间推进的方向、跑步和跳跃意图；客户端只显示服务器位置，不运行
  MockServer 的物理、重力、NPC AI、奖励和战斗模拟。点击寻路使用 Go 返回的路径。
- 自身/附近玩家快照、带实例 generation 的离开通知、服务器传送后的重新加载。
- 带 Bearer 的 JSON GET 和带完整 WorldContext 头的 POST 入口。
- 入场时恢复背包、属性、成长、生命、实体、技能、状态、区域、队伍、联盟、奖励、
  环境及附近地图交互快照；分页交互完成后再次核对世界会话，再允许 Ready。
- 周期刷新生命、背包、成长、环境和附近交互；门窗的服务器状态应用到运行时
  碰撞/表现，E 键向服务器提交附近对象的首个可用交互。

Ready 前、断线后和错误世界代次下不发送移动。地图变化会取消旧路径/Ready 回调，
旧请求不会换上新上下文自动重放。Leave 错误时查询 `/v1/world/session` 恢复结果，
不会盲目重复 Leave。异步 HTTP 和 RPC 在断开时都会得到失败结果。

## 后续对接边界

这是实际可用的通信基础与三维入场/移动接入，尚未完成全部 MMO 业务界面的适配。
现有 Go 协议没有自定义捏脸字段，因此真实模式创建页使用基础外观；不会丢弃
用户编辑的捏脸数据后谎报已保存。附近玩家协议目前只有空间状态，角色表现使用
现有默认模型；完整外观、装备和表情广播仍需扩展协议。

战斗施法、NPC 对话/任务、商店、交易、邮件、公会、背包写操作的 UI 适配、复活、
坐椅子和本地主动传送等尚未接入时，会返回 `unsupported_remote_operation` 或保持
不可用。可以通过 `RealServer.request_api()` 对接现有业务端点，但不能据此视为
相关界面已经完成。读取到的原始业务快照保存在 `business_snapshots`；尚未转换的
技能/任务/队伍界面不展示模拟数据。

`remote_boundary.gd` 自动覆盖 MockServer 的所有 `try_*` / `snapshot_*`；真实实现
显式覆盖已支持的方法。复用的目录与 HUD 模型仅作为显示缓存，不构成服务器授权。
后续增加 Mock 接口必须重新生成并检查边界，避免继承到本地业务行为。

## 验证和复现

```sh
python3 tools/generate_server_protocol.py --check
python3 tools/generate_remote_boundary.py --check
python3 tools/test_network_regressions.py
godot --headless --path . --script res://tools/test_real_server.gd -- --backend=real
python3 tools/test_real_server_integration.py \
  --server-bin /absolute/path/to/gameserver \
  --server-repo /absolute/path/to/rmmo_server
```

协议描述由所附 `scripts/net/protocol/game.proto` 生成，保留原文件 SHA256。
更新服务端协议后复制该文件并运行 `generate_server_protocol.py`，不要手工改描述表。
通信编解码限制帧大小、嵌套深度和字段数量；uint64 序号通过 Protobuf 整数传递。

集成脚本在临时目录复制服务端自带的合成示例资源，启动真正的 Go 服务，再运行
Godot。覆盖注册、基础建角、状态恢复、Ready、权威移动、服务器寻路、HTTP 鉴权和
世界请求头、旧代次隔离、断开回调、重连及退出后账号/角色仍可读取。
不会连接生产账号或修改用户资源；图形角色、完整真实地图和公网 TLS 部署仍需
在拥有对应资源的运行环境完成验收。

本轮结果：真实 Go 服务联调及连接边界测试共 56 项通过，现有 NetClient、
RequestPipeline 和路径消费回归共 50 项通过；20 个新增/修改的 GDScript
通过 Godot 解析检查，Python 语法、生成描述表与边界同步检查通过。
