# 编辑器 DDD 分层重构计划 (Editor DDD Layering Plan)

> 状态：进行中。当前 `content_editor.gd` 仍是 ~3184 行的组合根（上帝脚本），但其依赖的 16 个
> 子模块已被提前拆出。本计划把编辑器按 DDD（领域/应用/基础设施/接口/适配）分层，并在
> 不破坏可运行性的前提下，把界面搭建与编排胶水从上帝脚本中抽离。

## 校验方式（关键）
本机 Godot 在 `D:\tools\godot\Godot_v4.7.2-stable_win64_console.exe`。
每次改动后运行：
```
cd d:/code/rmmo
D:\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --script d:/code/rmmo/tools/_validate_editor.gd
```
该脚本 `preload("res://scripts/editor/content_editor.gd")`，会强制编译编辑器脚本及其**完整 preload 依赖图**，
任何路径错误或语法错误都会立即报错。每个子步骤都必须通过该校验后才能提交。

---

## 阶段 A：把已拆出的 16 个模块归入 DDD 层目录（纯机械、低风险）

`scripts/editor/` 下现有模块按职责迁入子目录，**仅改路径，不改代码逻辑**：

| 模块 | 目标层 |
|------|--------|
| `map_document.gd`, `content_pack.gd`, `paint_tools.gd`, `event_commands.gd`, `tile_labels.gd`, `map_shapes.gd` | `domain/` |
| `pack_zip.gd`, `resource_manager.gd`, `rtp.gd` | `infrastructure/` |
| `map_tree.gd`, `entity_inspector.gd`, `map_minimap.gd`, `tile_palette.gd`, `tileset_manager.gd` | `interface/` |
| `editor_mcp.gd`, `editor_mcp_ops.gd` | `adapters/` |

- `content_editor.gd` 作为组合根（composition root）**保留**在 `scripts/editor/` 根目录，避免改动 `.tscn` 绑定。
- 全仓所有 `scripts/editor/<m>.gd` 引用（`.gd`/`.tscn`/`.tres`/`.remap`）统一改为新路径。
- 校验：移动后 `scripts/editor/<m>.gd`（旧路径）在全仓 0 匹配；`_validate_editor.gd` 通过。

## 阶段 B：把界面搭建从 `content_editor.gd` 抽进 `interface/` 构建器（行为不变）

抽出**纯搭建函数**（传入组合根 `ctrl` 与父节点，内部把信号连回 `ctrl.<方法>`；被调用的
处理方法保留在 `content_editor.gd`，因此逻辑完全不变）。每抽一个文件即校验+提交：

- `interface/editor_menus.gd`：`_build_menu_bar`、`_build_toolbar`、`_vsep`、`_tb_btn`、`_tb_toggle`、`_add_popup`、`_btn`、`_add_lbl`、`_on_menu` 路由（保留分发或迁入此文件）。
- `interface/editor_dialogs.gd`：`_build_asset_window`、`_build_entity_window`、`_popup_win`、`_build_tileset_window`、`_build_map_settings_dialog` 及其弹出/确认处理函数。
- `interface/editor_spec_panel.gd`：`_build_spec_panel`、`_spec_bit_btn`、`_spec_shadow_btn`（仅搭建；`_sync_spec_panel` 状态同步保留在根）。
- `interface/editor_canvas.gd`：相机/缩放/平移/滚动条/坐标换算（`_set_zoom`、`_zoom_at`、`_zoom_fit`、`_mouse_world`、`_clamp_camera`、`_sync_scrollbars`、`_on_hscroll`、`_on_vscroll`、`_canvas_wheel_scroll`、`_canvas_pan_pixels`、`_mouse_cell`、`_fit_layout`）。`_on_canvas_input` 输入路由保留在根，调用 canvas 辅助函数。
- `interface/editor_atmosphere.gd`：光/天气/特效预览与预设加载（`_on_toolbar_light`、`_sync_light_controls`、`_apply_editor_light`、`_on_toolbar_weather`、`_apply_editor_atmosphere`、`_fx_*`、`_fill_preset_opt`、`_fill_bgm_opt`、`_set_far_scroll`）。
- `interface/editor_minimap_bridge.gd`：minimap 绑定（`_rebuild_minimap`、`_schedule_minimap`、`_sync_minimap_view`、`_on_minimap_jump`、`_refresh_bookmarks`、`_on_bookmark_sel`、`_add_bookmark_here`）。

## 阶段 C：把包/地图生命周期编排抽进 `application/`（变更共享态所有权，高风险，单独评审）

- `application/editor_session.gd`：持有 `pack` / `doc` / `current_map_id` / `paint` 会话态聚合，提供开包/新建/保存/选择/切换/删除/重命名/复制/试玩/导入导出用例。
- 根脚本退化为瘦组合根 `EditorController`，仅持有核心节点（`map_field`、相机、视口、状态栏）并委托子系统。

> 阶段 C 涉及 ~150 处 `pack.`/`doc.` 引用重绑，风险高；在阶段 A/B 稳定且经用户确认后再做。

---

## 执行顺序与提交粒度
A →（校验+提交）→ B1 menus →（校验+提交）→ B2 dialogs →（校验+提交）→ B3 spec_panel
→（校验+提交）→ B4 canvas →（校验+提交）→ B5 atmosphere →（校验+提交）→ B6 minimap_bridge。
每个提交都保证 `_validate_editor.gd` 通过，可随时 `git bisect` 回退。

---

## 进度（已实现）

| 步骤 | 提交 | 状态 |
|------|------|------|
| 阶段 A：模块归入 DDD 层目录 | `f4dcce4` | ✅ |
| B1 menus/toolbar → `interface/editor_menus.gd` | `7d0e59a` | ✅ |
| B2 dialogs → `interface/editor_dialogs.gd` | `feac160` | ✅ |
| B3 spec panel → `interface/editor_spec_panel.gd` | `a0fe6f8` | ✅ |
| B4 canvas → `interface/editor_canvas.gd` | `d065e5f` | ✅ |
| B5 atmosphere → `interface/editor_atmosphere.gd` | `5100333` | ✅ |
| B6 minimap bridge → `interface/editor_minimap_bridge.gd` | `88243db` | ✅ |

**结果**：`content_editor.gd` 由 3184 行降至 2475 行；所有纯 UI 搭建/相机/光天气/小地图逻辑已外移到
`scripts/editor/interface/` 下的独立服务类（组合根保留同名 1 行委托，保证既有的外置构建器调用与信号连接零改动）。
每个提交均通过 `D:\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --script tools/_validate_editor.gd`
（强制编译编辑器整张 preload 依赖图）校验。

## 待办：阶段 C（需评审，高风险）

`application/editor_session.gd` 接管 `pack` / `doc` / `current_map_id` / `paint` 会话态聚合，
涉及 ~150 处 `pack.`/`doc.` 引用重绑，会改变共享态所有权。建议用户在引擎内验证编辑器可正常运行后，
再决定何时执行阶段 C。
