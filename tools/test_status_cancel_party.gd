extends SceneTree
## Headless: cancel beneficial buffs + party member statuses for expand UI.

func _init() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("OK ", msg)
		return 0
	push_error("FAIL " + msg)
	print("FAIL ", msg)
	return 1


func _run() -> void:
	await process_frame
	await process_frame
	var failed := 0
	var Bar = load("res://scripts/ui/status_icon_bar.gd")
	var Status = load("res://scripts/net/combat/status_effects.gd")
	var Net = load("res://scripts/net/net.gd")

	# --- StatusIconBar allow_cancel wiring ---
	var bar = Bar.new()
	bar.allow_cancel = true
	get_root().add_child(bar)
	await process_frame
	var st = Status.new()
	st.apply_status("player", {"id": "atk_up", "name": "强击", "kind": "buff", "duration": 10.0}, 10.0)
	st.apply_status("player", {"id": "regen", "name": "再生", "kind": "hot", "duration": 8.0, "tick_hp": 2}, 8.0)
	st.apply_status("player", {"id": "bleed", "name": "流血", "kind": "dot", "duration": 6.0, "tick_hp": -2}, 6.0)
	var snap: Array = st.snapshot_statuses("player")
	failed += _expect(snap.size() == 3, "3 statuses applied")
	bar.apply_statuses(snap)
	await process_frame
	var buffs = bar.get_node("BuffRow")
	var debuffs = bar.get_node("DebuffRow")
	failed += _expect(buffs.get_child_count() == 2, "buff/hot slots == 2")
	failed += _expect(debuffs.get_child_count() == 1, "dot slot == 1")
	var got_cancel := [0]
	bar.cancel_requested.connect(func(sid: String):
		got_cancel[0] += 1
		failed += _expect(sid == "atk_up", "cancel id atk_up")
	)
	var slot0 = buffs.get_child(0)
	failed += _expect(bool(slot0.cancelable), "buff slot cancelable")
	failed += _expect("右键取消" in str(slot0.tooltip_text), "tooltip has 右键取消")
	var deb_slot = debuffs.get_child(0)
	failed += _expect(not bool(deb_slot.cancelable), "dot not cancelable")
	slot0.cancel_requested.emit("atk_up")
	await process_frame
	failed += _expect(got_cancel[0] == 1, "bar forwarded cancel")

	# Unit clear_status path (beneficial only logic mirrors MockServer)
	st.clear_status("player", "atk_up")
	failed += _expect(not st.has_status("player", "atk_up"), "buff cleared")
	failed += _expect(st.has_status("player", "bleed"), "dot remains")

	# --- MockServer try_cancel_status + party statuses ---
	var srv = Net.server()
	if srv == null:
		failed += _expect(false, "MockServer present")
	else:
		if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
			srv._init_combat_layers()
		srv.combat_stats.statuses.clear_everything()
		srv.combat_stats.statuses.apply_status("player", {
			"id": "battle_cry", "name": "战吼", "kind": "buff", "duration": 15.0, "atk_mul": 1.2
		}, 15.0)
		srv.combat_stats.statuses.apply_status("player", {
			"id": "poison", "name": "中毒", "kind": "dot", "duration": 5.0, "tick_hp": -1
		}, 5.0)
		# Cancel debuff/dot should fail
		var bad: Dictionary = srv.try_cancel_status("poison")
		failed += _expect(not bool(bad.get("ok", true)), "dot cancel rejected")
		failed += _expect(srv.combat_stats.statuses.has_status("player", "poison"), "poison still there")
		# Cancel buff ok
		var good: Dictionary = srv.try_cancel_status("battle_cry")
		failed += _expect(bool(good.get("ok", false)), "buff cancel ok")
		failed += _expect(not srv.combat_stats.statuses.has_status("player", "battle_cry"), "buff gone")
		var acts: Array = good.get("actions", [])
		var has_su := false
		for a in acts:
			if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "status_update":
				has_su = true
		failed += _expect(has_su, "cancel emits status_update")

		# Party stub includes statuses
		var created: Dictionary = srv.try_party_create()
		failed += _expect(bool(created.get("ok", false)), "party create")
		var fill: Dictionary = srv.try_party_debug_fill()
		failed += _expect(bool(fill.get("ok", false)), "party fill")
		var party: Dictionary = srv.snapshot_party()
		var members: Array = party.get("members", [])
		failed += _expect(members.size() >= 2, "party has stubs")
		var self_ok := false
		var stub_ok := false
		var self_id := str(srv._party_self_id())
		for m in members:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = m
			var st_arr: Array = md.get("statuses", []) if typeof(md.get("statuses", [])) == TYPE_ARRAY else []
			if str(md.get("id", "")) == self_id:
				self_ok = true
				# self should have remaining poison from earlier
				failed += _expect(typeof(md.get("statuses", null)) == TYPE_ARRAY, "self has statuses key")
			else:
				if st_arr.size() >= 2:
					stub_ok = true
		failed += _expect(self_ok, "self member present")
		failed += _expect(stub_ok, "stub has demo statuses")

		# Cancel while in party also emits party_update
		srv.combat_stats.statuses.apply_status("player", {
			"id": "hot_test", "name": "再生", "kind": "hot", "duration": 9.0
		}, 9.0)
		var cancel2: Dictionary = srv.try_cancel_status("hot_test")
		failed += _expect(bool(cancel2.get("ok", false)), "hot cancel ok")
		var has_party := false
		for a2 in cancel2.get("actions", []):
			if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "party_update":
				has_party = true
		failed += _expect(has_party, "cancel in party emits party_update")

		# Cleanup party
		srv.try_party_leave()
		srv.combat_stats.statuses.clear_everything()

	if failed == 0:
		print("PASS status cancel party")
		quit(0)
	else:
		print("FAIL status cancel party count=", failed)
		quit(1)
