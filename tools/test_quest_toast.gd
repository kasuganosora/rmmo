extends SceneTree
## Headless: quest ready/complete toast on status transition only.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		_finish(failed)
		return

	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("show_quest_ready_toast"), "show_quest_ready_toast API")
	failed += _expect(hud.has_method("show_quest_complete_toast"), "show_quest_complete_toast API")
	failed += _expect(hud.has_method("hide_quest_toast"), "hide_quest_toast API")
	failed += _expect(hud.has_method("is_quest_toast_visible"), "is_quest_toast_visible API")
	failed += _expect(hud.has_method("get_quest_toast_text"), "get_quest_toast_text API")
	failed += _expect(hud.has_method("apply_quest_snapshot"), "apply_quest_snapshot API")

	# Direct ready toast
	hud.show_quest_ready_toast("采药")
	await process_frame
	failed += _expect(hud.is_quest_toast_visible(), "ready toast visible")
	var text_ready: String = hud.get_quest_toast_text()
	failed += _expect(text_ready == "任务可交付：采药", "ready text exact got '%s'" % text_ready)

	var toast: Control = hud.get_node_or_null("QuestToast")
	failed += _expect(toast != null, "QuestToast node exists")
	if toast != null:
		failed += _expect(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "toast mouse_filter IGNORE")
		failed += _expect(toast.visible, "toast Control visible")

	hud.hide_quest_toast()
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "hidden after hide")

	# Direct complete toast
	hud.show_quest_complete_toast("采药")
	await process_frame
	failed += _expect(hud.get_quest_toast_text() == "任务完成：采药", "complete text exact")
	failed += _expect(hud.is_quest_toast_visible(), "complete toast visible")

	# Auto-hide ~2s
	if hud.has_method("_tick_quest_toast"):
		hud._tick_quest_toast(2.1)
	else:
		hud._process(2.1)
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "auto-hide after ~2s")

	# --- Transition detection via apply_quest_snapshot ---
	# First snapshot seeds only (no toast) even if ready/completed present.
	var seed_snap: Array = [
		{
			"id": "herb_gather",
			"title": "采药",
			"status": "in_progress",
			"objectives": [{"text": "药草", "cur": 1, "max": 3}],
		},
		{
			"id": "welcome_gift",
			"title": "初入村庄",
			"status": "completed",
			"objectives": [{"text": "领取", "cur": 1, "max": 1}],
		},
	]
	hud.apply_quest_snapshot(seed_snap)
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "no toast on first seed snapshot")

	# Same ready state reapplied → no spam
	var ready_snap: Array = [
		{
			"id": "herb_gather",
			"title": "采药",
			"status": "ready",
			"objectives": [{"text": "药草", "cur": 3, "max": 3}],
		},
		seed_snap[1],
	]
	hud.apply_quest_snapshot(ready_snap)
	await process_frame
	failed += _expect(hud.is_quest_toast_visible(), "toast on transition to ready")
	failed += _expect(hud.get_quest_toast_text() == "任务可交付：采药", "ready transition text")

	hud.hide_quest_toast()
	await process_frame

	# Reapply identical ready snapshot → no second toast
	hud.apply_quest_snapshot(ready_snap)
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "no spam on reapply same ready")

	# Turn-in / completed transition
	var done_snap: Array = [
		{
			"id": "herb_gather",
			"title": "采药",
			"status": "completed",
			"objectives": [{"text": "药草", "cur": 3, "max": 3}],
		},
		seed_snap[1],
	]
	hud.apply_quest_snapshot(done_snap)
	await process_frame
	failed += _expect(hud.is_quest_toast_visible(), "toast on transition to completed")
	failed += _expect(hud.get_quest_toast_text() == "任务完成：采药", "complete transition text")

	hud.hide_quest_toast()
	await process_frame
	hud.apply_quest_snapshot(done_snap)
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "no spam on reapply same completed")

	# Alias "complete" → completed
	var prog2: Array = [
		{
			"id": "pond_fishing",
			"title": "池边垂钓",
			"status": "in_progress",
			"objectives": [{"text": "鱼", "cur": 0, "max": 2}],
		},
	]
	# Reset seen by applying a fresh quest only (herb already completed stays)
	hud.apply_quest_snapshot(done_snap + prog2)
	await process_frame
	failed += _expect(not hud.is_quest_toast_visible(), "no toast adding in_progress")

	var alias_done: Array = done_snap + [
		{
			"id": "pond_fishing",
			"title": "池边垂钓",
			"status": "complete",
			"objectives": [{"text": "鱼", "cur": 2, "max": 2}],
		},
	]
	hud.apply_quest_snapshot(alias_done)
	await process_frame
	failed += _expect(hud.is_quest_toast_visible(), "toast on complete alias")
	failed += _expect(hud.get_quest_toast_text() == "任务完成：池边垂钓", "alias complete text")

	# World still routes quest_update → apply_quest_snapshot
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find('"quest_update"') >= 0, "world handles quest_update")
	failed += _expect(world_src.find("apply_quest_snapshot") >= 0, "world calls apply_quest_snapshot")

	hud.queue_free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
