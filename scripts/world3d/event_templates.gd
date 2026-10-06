extends RefCounted
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const LABELS = {"dialogue": "对话", "chest": "宝箱", "gather": "采集", "transfer": "传送", "shop": "商店"}
const COMMON = {"name": "", "enabled": true, "trigger": "action", "required_switch": "", "required_item": "", "required_quantity": 1, "set_switch": "", "offset": [0, 0, 0], "touch_size": [1.2, 1.2, 1.2], "radius": 2.0}
const SPECIFIC = {
	"dialogue": {"text": "你好！", "once": false, "empty_text": "我们已经聊过了。"},
	"chest": {"text": "打开了宝箱。", "item_id": "", "quantity": 1, "gold": 10, "once": true, "empty_text": "宝箱已经空了。"},
	"gather": {"text": "采集完成。", "item_id": "", "quantity": 1, "once": true, "empty_text": "这里已经采集过了。"},
	"transfer": {"map_path": "", "spawn": [0, 0, 0]},
	"shop": {"shop_id": ""},
}

static func parameters_schema() -> Dictionary:
	var fields := {}
	for key in ["name", "text", "empty_text", "item_id", "required_item", "required_switch", "set_switch", "shop_id", "map_path"]: fields[key] = {"type": "string", "maxLength": 4096 if key in ["text", "empty_text"] else 2048}
	for key in ["enabled", "once"]: fields[key] = {"type": "boolean"}
	fields.trigger = {"type": "string", "enum": ["action", "player_touch"]}
	for key in ["quantity", "required_quantity"]: fields[key] = Schema.number(1, 999, true)
	fields.gold = Schema.number(0, 1000000, true)
	fields.offset = Schema.vector(-100, 100); fields.spawn = Schema.vector(-100000, 100000)
	fields.touch_size = Schema.vector(.1, 32); fields.radius = Schema.number(.5, 6)
	return {"type": "object", "properties": fields, "additionalProperties": false}

static func defaults(type: String) -> Dictionary:
	var result: Dictionary = COMMON.duplicate(true)
	result.merge(SPECIFIC.get(type, {}).duplicate(true))
	result.name = LABELS.get(type, "")
	if type == "transfer": result.trigger = "player_touch"
	return result

static func prepare(type: String, parameters: Variant, content_root: String = "") -> Dictionary:
	if not LABELS.has(type): return {"ok": false, "error": "不支持的事件模板"}
	var error := Schema.validate(parameters, parameters_schema())
	if not error.is_empty(): return {"ok": false, "error": error}
	var values := defaults(type)
	for key in parameters:
		if not values.has(key): return {"ok": false, "error": "此模板不支持参数：" + str(key)}
		values[key] = parameters[key]
	for key in ["name", "item_id", "required_item", "required_switch", "set_switch", "shop_id", "map_path"]:
		if values.has(key): values[key] = str(values[key]).strip_edges()
	if values.name.is_empty() or values.name.length() > 120: return {"ok": false, "error": "事件名称需为 1～120 字符"}
	if type == "gather" and values.item_id.is_empty(): return {"ok": false, "error": "采集模板需要物品"}
	if type == "chest" and values.item_id.is_empty() and values.gold == 0: return {"ok": false, "error": "宝箱需要物品或金币奖励"}
	if type == "shop" and values.shop_id.is_empty(): return {"ok": false, "error": "请选择商店"}
	if type == "transfer" and (not Paths.allowed(values.map_path, content_root) or values.map_path.get_extension().to_lower() != "gltf"): return {"ok": false, "error": "传送目标必须是内容根内的 glTF 地图"}
	return {"ok": true, "value": {"version": 1, "template": type, "parameters": values}}

static func valid_record(record: Dictionary, content_root: String = "") -> bool:
	if not record.has("event_template"): return true
	var value: Variant = record.event_template
	if not value is Dictionary or value.get("version") != 1 or not value.get("template") is String: return false
	var checked := prepare(value.template, value.get("parameters"), content_root)
	return checked.ok and checked.value.parameters == value.get("parameters")

static func compile(value: Dictionary) -> Dictionary:
	var p: Dictionary = value.parameters
	var type: String = value.template
	if not p.enabled: return {"pages": []}
	var commands: Array = []
	var when := {}
	if not p.required_switch.is_empty(): when.switch = p.required_switch
	if not p.required_item.is_empty(): when.item = {"item_id": p.required_item, "qty": p.required_quantity}
	if type in ["chest", "gather"]:
		if not p.item_id.is_empty(): commands.append({"op": "give_item", "item_id": p.item_id, "qty": p.quantity})
		if p.get("gold", 0) > 0: commands.append({"op": "give_gold", "amount": p.gold})
	if p.has("text") and not p.text.is_empty(): commands.append({"op": "text", "text": p.text, "npc_name": p.name})
	if type == "shop": commands.append({"op": "open_shop", "shop_id": p.shop_id})
	if not p.set_switch.is_empty(): commands.append({"op": "set_switch", "id": p.set_switch, "value": true})
	if p.get("once", false): commands.append({"op": "set_self_switch", "letter": "A", "value": true})
	if type == "transfer": commands.append({"op": "transfer", "map_path": p.map_path, "world_location": {"map_ref": "authored/destination", "position_m": p.spawn, "surface_id": "ground"}})
	var pages: Array = [{"when": when, "commands": commands}]
	if p.get("once", false): pages.append({"when": {"self_switch": "A"}, "commands": [{"op": "text", "text": p.empty_text, "npc_name": p.name}]})
	return {"name": p.name, "trigger": p.trigger, "pages": pages}

static func spec(record: Dictionary) -> Dictionary:
	var value: Dictionary = record.event_template
	var p: Dictionary = value.parameters
	var rotation: Array = record.rotation
	var basis := Basis.from_euler(Vector3(rotation[0], rotation[1], rotation[2]) * PI / 180)
	var position: Array = record.position
	var center := Vector3(position[0], position[1], position[2]) + basis * Vector3(p.offset[0], p.offset[1], p.offset[2])
	var mesh := BoxMesh.new(); mesh.size = Vector3(p.touch_size[0], p.touch_size[1], p.touch_size[2])
	return {"uuid": record.uuid, "position": center, "transform": Transform3D(basis, center), "mesh": mesh, "extras": {"kind": "event", "name": p.name, "event": compile(value)}, "template": value, "radius": p.radius}
