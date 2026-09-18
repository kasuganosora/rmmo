extends SceneTree
## Headless: CombatLog ring buffer push / cap / clear / Chinese formatters.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var CombatLog = load("res://scripts/game/combat_log.gd")
	failed += _expect(CombatLog != null, "load combat_log.gd")
	if CombatLog == null:
		print("test_combat_log: FAIL count=", failed)
		quit(1)
		return

	failed += _expect(int(CombatLog.MAX_LINES) == 50, "MAX_LINES == 50")

	# Formatters (static — no instance needed)
	failed += _expect(CombatLog.line_miss() == "未命中", "miss line")
	failed += _expect(CombatLog.line_crit(24) == "暴击！24", "crit shorthand")
	failed += _expect(
		CombatLog.line_damage_out("史莱姆", 12) == "你对史莱姆造成 12 伤害",
		"damage out short"
	)
	failed += _expect(
		CombatLog.line_damage_out("史莱姆", 24, true) == "暴击！24（史莱姆）",
		"damage out crit"
	)
	failed += _expect(CombatLog.line_damage_in(9) == "你受到 9 伤害", "damage in")
	failed += _expect(CombatLog.line_damage_in(9, true) == "受到暴击！9", "damage in crit")
	failed += _expect(CombatLog.line_heal(15) == "恢复 15 生命", "heal")
	failed += _expect(CombatLog.line_mp(8) == "恢复 8 魔法", "mp")
	failed += _expect(CombatLog.line_kill("史莱姆") == "击败了史莱姆", "kill")

	var log = CombatLog.new()
	failed += _expect(log.size() == 0, "empty size")
	failed += _expect(log.latest() == "", "empty latest")

	log.push("  ")
	failed += _expect(log.size() == 0, "blank ignored")

	log.push("你对史莱姆造成 12 伤害")
	log.push("未命中")
	log.push("暴击！24")
	failed += _expect(log.size() == 3, "size 3 after pushes")
	failed += _expect(log.latest() == "暴击！24", "latest")
	var rows: PackedStringArray = log.lines()
	failed += _expect(rows.size() == 3, "lines() size")
	failed += _expect(str(rows[0]).find("史莱姆") >= 0, "first line kept")

	# Cap: push beyond MAX_LINES
	log.clear()
	failed += _expect(log.size() == 0, "clear")
	for i in range(CombatLog.MAX_LINES + 17):
		log.push("行%d" % i)
	failed += _expect(log.size() == CombatLog.MAX_LINES, "capped at MAX_LINES (got %d)" % log.size())
	var after: PackedStringArray = log.lines()
	failed += _expect(str(after[0]) == "行17", "oldest dropped (got %s)" % str(after[0]))
	failed += _expect(
		str(after[after.size() - 1]) == "行%d" % (CombatLog.MAX_LINES + 16),
		"newest kept"
	)

	# game_settings: B = combat_log; L stays quest
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "load game_settings")
	if Settings != null:
		var defaults: Dictionary = Settings.KEYBIND_DEFAULTS
		failed += _expect(defaults.has("combat_log"), "keybind combat_log exists")
		failed += _expect(int(defaults.get("combat_log", -1)) == KEY_B, "default hotkey B")
		failed += _expect(int(defaults.get("quest", -1)) == KEY_L, "L still quest")

	if failed == 0:
		print("test_combat_log: PASS")
		quit(0)
	else:
		print("test_combat_log: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		return 0
	print("  FAIL: ", msg)
	return 1
