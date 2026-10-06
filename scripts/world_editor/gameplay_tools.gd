extends RefCounted
## Shared, atomic authoring operations for UI and the current 3D MCP.
const Templates = preload("res://scripts/world3d/event_templates.gd")
const EnvironmentSettings = preload("res://scripts/world3d/environment_settings.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Net = preload("res://scripts/net/net.gd")
var editor: Node3D

func guard() -> Dictionary:
	if editor._ground_draw!=null and editor._ground_draw.active: return {"ok":false,"error":"请先完成或取消地表区域绘制"}
	if editor._city.busy(): return {"ok":false,"error":"请先提交或取消道路草案 / 节点拖动"}
	if editor._playtest != null and editor._playtest.active(): return {"ok":false,"error":"试玩期间不能修改编辑文档，请先停止试玩"}
	if editor._authoring.picking: return {"ok":false,"error":"请先完成或取消出生点拾取"}
	if editor._building_area_busy(): return {"ok":false,"error":"请先完成或取消建筑区域框选"}
	if editor._load_failed: return {"ok": false, "error": "地图加载失败，当前为只读模式"}
	if editor._safety.state().close_pending: return {"ok": false, "error": "请先处理关闭提示"}
	if editor._transform_drag.active or editor._auto_stroke.active or editor._selection_tools.marquee or editor._stroke._open or editor._placement_tools.active or editor._material_tool.active or (editor._terrain_brush!=null and editor._terrain_brush.active): return {"ok": false, "error": "请先完成当前画布操作"}
	return {"ok": true}

func resources() -> Dictionary:
	var server = Net.server()
	var items: Array = []
	var shops: Array = []
	for id in server.item_catalog.all_ids():
		var item: Dictionary = server.item_catalog.get_item(id)
		items.append({"id": id, "name": item.get("name", id)})
	for id in server.shop_catalog._shops:
		shops.append({"id": id, "name": server.shop_catalog.shop_title(id)})
	return {"ok": true, "items": items, "shops": shops}

func prepare(type: String, parameters: Dictionary) -> Dictionary:
	var result := Templates.prepare(type, parameters)
	if not result.ok: return result
	var p: Dictionary = result.value.parameters
	var server = Net.server()
	for field in ["item_id", "required_item"]:
		if not str(p.get(field, "")).is_empty() and not server.item_catalog.has_item(p[field]): return {"ok": false, "error": "物品不存在：" + str(p[field])}
	if type == "shop" and not server.shop_catalog.has_shop(p.shop_id): return {"ok": false, "error": "商店不存在"}
	if type == "transfer" and not FileAccess.file_exists(p.map_path): return {"ok": false, "error": "传送目标地图不存在"}
	return result

func create_event(type: String, position: Vector3, parameters: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	if not position.is_finite() or position.abs()[position.abs().max_axis_index()] > 100000: return {"ok": false, "error": "事件位置超出范围"}
	var result := prepare(type, parameters)
	if not result.ok: return result
	var doc = editor._doc
	doc.checkpoint()
	var size_ := Vector3(.8, .8, .8) if type != "transfer" else Vector3(1.2, .1, 1.2)
	var id: String = doc.add_box_silent("event", position + Vector3(0, size_.y / 2, 0), size_)
	var record: Dictionary = doc._find(id)
	record.event_template = result.value
	record.editor_name = result.value.parameters.name
	record.color = {"dialogue": [.3,.6,.8], "chest": [.72,.48,.16], "gather": [.35,.65,.3], "transfer": [.6,.35,.8], "shop": [.8,.5,.35]}[type]
	if type == "transfer": record.collision = "none"
	changed()
	editor._selection_tools.set_ids([id]); editor._set_mode(1)
	return {"ok": true, "id": id, "event_template": result.value, "event": Templates.compile(result.value)}

func set_event(id: String, type: String, parameters: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var record: Dictionary = editor._doc._find(id)
	if record.is_empty() or not editor._record_editable(record): return {"ok": false, "error": "物件不存在、被隐藏、锁定或不在当前楼层"}
	if record.get("kind") in ["warp", "seat"] or record.get("hostile", false) or record.get("ally", false): return {"ok": false, "error": "椅子、旧传送点、战斗角色已有独立交互，不能附加事件模板"}
	var previous: Dictionary = record.get("event_template", {})
	if type.is_empty(): type = str(previous.get("template", "dialogue"))
	var merged: Dictionary = previous.get("parameters", {}).duplicate(true) if previous.get("template") == type else {}
	merged.merge(parameters, true)
	var result := prepare(type, merged)
	if not result.ok: return result
	if previous == result.value: return {"ok": true, "changed": false, "event_template": result.value}
	editor._doc.checkpoint()
	record.event_template = result.value
	changed()
	return {"ok": true, "changed": true, "event_template": result.value, "event": Templates.compile(result.value)}

func clear_event(id: String) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var record: Dictionary = editor._doc._find(id)
	if record.is_empty() or not editor._record_editable(record): return {"ok": false, "error": "物件不存在、被隐藏、锁定或不在当前楼层"}
	if not record.has("event_template"): return {"ok": true, "changed": false}
	editor._doc.checkpoint(); record.erase("event_template"); changed()
	return {"ok": true, "changed": true}

func set_environment(changes: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var invalid := EnvironmentSettings.Schema.validate(changes, EnvironmentSettings.schema())
	if not invalid.is_empty(): return {"ok": false, "error": invalid}
	var value := EnvironmentSettings.updated(editor._doc.map_meta, changes)
	if value == EnvironmentSettings.resolve(editor._doc.map_meta): return {"ok": true, "changed": false, "environment": value}
	editor._doc.checkpoint_recovery()
	editor._doc.map_meta.environment = value
	editor._dirty = true
	editor._apply_environment()
	return {"ok": true, "changed": true, "environment": value}

func changed() -> void:
	editor._dirty = true
	editor._rebuild()
