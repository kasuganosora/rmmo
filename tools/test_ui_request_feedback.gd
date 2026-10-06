extends SceneTree
const Net = preload("res://scripts/net/net.gd")
const Pipeline = preload("res://scripts/net/request_pipeline.gd")
const UIRequest = preload("res://scripts/ui/ui_request.gd")
class Bridge3D extends Node:
	var received: Array = []
	func apply_actions(actions): received.append_array(actions)
class LegacyBridge extends Node:
	var received: Array = []
	func _apply_server_actions(actions): received.append_array(actions)
class Transport extends Node:
	signal response_ready(id: int, result: Dictionary)
	var calls: Array = []
	var next := 0
	var item_catalog
	var source_server
	func item_display_name(id): return source_server.item_display_name(id)
	var _session_character_id := "test"
	var reset_calls := 0
	func request(kind: String, args: Array) -> Dictionary:
		next += 1
		calls.append([next, kind, args])
		return {"deferred": true, "request_id": next}
	func try_mail_send(to, subject, body, gold, item, qty): return request("mail", [to, subject, body, gold, item, qty])
	func try_auction_list(item, qty, price): return request("auction", [item, qty, price])
	func try_shop_buy(shop, item, qty): return request("buy", [shop, item, qty])
	func try_shop_sell(item, qty): return request("sell", [item, qty])
	func try_skill_respec():
		reset_calls += 1
		return {"ok": true, "actions": []}
	func resolve(id: int, ok: bool): response_ready.emit(id, {"ok": ok, "actions": [] if ok else [{"type": "system_message", "text": "测试：库存不足"}]})

var checks := 0
var failures := 0
var capture := false
func _init(): call_deferred("run")
func expect(value: bool, label: String):
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + label)
func settle():
	for i in 4: await process_frame
func shot(name: String, panel: Control):
	if not capture: return
	panel.show()
	panel.move_to_front()
	panel.global_position = Vector2(30, 30)
	await settle()
	await RenderingServer.frame_post_draw
	var folder = preload("res://scripts/asset/art_paths.gd").review_path("game_windows")
	DirAccess.make_dir_recursive_absolute(folder)
	var img: Image = root.get_texture().get_image()
	img.get_region(Rect2i(panel.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))).save_png(folder.path_join(name + ".png"))
	panel.hide()
