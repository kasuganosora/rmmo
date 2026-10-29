# 任务追踪 Mock 测试隔离验收（2026-10-29）

`tools/test_quest_tracker.gd` 的三个任务联动失败由外部任务目录缺失引起，已用测试专用临时 JSON 夹具修复。原有 24 个断言全部保留；新增实际 Mock 后端和夹具加载/清理检查后，默认命令共 26 项通过、退出码 0、零 `ERROR:`。

## 修复前的实际复现

使用 Godot 4.6.3 headless，在当前代码 `acdaab7` 及旧提交 `ecc6d05` 的完整独立提取副本分别运行原版测试。旧提交通过 `git archive ecc6d05` 提取到 `/tmp/rmmo-quest-tracker-ecc6d05-71q3qq_h`，没有切换共享分支；只复制导入缓存供资源解析，全部源码来自旧提交。

两次均退出 1，以下三个断言失败，其他 21 项通过：

- `accept herb_gather`
- `live journal progress in tracker text`
- `live text non-empty`

修复前日志逐字节相同：

| 代码 | 日志 |
| --- | --- |
| 当前原版 | `/tmp/rmmo-quest-tracker-current-mock.log` |
| `ecc6d05` 原版 | `/tmp/rmmo-quest-tracker-ecc6d05-mock.log` |

共同 SHA-256：`fb956ae9dad023a7c12444b697b2f25a1f22fd22dd3c8964bbb09e61b41b2bce`。

`quest_journal.gd`、`json_util.gd`、`quest_tracker_util.gd`、`asset_manager.gd` 和原版 `test_quest_tracker.gd` 在两个提交之间也逐字节相同。因此这些失败并非本轮真实服务器玩法改动引入。

## 两条缺失内容依赖

生产加载链为 `QuestJournal.load_catalog()` → `JsonUtil.load_first(["combat/quests.json"])` → `AssetManager.data_file()` → `{content_root}/data/combat/quests.json`。该文件缺失时，Mock 回退目录只有 `starter_step`、`slime_hunt`、`welcome_gift` 和 `rat_cleanup`，没有 `herb_gather`。

独立只读探针 `/tmp/rmmo-quest-tracker-content-probe.log` 实际输出：

```json
{
  "catalog_path": "/tmp/rmmo-quest-tracker-review/data/godot/app_userdata/rmmo/content/data/combat/quests.json",
  "catalog_exists": false,
  "herb_catalog_entry": {},
  "fallback_starter_present": true,
  "map_ref": "content://map_pack/default",
  "resolved_map_path": "/tmp/rmmo-quest-tracker-review/data/godot/app_userdata/rmmo/content/packs/map_pack/default",
  "map_pack_exists": false
}
```

默认 Mock 启动另有三条缺失地图报错：无法打开 `content://map_pack/default/pack.json`、地图包加载失败、碰撞加载失败。这是无关的二维启动依赖；任务目录不从该地图包读取。没有把地图缺失误当作三个任务断言的直接根因。

## 测试改动及最终验证

测试创建唯一 `user://quest_tracker_<pid>_<ticks>/data/combat/quests.json`，包含真实 `herb_gather` 定义及 `wild_herb` 的 0/5 目标。仅在同步 `load_catalog()` 期间设置 `AssetManager.content_root_override`，随后立即恢复，并删除本次创建的精确文件和空目录。接取、物品增加、快照、追踪文本与 HUD 仍执行生产逻辑；没有向私有目录字段注入结果，也没有削弱断言。

启动隔离沿用 `tools/test_network_regressions.py` 的顺序：进程内暂缓 Mock 自动启动，设置既有 `world3d` profile，然后通过 `ServerConnection.configure(false)` 初始化真正的 Mock 后端。新增断言同时验证配置成功、模式为 `mock`、`Net.server()` 正是 `MockServer`。项目设置不写回磁盘，不屏蔽日志，不修改生产 Mock。

当前代码默认命令：

```sh
XDG_DATA_HOME=/tmp/rmmo-quest-tracker-current-isolated-mock/data \
XDG_CACHE_HOME=/tmp/rmmo-quest-tracker-current-isolated-mock/cache \
XDG_CONFIG_HOME=/tmp/rmmo-quest-tracker-current-isolated-mock/config \
godot --headless --path /workspace/rmmo --script res://tools/test_quest_tracker.gd
```

同一修复后的测试还复制为旧提交临时副本中的 `tools/test_quest_tracker_with_fixture.gd`，使用 `ecc6d05` 的生产脚本执行。两次均 **26 项通过、退出 0、零 `ERROR:`**；最终日志同样逐字节相同：

| 代码 | 日志 |
| --- | --- |
| 当前修复后 | `/tmp/rmmo-quest-tracker-current-isolated-mock.log` |
| `ecc6d05` + 同一测试夹具 | `/tmp/rmmo-quest-tracker-ecc6d05-isolated-mock.log` |

共同 SHA-256：`f0fd2237168d892c83bf86a5129f218887df547a367babe7f4467511fbd71ca0`。

本次只修改该测试及本报告；未修改正式地图、美术、生产 Mock 或真实服务器实现。结论覆盖任务追踪的 Mock/HUD 联动与测试隔离，不代表缺失的外部正式资源包已经补齐。

主任务工具链补验：使用 `/workspace/.cloud-setup/env.sh` 中的 Godot 4.7.2，对当前测试再运行默认命令，26 项通过、退出 0、零 ERROR，日志 `/workspace/.cloud-setup/gameplay3-acceptance-mock-4.7.2.log`。上述旧提交对照仍是 Godot 4.6.3 的实际结果。
