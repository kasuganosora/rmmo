extends RefCounted
## Domain ops: entities (update_entity, place_chest).

var ctrl
func _init(c):
	ctrl = c

const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")

func update_entity(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var c: Vector2i = ctrl.mcp._cell(args)
	var hit: Dictionary = d.entity_at(c)
	if hit.is_empty():
		return ctrl.mcp._err("empty cell")
	var data: Dictionary = hit.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return ctrl.mcp._err("bad entity")
	var skip = {"x": true, "y": true, "commands": true, "text": true, "face": true, "face_index": true, "pages": true}
	for k in args.keys():
		if skip.has(str(k)):
			continue
		data[str(k)] = args[k]
	if str(hit.get("kind", "")) == "event":
		var pages: Array = EventCommands.ensure_pages(data)
		if args.has("pages") and typeof(args.get("pages")) == TYPE_ARRAY:
			data["pages"] = args.get("pages")
			pages = EventCommands.ensure_pages(data)
		if not pages.is_empty() and typeof(pages[0]) == TYPE_DICTIONARY:
			if args.has("commands") and typeof(args.get("commands")) == TYPE_ARRAY:
				pages[0]["commands"] = args.get("commands")
			if args.has("text"):
				var cmds: Array = pages[0].get("commands", [])
				if cmds.is_empty():
					cmds = [{"op": "text", "text": str(args.get("text"))}]
					pages[0]["commands"] = cmds
				elif typeof(cmds[0]) == TYPE_DICTIONARY:
					cmds[0]["text"] = str(args.get("text"))
			if args.has("face") and not pages[0].get("commands", []).is_empty():
				EventCommands.set_cmd_face(pages[0]["commands"][0], str(args.get("face")), int(args.get("face_index", 0)))
	d.dirty = true
	if ctrl.pack():
		ctrl.pack().dirty = true
	ctrl.mcp._refresh(c)
	return ctrl.mcp._ok({"kind": str(hit.get("kind", "")), "entity": data})



func place_chest(args: Dictionary) -> Dictionary:
	var d = ctrl.doc()
	if d == null:
		return ctrl.mcp._err("no map")
	var c: Vector2i = ctrl.mcp._cell(args)
	d.remove_entity_at(c)
	var ev: Dictionary = EventCommands.make_chest(
		c,
		str(args.get("item_id", "potion_hp_small")),
		maxi(int(args.get("qty", 1)), 1),
		maxi(int(args.get("gold", 10)), 0)
	)
	d.events.append(ev)
	d.dirty = true
	if ctrl.pack():
		ctrl.pack().dirty = true
	ctrl.mcp._refresh(c)
	return ctrl.mcp._ok({"chest": ev})

func op_names() -> Array:
	return ["update_entity", "place_chest"]

func tools() -> Array:
	return [
		ctrl.mcp._tool("update_entity", "改一格已有实体字段（不整格覆盖）。事件可带 commands/pages。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
		}, ["x", "y"]),
		ctrl.mcp._tool("place_chest", "放置宝箱事件。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"item_id": {"type": "string"}, "qty": {"type": "integer"}, "gold": {"type": "integer"},
		}, ["x", "y"]),
	]
