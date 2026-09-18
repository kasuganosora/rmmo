extends SceneTree
## Headless: combat log kind filters — typed push, hide kinds, settings persist.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_typed_and_filter()
	failed += _test_infer_kind()
	failed += await _test_settings_persist()

	if failed == 0:
		print("test_combat_log_filter: PASS")
		quit(0)
	else:
		print("test_combat_log_filter: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  OK  ", msg)
		return 0
	print("  FAIL: ", msg)
	return 1


func _test_typed_and_filter() -> int:
	var failed := 0
	var CombatLog = load("res://scripts/game/combat_log.gd")
	failed += _expect(CombatLog != null, "load combat_log.gd")
	if CombatLog == null:
		return failed
	var log = CombatLog.new()
	log.push_typed("damage", "你对史莱姆造成 12 伤害")
	log.push_typed("heal", "恢复 15 生命")
	log.push_typed("miss", "未命中")
	log.push_typed("kill", "击败了史莱姆")
	log.push_typed("other", "其它提示")
	failed += _expect(log.size() == 5, "buffer size 5")
	failed += _expect(log.lines().size() == 5, "lines() unfiltered 5")

	var all_vis: PackedStringArray = log.filtered_lines({})
	failed += _expect(all_vis.size() == 5, "all flags default show 5")

	var no_dmg: PackedStringArray = log.filtered_lines({"show_damage": false})
	failed += _expect(no_dmg.size() == 4, "hide damage → 4")
	failed += _expect(str(no_dmg).find("伤害") < 0, "no damage text")

	var only_kill: PackedStringArray = log.filtered_lines({
		"show_damage": false, "show_heal": false, "show_miss": false, "show_kill": true
	})
	failed += _expect(only_kill.size() == 2, "kill+other → 2 (got %d)" % only_kill.size())
	failed += _expect(str(only_kill[0]).find("击败") >= 0 or str(only_kill[1]).find("击败") >= 0, "kill kept")

	var hide_all_kinds: PackedStringArray = log.filtered_lines({
		"show_damage": false, "show_heal": false, "show_miss": false, "show_kill": false
	})
	failed += _expect(hide_all_kinds.size() == 1, "only other remains")
	failed += _expect(str(hide_all_kinds[0]) == "其它提示", "other always shown")

	# Cap still on buffer
	log.clear()
	for i in range(CombatLog.MAX_LINES + 5):
		log.push_typed("damage", "行%d" % i)
	failed += _expect(log.size() == CombatLog.MAX_LINES, "cap MAX_LINES")
	var filt: PackedStringArray = log.filtered_lines({"show_damage": false})
	failed += _expect(filt.size() == 0, "filter hides all damage but buffer full")
	failed += _expect(log.size() == CombatLog.MAX_LINES, "buffer unchanged by filter")
	return failed


func _test_infer_kind() -> int:
	var failed := 0
	var CombatLog = load("res://scripts/game/combat_log.gd")
	failed += _expect(CombatLog.infer_kind("未命中") == "miss", "infer miss")
	failed += _expect(CombatLog.infer_kind("击败了史莱姆") == "kill", "infer kill")
	failed += _expect(CombatLog.infer_kind("恢复 15 生命") == "heal", "infer heal")
	failed += _expect(CombatLog.infer_kind("恢复 8 魔法") == "heal", "infer mp as heal")
	failed += _expect(CombatLog.infer_kind("你对史莱姆造成 12 伤害") == "damage", "infer damage")
	failed += _expect(CombatLog.infer_kind("暴击！24") == "damage", "infer crit")
	failed += _expect(CombatLog.infer_kind("随便") == "other", "infer other")
	var log = CombatLog.new()
	log.push("未命中")
	failed += _expect(log.latest_kind() == "miss", "push infers miss")
	log.push("你受到 9 伤害")
	failed += _expect(log.latest_kind() == "damage", "push infers damage")
	return failed


func _test_settings_persist() -> int:
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "load game_settings")
	if Settings == null:
		return failed

	# Prefer isolated instance for disk round-trip (avoid clobbering autoload).
	var path := "user://_test_combat_log_filter.cfg"
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)

	var gs = Settings.new()
	gs.name = "GameSettingsCombatLogFilterTest"
	gs.persist_path = path
	gs.persist_enabled = true
	root.add_child(gs)
	await process_frame

	failed += _expect(bool(gs.combat_log_show_damage), "default damage ON")
	failed += _expect(bool(gs.combat_log_show_heal), "default heal ON")
	failed += _expect(bool(gs.combat_log_show_miss), "default miss ON")
	failed += _expect(bool(gs.combat_log_show_kill), "default kill ON")
	var snap: Dictionary = gs.snapshot()
	failed += _expect(snap.has("combat_log_show_damage"), "snapshot damage key")
	failed += _expect(snap.has("combat_log_show_kill"), "snapshot kill key")

	gs.set_flag("combat_log_show_damage", false)
	gs.set_flag("combat_log_show_miss", false)
	failed += _expect(not bool(gs.combat_log_show_damage), "damage OFF after set")
	failed += _expect(not bool(gs.combat_log_show_miss), "miss OFF after set")
	failed += _expect(bool(gs.combat_log_show_heal), "heal still ON")
	failed += _expect(FileAccess.file_exists(path), "cfg written")

	gs.queue_free()
	await process_frame

	var gs2 = Settings.new()
	gs2.name = "GameSettingsCombatLogFilterTest2"
	gs2.persist_path = path
	gs2.persist_enabled = true
	root.add_child(gs2)
	await process_frame
	# _ready already load_from_disk
	failed += _expect(not bool(gs2.combat_log_show_damage), "reload damage OFF")
	failed += _expect(not bool(gs2.combat_log_show_miss), "reload miss OFF")
	failed += _expect(bool(gs2.combat_log_show_heal), "reload heal ON")
	failed += _expect(bool(gs2.combat_log_show_kill), "reload kill ON")

	# Autoload set_flag also accepts new keys
	var auto = Settings.get_i()
	if auto != null:
		var prev_d: bool = bool(auto.combat_log_show_damage)
		auto.persist_enabled = false
		auto.set_flag("combat_log_show_damage", false)
		failed += _expect(not bool(auto.combat_log_show_damage), "autoload set_flag damage")
		auto.set_flag("combat_log_show_damage", prev_d)
		auto.persist_enabled = true

	gs2.queue_free()
	DirAccess.remove_absolute(abs_path)
	return failed
