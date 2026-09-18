extends SceneTree
## Headless: title journal polish — unlocked/locked list, click equip/unequip, nameplate Label.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += await _test_hud_title_ui()
	if failed == 0:
		print("test_title_ui: PASS")
		quit(0)
	else:
		print("test_title_ui: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _test_hud_title_ui() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	failed += _expect(srv != null, "MockServer present")
	if srv == null:
		return failed
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.get("title_catalog") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		return failed
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	failed += _expect(hud.has_method("_ensure_title_under_name"), "ensure title under name API")
	failed += _expect(hud.has_method("_refresh_titles_panel"), "refresh titles panel API")
	failed += _expect(hud.has_method("_on_title_equip"), "on title equip API")
	failed += _expect(hud.has_method("apply_title_update"), "apply_title_update API")
	failed += _expect(hud.has_method("_title_unlock_hint"), "unlock hint API")
	failed += _expect(hud.has_method("_active_title_display_name"), "active title display API")
	failed += _expect(hud.has_method("_apply_title_result_locally"), "apply title result locally API")

	hud.bind_character({"name": "测试侠", "class_id": "warrior", "level": 3})
	await process_frame
	hud._ensure_title_under_name()
	await process_frame

	var under: Label = hud.get("_title_under_name") as Label
	failed += _expect(under != null, "TitleUnderName label created")
	if under != null:
		failed += _expect(under.name == "TitleUnderName", "label named TitleUnderName")
		var fs := under.get_theme_font_size("font_size")
		failed += _expect(fs <= 11, "thin font size <=11 (got %d)" % fs)
		failed += _expect(not under.visible or str(under.text).is_empty(), "hidden when no title")

	# Fresh server titles → unlock newbie_slayer via kill counter
	srv.combat_stats.reset_titles()
	srv._note_title_counter("kills", 1)
	failed += _expect(srv.combat_stats.is_title_unlocked("newbie_slayer"), "server unlocked newbie_slayer")
	failed += _expect(not srv.combat_stats.is_title_unlocked("hunter"), "hunter still locked")

	var snap: Dictionary = srv.snapshot_titles()
	hud.apply_title_update({"type": "title_update", "titles": snap})
	if hud.get("_titles_panel") != null:
		hud._titles_panel.visible = true
	hud._refresh_titles_panel()
	await process_frame
	await process_frame

	var body: VBoxContainer = hud.get("_titles_body") as VBoxContainer
	failed += _expect(body != null, "titles body exists")
	var body_txt := _collect_text(body)
	failed += _expect("初出茅庐" in body_txt, "lists unlocked title name")
	failed += _expect("猎手" in body_txt, "lists locked title name")
	failed += _expect(
		("击杀" in body_txt and "10" in body_txt) or "击杀 10" in body_txt,
		"locked shows unlock hint from catalog"
	)

	var locked_btn := _find_button_with(body, "猎手")
	failed += _expect(locked_btn == null, "locked title is not an equip button")

	var unlock_btn := _find_button_with(body, "初出茅庐")
	failed += _expect(unlock_btn != null, "unlocked title is clickable button")

	# Equip via MockServer authority
	var locked: Dictionary = srv.try_title_equip("hunter")
	failed += _expect(not bool(locked.get("ok", true)), "server rejects locked equip")
	failed += _expect(str(locked.get("reason", "")) == "locked", "reason locked")

	var eq: Dictionary = srv.try_title_equip("newbie_slayer")
	failed += _expect(bool(eq.get("ok", false)), "server equip ok")
	failed += _expect(str(srv.combat_stats.active_title) == "newbie_slayer", "server active set")

	hud._apply_title_result_locally(eq)
	await process_frame
	await process_frame
	var tname := str(hud._active_title_display_name())
	failed += _expect(tname == "初出茅庐", "HUD active title display 初出茅庐 (got %s)" % tname)

	under = hud.get("_title_under_name") as Label
	failed += _expect(under != null and under.visible, "nameplate title label visible when equipped")
	if under != null:
		failed += _expect("初出茅庐" in under.text, "nameplate shows title text")

	# Name label itself should not glue title as 「」 suffix
	var nl: Label = hud.get("name_label") as Label
	if nl == null:
		nl = hud.get_node_or_null("%NameLabel") as Label
	failed += _expect(nl != null, "name_label present")
	if nl != null:
		failed += _expect(not ("「" in nl.text), "name label clean (title not glued)")
		failed += _expect("测试侠" in nl.text or not str(nl.text).strip_edges().is_empty(), "name still shows")

	# Highlighted equipped row
	hud.apply_title_update({"type": "title_update", "titles": srv.snapshot_titles()})
	hud._refresh_titles_panel()
	await process_frame
	await process_frame
	body_txt = _collect_text(hud.get("_titles_body") as Node)
	failed += _expect("装备中" in body_txt or "✓" in body_txt, "equipped row highlighted")

	# Unequip via empty id — MockServer authority
	var uneq: Dictionary = srv.try_title_equip("")
	failed += _expect(bool(uneq.get("ok", false)), "server unequip ok")
	hud._apply_title_result_locally(uneq)
	await process_frame
	under = hud.get("_title_under_name") as Label
	failed += _expect(
		under == null or (not under.visible) or str(under.text).is_empty(),
		"nameplate cleared after unequip"
	)
	failed += _expect(str(srv.combat_stats.active_title) == "", "server active cleared")

	# HUD click path: equip then unequip via _on_title_equip
	srv.try_title_equip("newbie_slayer")
	hud.apply_title_update({"type": "title_update", "titles": srv.snapshot_titles()})
	hud._refresh_titles_panel()
	await process_frame
	hud._on_title_equip("")
	await process_frame
	failed += _expect(str(srv.combat_stats.active_title) == "", "click unequip clears via try_title_equip")

	# Unlock hint helper
	var hint := str(hud._title_unlock_hint({"desc": "", "require": {"kills": 10}}))
	failed += _expect("10" in hint and ("击杀" in hint or "解锁" in hint), "hint from require when no desc")
	var hint2 := str(hud._title_unlock_hint({"desc": "击杀 10 只怪物", "require": {"kills": 10}}))
	failed += _expect(hint2 == "击杀 10 只怪物", "desc preferred as unlock hint")

	return failed


func _collect_text(node: Node) -> String:
	var out := ""
	if node == null:
		return out
	if node is Label:
		out += str((node as Label).text) + "\n"
	elif node is Button:
		out += str((node as Button).text) + "\n"
	for c in node.get_children():
		out += _collect_text(c)
	return out


func _find_button_with(node: Node, needle: String) -> Button:
	if node == null:
		return null
	if node is Button and needle in str((node as Button).text):
		return node as Button
	for c in node.get_children():
		var f := _find_button_with(c, needle)
		if f != null:
			return f
	return null
