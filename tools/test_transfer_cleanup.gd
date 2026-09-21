extends SceneTree
## Headless: map transfer clears ground bags + remotes; stamp bags_cleared.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_transfer_cleanup: FAIL no MockServer")
		quit(1)
		return

	# Ensure demo pack
	if not srv._load_pack("res://demo_map"):
		print("test_transfer_cleanup: FAIL load demo")
		quit(1)
		return
	srv.set_player_cell(5, 5)

	# Seed bag + remote on current map
	srv._add_items_to_ground({"x": 5, "y": 5}, [{"item_id": "potion_hp_small", "qty": 1}], "player", "")
	failed += _expect(srv.ground_bag_count() >= 1, "seeded ground bag")
	var sp: Dictionary = srv.try_remote_debug_spawn("过图测试员")
	failed += _expect(bool(sp.get("ok", false)), "seed remote")
	failed += _expect(srv.snapshot_remote_players().size() >= 1, "remote present")

	# Find a warp if any
	var warp_cell := Vector2i(-1, -1)
	for item in srv.map_warps:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var fc: Variant = item.get("from_cell", {})
		if typeof(fc) == TYPE_DICTIONARY:
			warp_cell = Vector2i(int(fc.get("x", -1)), int(fc.get("y", -1)))
			break

	if warp_cell.x < 0:
		# Synthesize transfer via event helper to street_map if exists
		var am: Node = root.get_node_or_null("AssetManager")
		var to := str(am.resolve_map_pack_path("street_map")) if am != null else "content://map_pack/street_map"
		if not FileAccess.file_exists("%s/pack.json" % to):
			print("test_transfer_cleanup: SKIP no warp and no street_map")
			# Still unit-test _load_pack cleanup path
			srv._add_items_to_ground({"x": 6, "y": 6}, [{"item_id": "potion_mp_small", "qty": 1}], "player", "")
			failed += _expect(srv.ground_bag_count() >= 1, "bag before pack reload")
			failed += _expect(srv._load_pack("res://demo_map"), "reload demo")
			failed += _expect(srv.ground_bag_count() == 0, "bags cleared on _load_pack")
			failed += _expect(srv.snapshot_remote_players().is_empty(), "remotes cleared on _load_pack")
			if failed == 0:
				print("test_transfer_cleanup: PASS (load_pack path)")
				quit(0)
				return
			print("test_transfer_cleanup: FAIL count=%d" % failed)
			quit(1)
			return
		var ev: Dictionary = srv._event_perform_transfer(to, {"x": 2, "y": 2}, 2, "测试街", "street_map")
		failed += _expect(bool(ev.get("ok", false)), "event transfer ok")
		failed += _expect(bool(ev.get("bags_cleared", false)), "bags_cleared flag")
		failed += _expect((ev.get("ground_bags", ["x"]) as Array).is_empty(), "result ground_bags empty")
		failed += _expect(srv.ground_bag_count() == 0, "server bags empty after transfer")
		var names2: Array = []
		for rp2 in srv.snapshot_remote_players():
			if typeof(rp2) == TYPE_DICTIONARY:
				names2.append(str(rp2.get("name", "")))
		failed += _expect(not names2.has("过图测试员"), "prior remote cleared after event transfer")
		failed += _expect(_has_type(ev, "loot_close"), "loot_close action")
		failed += _expect(_has_type(ev, "system_message"), "cleanup system_message")
	else:
		srv.set_player_cell(warp_cell.x, warp_cell.y)
		var tr: Dictionary = srv.try_transfer(warp_cell.x, warp_cell.y)
		failed += _expect(bool(tr.get("ok", false)), "try_transfer ok")
		failed += _expect(bool(tr.get("bags_cleared", false)), "bags_cleared flag")
		failed += _expect(srv.ground_bag_count() == 0, "bags empty")
		# Prior-map debug remotes cleared; destination may auto-spawn shell remotes.
		var names: Array = []
		for rp in srv.snapshot_remote_players():
			if typeof(rp) == TYPE_DICTIONARY:
				names.append(str(rp.get("name", "")))
		failed += _expect(not names.has("过图测试员"), "prior debug remote cleared")
		failed += _expect(_has_type(tr, "system_message"), "system tip")

	if failed == 0:
		print("test_transfer_cleanup: PASS")
		quit(0)
		return
	print("test_transfer_cleanup: FAIL count=%d" % failed)
	quit(1)


func _has_type(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
