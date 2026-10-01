extends "res://tools/test_world3d_mcp.gd"
const Templates = preload("res://scripts/world3d/event_templates.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Net = preload("res://scripts/net/net.gd")
var directory: String

class TestWorld extends "res://scripts/world3d/world_3d.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class ShopHud extends Control:
	var shop_id := ""
	var listings: Array = []
	var buyback: Array = []
	func show_shop(id: String, _title: String, rows: Array, _gold: int, _rep: int) -> void: shop_id = id; listings = rows
	func apply_shop_buyback(rows: Array) -> void: buyback = rows
	func apply_inventory_snapshot(_items: Array, _gold: int) -> void: pass
	func append_system(_text: String) -> void: pass

func run() -> void:
	directory = Paths.external_root().path_join("__gameplay_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id": "gameplay_test", "name": "事件环境测试包"})); metadata.close()
	var path := directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0,-.25,0), Vector3(20,.5,20))
	var model := Node3D.new(); model.name = "EventModel"
	for y in [0.5, 1.5]:
		var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.position.y = y
		mesh.set_meta("extras", {"kind":"npc", "name":"原模型事件"}); model.add_child(mesh)
	var model_path := directory.path_join("event_model.glb")
	check(Io.save_scene(model,model_path) == OK, "create multi-mesh imported event fixture")
	model.free()
	var model_id: String = doc.add_asset({"asset_path":model_path, "bounds_position":[-.5,0,-.5], "bounds_size":[1,2,1]}, Vector3(-6,0,0))
	check(doc.save(path) == OK, "create isolated map")
	Net.session().world3d_editor_path = path; Net.session().world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled = false
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok, "start real HTTP MCP")
	var discovery := await rpc("tools/list")
	check(discovery.result.tools.size() == 63, "discover 63 current 3D tools")
	var catalog := await call_tool("list_event_templates")
	check(catalog.templates.size() == 5, "all five templates and their defaults are discoverable")
	var resources := await call_tool("list_event_resources", {"limit": 200})
	check(not resources.items.is_empty() and not resources.shops.is_empty(), "events use actual item and shop catalogs")
	var item: String = resources.items[0].id
	var shop: String = resources.shops[0].id
	var dialogue := await call_tool("create_event_template", {"template": "dialogue", "position": [0,0,0], "parameters": {"text": "测试对话"}})
	var chest := await call_tool("create_event_template", {"template": "chest", "position": [3,0,0], "parameters": {"item_id": item, "quantity": 2, "gold": 17, "set_switch": "reward_done"}})
	var gather := await call_tool("create_event_template", {"template": "gather", "position": [6,0,0], "parameters": {"item_id": item, "required_switch": "reward_done", "required_item": item, "required_quantity": 2}})
	var transfer := await call_tool("create_event_template", {"template": "transfer", "position": [0,0,3], "parameters": {"map_path": path, "spawn": [4,0,5]}})
	var vendor := await call_tool("create_event_template", {"template": "shop", "position": [3,0,3], "parameters": {"shop_id": shop}})
	await call_tool("set_event_template", {"id": model_id, "template": "dialogue", "parameters": {"text":"模型上的事件", "offset":[0,1,0]}})
	await call_tool("set_event_template", {"id": dialogue.id, "parameters": {"text": "更新后的对话", "radius": 3}})
	check(doc._find(dialogue.id).event_template.parameters.text == "更新后的对话", "partial updates retain other event fields")
	var before := doc.recovery_snapshot(); var undo_count: int = doc._undo.size()
	await call_tool("create_event_template", {"template": "gather", "position": [0,0,0], "parameters": {"item_id": "__missing_item__"}}, false)
	await call_tool("set_event_template", {"id": dialogue.id, "parameters": {"quantity": 2}}, false)
	await call_tool("set_event_template", {"id": chest.id, "parameters": {"quantity": 1.5}}, false)
	await call_tool("create_event_template", {"template": "transfer", "position": [0,0,0], "parameters": {"map_path": "C:/outside/map.gltf"}}, false)
	await call_tool("create_event_template", {"template": "transfer", "position": [0,0,0], "parameters": {"map_path": directory.path_join("missing.gltf")}}, false)
	await call_tool("set_event_template", {"id": vendor.id, "parameters": {"shop_id": "__missing_shop__"}}, false)
	await call_tool("set_environment", {"fog_density": -1}, false)
	await call_tool("set_environment", {"outline_color": [1,2,3]}, false)
	check(doc.recovery_snapshot() == before and doc._undo.size() == undo_count, "invalid operations have no document or undo side effects")
	for flag in ["locked", "hidden"]:
		await call_tool("set_object_properties", {"ids": [dialogue.id], flag: true})
		before = doc.recovery_snapshot(); undo_count = doc._undo.size()
		await call_tool("set_event_template", {"id": dialogue.id, "parameters": {"text": "不能修改"}}, false)
		await call_tool("clear_event_template", {"id": dialogue.id}, false)
		check(doc.recovery_snapshot() == before and doc._undo.size() == undo_count, "protected event failure is atomic")
		await call_tool("set_object_properties", {"ids": [dialogue.id], flag: false})
	await call_tool("clear_event_template", {"id": dialogue.id})
	check(not doc._find(dialogue.id).has("event_template"), "clear leaves the object intact")
	await call_tool("undo"); check(doc._find(dialogue.id).has("event_template"), "undo restores cleared event")
	await call_tool("redo"); await call_tool("undo")
	var initial := await call_tool("get_environment")
	undo_count = doc._undo.size()
	var configured := await call_tool("set_environment", {"preset": "night", "sun_energy": .15, "fog_enabled": true, "fog_density": .035, "outline_enabled": true, "outline_color": [1,.2,.1], "outline_width": 3})
	check(doc._undo.size() == undo_count + 1 and is_equal_approx(editor._sun.light_energy,.15) and editor._camera.environment.fog_enabled, "one environment transaction updates visible editor lighting")
	check(is_equal_approx(editor._environment_panel.form.fields.sun_energy.value,.15), "UI preserves precise values supplied through MCP")
	await call_tool("set_event_template", {"id": dialogue.id, "parameters": {"text": "mixed history"}})
	await call_tool("undo"); await call_tool("undo")
	check(equivalent(Settings.resolve(doc.map_meta), initial.environment), "mixed record/environment undo restores map metadata")
	await call_tool("redo"); await call_tool("redo")
	check(equivalent(Settings.resolve(doc.map_meta), configured.environment), "mixed redo restores full environment")
	# UI and HTTP share the same edits and undo stack.
	await call_tool("select_objects", {"ids": [dialogue.id]})
	editor._event_panel.form.fields.text.text = "面板修改"
	editor._event_panel.apply_selected()
	check(doc._find(dialogue.id).event_template.parameters.text == "面板修改", "event panel writes the same record")
	editor._environment_panel.form.fields.sun_energy.value = .2
	editor._environment_panel.apply()
	check(is_equal_approx(editor._sun.light_energy, .2), "environment panel applies shared settings")
	editor._load_failed = true
	check(not editor._gameplay.set_environment({"preset":"day"}).ok and not editor._gameplay.clear_event(dialogue.id).ok, "UI also rejects edits in read-only state")
	editor._load_failed = false
	await call_tool("select_objects", {"ids": [chest.id]})
	var prefab := await call_tool("save_prefab", {"name": "可领取宝箱", "pack_root": directory})
	await call_tool("place_asset", {"asset_id": prefab.asset_id, "position": [-3,0,0]})
	var copy_id: String = editor._selection_tools.ids[0]
	check(copy_id != chest.id and equivalent(doc._find(copy_id).event_template, doc._find(chest.id).event_template), "prefab retains template with independent event identity")
	await call_tool("save_world")
	var draft := await call_tool("save_editor_draft")
	await call_tool("list_editor_drafts")
	before = doc.recovery_snapshot()
	await call_tool("set_environment", {"preset":"day"})
	await call_tool("restore_editor_draft", {"draft_id": draft.draft_id, "discard_changes": true})
	check(equivalent(editor._doc.records, before.records) and equivalent(editor._doc.map_meta, before.map_meta), "draft restores both event and environment records")
	await call_tool("open_world", {"path": path, "discard_changes": true})
	check(equivalent(editor._doc.records, before.records) and equivalent(Settings.resolve(editor._doc.map_meta), Settings.resolve(before.map_meta)), "save/reopen preserves templates and environment")
	var intact_hash := FileAccess.get_sha256(path)
	var saved_template: Dictionary = editor._doc._find(dialogue.id).event_template.duplicate(true)
	editor._doc._find(dialogue.id).event_template.parameters.trigger = "invalid"
	await call_tool("save_world", {}, false)
	check(FileAccess.get_sha256(path) == intact_hash, "malformed event cannot overwrite a saved map")
	editor._doc._find(dialogue.id).event_template = saved_template
	if DisplayServer.get_name() != "headless":
		editor._dock_tabs.current_tab = 5
		await settle(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_gameplay/event_panel.png"))
		editor._dock_tabs.current_tab = 6
		await settle(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_gameplay/environment_panel.png"))
	editor.queue_free(); await settle()
	var loader := preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array = await loader.finished
	var runtime: Node3D = loaded[0]
	check(runtime != null, "runtime loads authored templates and environment")
	if runtime != null:
		var host := Node3D.new(); root.add_child(host); host.add_child(runtime)
		preload("res://scripts/world3d/world_stream.gd").sync(runtime,host,Vector3.ZERO)
		await physics_frame; await physics_frame
		var server = Net.server(); var events = server.world3d_events
		events.runtime.clear_session()
		events.mount("test/events", runtime.get_meta("stream_library", []), Io.extras_of(runtime).rmmo_records)
		check(events.targets.size() == 7, "runtime registers one event per authored object, including model and prefab")
		server.inventory.restore_session_state({"stacks":[], "gold":0, "max_slots":32})
		check(events.run(gather.id).is_empty(), "required switch and item prevent early gathering")
		server.inventory.max_slots = 0
		events.run(chest.id)
		check(server.inventory.get_gold() == 0 and not events.runtime.get_self_switch(chest.id,"A"), "full inventory cannot consume a one-shot chest or grant partial gold")
		server.inventory.max_slots = 1
		var limit: int = server.inventory.stack_max_for(item)
		server.inventory.add_item(item, limit - 1)
		events.run(chest.id)
		check(server.inventory.get_qty(item) == limit - 1 and not events.runtime.get_self_switch(chest.id,"A"), "partial stack capacity also fails without consuming reward")
		server.inventory.clear()
		server.inventory.max_slots = 32
		var reward: Array = events.run(chest.id)
		check(server.inventory.get_gold() == 17 and server.inventory.get_qty(item) == 2 and events.runtime.get_switch("reward_done"), "chest grants complete reward and completion switch")
		events.run(chest.id)
		check(server.inventory.get_gold() == 17 and server.inventory.get_qty(item) == 2, "chest cannot be collected twice")
		events.run(copy_id)
		check(server.inventory.get_gold() == 34, "prefab copy can be collected independently")
		events.run(gather.id)
		check(server.inventory.get_qty(item) == 5, "gather template reuses conditions and inventory runtime")
		var shop_actions: Array = events.run(vendor.id)
		check(shop_actions.any(func(a): return a.type == "open_shop" and a.shop_id == shop), "shop uses the existing catalog and server pricing callback")
		var world := TestWorld.new(); root.add_child(world)
		world._status = Label.new(); world.add_child(world._status)
		world._hud = ShopHud.new(); world.add_child(world._hud)
		world.apply_actions(shop_actions)
		check(world._hud.shop_id == shop and not world._hud.listings.is_empty(), "3D world forwards open-shop actions to its HUD")
		var sale: Dictionary = world._hud.listings[0]
		var sale_id: String = sale.get("item_id", sale.get("id", ""))
		server.inventory.add_gold(100000)
		var old_qty: int = server.inventory.get_qty(sale_id)
		world.request_shop_buy(shop,sale_id,1)
		check(server.inventory.get_qty(sale_id) == old_qty + 1, "3D shop purchase calls existing authoritative transaction")
		world.request_shop_sell(sale_id,1)
		check(server.inventory.get_qty(sale_id) == old_qty and not world._hud.buyback.is_empty(), "3D sale updates inventory and buyback HUD")
		world.request_shop_buyback(0)
		check(server.inventory.get_qty(sale_id) == old_qty + 1, "3D buyback uses existing transaction")
		world.request_shop_close(); world.free()
		var transfer_actions: Array = events.touch_segment(Vector3(-2,0,3),Vector3(2,0,3))
		check(transfer_actions.any(func(a): return a.type == "world3d_transfer" and a.path == path and equivalent(a.location.position_m, [4,0,5])), "fast movement across a trigger preserves transfer foot coordinates")
		var body := CharacterBody3D.new(); body.position = Vector3(0,.4,1); root.add_child(body)
		check(events.nearest(body) == dialogue.id, "event on ordinary object can be found by interaction")
		body.position = Vector3(-6,1,1)
		check(events.nearest(body) == model_id and not events.interact(model_id,body).is_empty(), "imported multi-mesh object interacts through its own collision without duplicate events")
		body.position = Vector3(0,.4,1)
		var wall := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(2,2,.2); shape.shape = box; wall.add_child(shape); wall.position = Vector3(0,.4,.5); root.add_child(wall)
		await physics_frame; await physics_frame
		check(not events.can_interact(dialogue.id, body), "solid wall blocks interaction")
		wall.free(); body.free()
		events.mount("test/events", [], Io.extras_of(runtime).rmmo_records)
		check(events.runtime.get_self_switch(chest.id,"A"), "map reload retains session self-switches")
		var light := DirectionalLight3D.new(); var environment := Environment.new()
		Settings.apply(Settings.resolve(Io.extras_of(runtime)), light, environment)
		check(is_equal_approx(light.light_energy,.2) and environment.fog_enabled, "runtime uses saved lighting and fog")
		light.free(); host.free()
	if DisplayServer.get_name() != "headless":
		# Exercise the production scene hooks, including the real player/camera.
		preload("res://tools/world3d_test_character.gd").ensure(self)
		Net.session().world3d_map_path = path
		Net.session().world3d_spawn = Vector3(0,.9,1)
		var live = load("res://scenes/world_3d.tscn").instantiate()
		root.add_child(live)
		while not live.is_world_ready(): await process_frame
		check(live._player != null and live._outline != null and live._outline.enabled, "production scene mounts player outline from map settings")
		check(is_equal_approx(live._sun.light_energy,.2) and live._env.fog_enabled and Net.server().world3d_events.targets.size() == 7, "production scene applies saved environment and all authored events")
		if live._player != null:
			live._player.set_physics_process(false)
			live._talk()
			check(live._status.text == "面板修改", "production E interaction reaches an authored dialogue")
			var destination := Doc.new(); destination.add_box("ground",Vector3(0,-.25,0),Vector3(20,.5,20))
			destination.map_meta.environment = Settings.updated({}, {"preset":"sunset", "outline_enabled":false})
			var destination_path := directory.path_join("maps/destination/map.gltf")
			check(destination.save(destination_path) == OK, "save destination with a different environment")
			check(await live.transfer_map(destination_path,Vector3(0,.9,0)), "production map transfer succeeds")
			check(is_equal_approx(live._sun.light_energy,.8) and not live._env.fog_enabled and not live._outline.enabled, "map transfer replaces light, fog and outline settings")
		live.queue_free(); await settle()
	if failed == 0: Io._remove_tree(directory)
	else: print("fixture=" + directory)
	print("test_world3d_gameplay: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