func run():
	capture = OS.get_cmdline_user_args().has("--capture")
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 800)
	if capture: DisplayServer.window_set_size(root.size)
	root.get_node("GameSettings").persist_enabled = false
	var hud = load("res://scenes/ui/game_hud.tscn").instantiate()
	root.add_child(hud)
	await settle()
	var server := Transport.new()
	server.source_server = Net.server()
	server.item_catalog = Net.server().item_catalog
	root.add_child(server)
	Net._server_override = server
	hud._server_inventory = [{"id": "potion_hp_small", "qty": 8}]
	hud._server_gold = 1000
	var mail = hud._mail_panel_logic
	mail._select_page(1)
	hud._mail_to_input.text = "测试收件人"
	hud._mail_subject_input.text = "原主题"
	hud._mail_body_input.text = "不能丢失的正文"
	hud._mail_item_id_input.select_key("potion_hp_small")
	hud._mail_item_qty_spin.value = 3
	mail._on_mail_send()
	expect(mail._sending and hud._mail_body_input.text == "不能丢失的正文", "mail waits for authoritative result without clearing draft")
	expect(not hud._mail_body_input.editable and mail._send_button.disabled, "pending mail locks form and submit")
	mail._on_mail_send()
	expect(server.calls.size() == 1, "duplicate mail submission suppressed")
	server.resolve(9999, true)
	expect(mail._sending, "unrelated response cannot complete mail")
	server.resolve(1, false)
	expect(not mail._sending and hud._mail_body_input.text == "不能丢失的正文", "failed mail preserves complete draft")
	expect(hud._mail_item_qty_spin.editable and hud._mail_body_input.editable, "failed mail restores editable controls")
	expect(mail._feedback.text.contains("库存不足"), "mail error appears in current window")
	await shot("mail_failure", hud._mail_panel)
	mail._on_mail_send()
	server.resolve(1, true)
	expect(mail._sending, "late duplicate response cannot finish retry")
	server.resolve(2, true)
	expect(hud._mail_body_input.text.is_empty() and not mail._sending, "mail clears only after matching success")
	await settle()
	expect(mail._feedback.text == "邮件已发送", "success remains visible after the form settles")
	hud._mail_panel.show()
	await settle()
	hud._mail_body_input.grab_focus()
	var typed := InputEventKey.new()
	typed.keycode = KEY_N
	typed.unicode = 110
	typed.pressed = true
	Input.parse_input_event(typed)
	await process_frame
	typed.pressed = false
	Input.parse_input_event(typed)
	await settle()
	expect(hud._mail_body_input.text == "n" and mail._feedback.text.is_empty(), "typing a new draft removes previous send success")
	hud._mail_panel.hide()
	var auction = hud._auction_panel_logic
	auction._select_page(2)
	hud._auction_item_id_input.select_key("potion_hp_small")
	hud._auction_qty_spin.value = 3
	hud._auction_price_spin.value = 450
	auction._on_auction_list()
	auction._on_auction_list()
	expect(server.calls.size() == 3 and auction._listing, "auction suppresses duplicate submission")
	server.resolve(3, false)
	expect(hud._auction_price_spin.value == 450 and hud._auction_qty_spin.value == 3, "failed listing preserves quantity and entered price")
	expect(auction._feedback.text.contains("库存不足"), "listing error is inline")
	await shot("auction_failure", hud._auction_panel)
	auction._on_auction_list()
	server.resolve(4, true)
	expect(hud._auction_item_id_input.selected_item().is_empty(), "listing clears selection only after success")
	hud._auction_item_id_input.select_key("potion_hp_small")
	expect(auction._feedback.text.is_empty(), "new listing does not display previous success")
	hud.show_shop("test", "商店", [{"item_id": "potion_hp_small", "buy_price": 20}], 1000)
	hud._shop_buy_cart = [{"item_id": "potion_hp_small", "name": "生命药水", "qty": 2, "unit_price": 20}, {"item_id": "potion_mp_small", "name": "魔法药水", "qty": 3, "unit_price": 30}]
	var shop = hud._shop_panel_logic
	shop._fill_shop_panel()
	shop._confirm_buy_cart()
	shop._confirm_buy_cart()
	expect(server.calls.size() == 5 and hud._shop_buy_cart.size() == 2, "cart remains intact and double confirm cannot submit twice")
	server.resolve(5, true)
	expect(hud._shop_buy_cart.size() == 1 and server.calls.size() == 6, "successful cart line removed and next submitted once")
	server.resolve(6, false)
	expect(not shop._submitting and hud._shop_buy_cart[0].item_id == "potion_mp_small", "partial failure preserves only failed cart line")
	expect(shop._feedback.text.contains("库存不足"), "cart failure stays visible")
	await shot("shop_partial_failure", hud._shop_panel)
	shop._confirm_buy_cart()
	expect(server.calls.back()[2] == ["test", "potion_mp_small", 3], "retry sends only failed line with original quantity")
	server.resolve(7, true)
	expect(hud._shop_buy_cart.is_empty(), "successful retry clears remaining cart")
	# Reset confirmation is visible, cancellable, and cannot survive closing.
	hud._shop_panel.hide()
	hud._windows.skills.show()
	hud._on_respec_skill_pressed()
	expect(server.reset_calls == 0 and hud._windows.skills.find_child("ConfirmAction", true, false) != null, "skill reset requires visible confirmation")
	hud._close_top_window()
	expect(hud._windows.skills.visible and hud._windows.skills.find_child("ConfirmAction", true, false) == null, "Escape cancels confirmation before closing window")
	hud._on_respec_skill_pressed()
	hud._windows.skills.hide()
	hud._windows.skills.show()
	expect(hud._windows.skills.find_child("ConfirmAction", true, false) == null, "reopening does not retain armed reset")
	hud._on_respec_skill_pressed()
	hud._windows.skills.find_child("ConfirmAction", true, false).pressed.emit()
	expect(server.reset_calls == 1, "confirmed skill reset invokes business operation exactly once")
	hud._windows.skills.hide()
	var gs = root.get_node("GameSettings")
	gs.master_volume = 37
	hud._windows.system.show()
	hud._windows.system.find_child("ResetAllSettings", true, false).pressed.emit()
	expect(gs.master_volume == 37, "requesting restore defaults does not mutate settings")
	hud._close_top_window()
	expect(gs.master_volume == 37, "cancel restore preserves settings")
	hud._windows.system.find_child("ResetAllSettings", true, false).pressed.emit()
	hud._windows.system.find_child("ConfirmAction", true, false).pressed.emit()
	expect(gs.master_volume == 80, "confirmed restore applies defaults")
	# Sync validation failures and each game bridge deliver actions once.
	var complete: Array = []
	var local_actions: Array = []
	var local_apply := func(result): local_actions.append_array(result.get("actions", []))
	var finish := func(result): complete.append(result)
	UIRequest.dispatch(hud, "missing_test_operation", [], local_apply, finish)
	expect(complete.size() == 1 and not complete[0].ok, "missing server operation resolves once as failure")
	var bridge := Bridge3D.new()
	root.add_child(bridge)
	hud._world_combat = bridge
	UIRequest.dispatch(hud, "try_mail_send", ["test", "", "", 0, "", 0], local_apply, finish)
	var request_id: int = server.calls.back()[0]
	var actions: Array = [{"type": "inventory_update"}, {"type": "mail_update"}]
	server.response_ready.emit(request_id, {"ok": true, "actions": actions})
	expect(bridge.received.size() == 1 and bridge.received[0].type == "inventory_update" and local_actions.size() == 1 and local_actions[0].type == "mail_update", "3D bridge and panel snapshots are each applied once")
	server.response_ready.emit(request_id, {"ok": true, "actions": actions})
	expect(complete.size() == 2 and bridge.received.size() == 1, "duplicate result cannot reapply game actions")
	var legacy := LegacyBridge.new()
	root.add_child(legacy)
	hud._world_combat = legacy
	UIRequest.dispatch(hud, "try_mail_send", ["test", "", "", 0, "", 0], local_apply, finish)
	server.response_ready.emit(server.calls.back()[0], {"ok": true, "actions": actions})
	expect(legacy.received == actions and local_actions.size() == 1, "legacy bridge retains sole action ownership")
	hud._world_combat = null
	bridge.queue_free()
	legacy.queue_free()
	Pipeline.reset()
	Net.clear_server_override()
	hud.queue_free()
	server.queue_free()
	await settle()
	print("test_ui_request_feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
