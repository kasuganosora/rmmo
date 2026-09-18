extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Bar = load("res://scripts/ui/status_icon_bar.gd")
	var Status = load("res://scripts/net/combat/status_effects.gd")
	var bar = Bar.new()
	get_root().add_child(bar)
	await process_frame
	var st = Status.new()
	st.apply_status("player", {"id": "atk_up", "name": "强击", "kind": "buff", "duration": 10.0}, 10.0)
	st.apply_status("player", {"id": "bleed", "name": "流血", "kind": "dot", "duration": 6.0, "tick_hp": -2}, 6.0)
	st.apply_status("player", {"id": "slow", "name": "迟缓", "kind": "debuff", "duration": 8.0}, 8.0)
	var snap: Array = st.snapshot_statuses("player")
	if snap.size() != 3:
		push_error("FAIL expected 3 statuses got %d" % snap.size())
		quit(1)
	if float(snap[0].get("duration_max", 0)) <= 0.0:
		push_error("FAIL duration_max missing")
		quit(1)
	bar.apply_statuses(snap)
	await process_frame
	var buffs = bar.get_node("BuffRow")
	var debuffs = bar.get_node("DebuffRow")
	if buffs.get_child_count() != 1:
		push_error("FAIL buff count %d" % buffs.get_child_count())
		quit(1)
	if debuffs.get_child_count() != 2:
		push_error("FAIL debuff count %d" % debuffs.get_child_count())
		quit(1)
	bar.tick(1.0)
	await process_frame
	# allow_cancel: buff cancelable, debuff/dot not
	bar.allow_cancel = true
	bar.apply_statuses(snap)
	await process_frame
	var buff_slot = bar.get_node("BuffRow").get_child(0)
	if not bool(buff_slot.cancelable):
		push_error("FAIL buff should be cancelable")
		quit(1)
	var got := [false]
	bar.cancel_requested.connect(func(_sid): got[0] = true)
	buff_slot.cancel_requested.emit(buff_slot.status_id)
	await process_frame
	if not got[0]:
		push_error("FAIL cancel not forwarded")
		quit(1)
	var deb_slot = bar.get_node("DebuffRow").get_child(0)
	if bool(deb_slot.cancelable):
		push_error("FAIL debuff should not be cancelable")
		quit(1)
	print("PASS status icon bar")
	quit(0)
