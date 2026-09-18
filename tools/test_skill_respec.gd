extends SceneTree
## Headless: skill respec refunds SP, clears known to basic_attack, deducts flat gold.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_book_respec_unit()
	failed += _test_mock_server_respec()
	if failed == 0:
		print("test_skill_respec: PASS")
		quit(0)
	else:
		print("test_skill_respec: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _msg_has(actions: Array, needle: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _test_book_respec_unit() -> int:
	print("-- skill_book.try_respec --")
	var failed := 0
	var SkillCatalog = load("res://scripts/net/combat/skill_catalog.gd")
	var SkillBook = load("res://scripts/net/combat/skill_book.gd")
	var skills = SkillCatalog.new()
	skills.load_catalog()
	var book = SkillBook.new()
	book.grant_starters(skills)
	# Only starters: still has power_strike → respec ok, refund 0.
	var r0: Dictionary = book.try_respec(skills)
	failed += _expect(bool(r0.get("ok", false)), "respec starters ok")
	failed += _expect(int(r0.get("refunded_sp", -1)) == 0, "starter refund 0")
	failed += _expect(book.list_known() == ["basic_attack"], "only basic_attack after starter respec")
	# Nothing to reset
	var r1: Dictionary = book.try_respec(skills)
	failed += _expect(not bool(r1.get("ok", true)), "second book respec fails")
	failed += _expect(str(r1.get("reason", "")) == "nothing", "reason nothing")
	# Learn paid skills and respec
	book.grant_skill_points(5)
	var sp_before: int = int(book.skill_points)
	var lh: Dictionary = book.try_learn("heal_light", skills, 1)
	failed += _expect(bool(lh.get("ok", false)), "learn heal_light")
	var cost_heal: int = maxi(int(skills.get_skill("heal_light").get("sp_cost", 1)), 0)
	var lt: Dictionary = book.try_learn("keen_eye", skills, 2)
	failed += _expect(bool(lt.get("ok", false)), "learn keen_eye")
	var cost_keen: int = maxi(int(skills.get_skill("keen_eye").get("sp_cost", 1)), 0)
	var spent: int = cost_heal + cost_keen
	var sp_mid: int = int(book.skill_points)
	failed += _expect(sp_mid == sp_before - spent, "SP spent on learn")
	var rr: Dictionary = book.try_respec(skills)
	failed += _expect(bool(rr.get("ok", false)), "respec after learn ok")
	failed += _expect(int(rr.get("refunded_sp", 0)) == spent, "refund equals spent")
	failed += _expect(book.skill_points == sp_mid + spent, "SP restored")
	failed += _expect(book.is_known("basic_attack"), "basic_attack kept")
	failed += _expect(not book.is_known("heal_light"), "heal forgotten")
	failed += _expect(not book.is_known("keen_eye"), "keen forgotten")
	failed += _expect(book.list_known() == ["basic_attack"], "known only basic_attack")
	return failed


func _test_mock_server_respec() -> int:
	print("-- MockServer.try_skill_respec --")
	var failed := 0
	var srv: Node = root.get_node_or_null("MockServer")
	if srv == null:
		print("  SKIP MockServer missing")
		return 0
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats == null:
		print("  SKIP combat_stats null")
		return 0
	srv.combat_stats.reset_player(2)
	if srv.has_method("_reset_skill_book"):
		srv._reset_skill_book()
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	var book = srv.combat_stats.skill_book
	book.grant_skill_points(5)
	var sp0: int = int(book.skill_points)
	var r_learn1: Dictionary = srv.try_learn_skill("heal_light")
	failed += _expect(bool(r_learn1.get("ok", false)), "server learn heal_light")
	var r_learn2: Dictionary = srv.try_learn_skill("keen_eye")
	failed += _expect(bool(r_learn2.get("ok", false)), "server learn keen_eye")
	var spent: int = sp0 - int(book.skill_points)
	failed += _expect(spent > 0, "spent SP > 0")
	var gold0: int = srv.inventory.get_gold()
	var r: Dictionary = srv.try_skill_respec()
	failed += _expect(bool(r.get("ok", false)), "respec ok")
	failed += _expect(int(r.get("gold_spent", 0)) == 50, "flat gold 50")
	failed += _expect(srv.inventory.get_gold() == gold0 - 50, "gold deducted 50")
	failed += _expect(int(r.get("refunded_sp", 0)) == spent, "refunded_sp matches spent")
	failed += _expect(book.skill_points == sp0, "SP fully refunded")
	failed += _expect(book.list_known() == ["basic_attack"], "server known only basic_attack")
	failed += _expect(_msg_has(r.get("actions", []), "已重置技能，返还技能点"), "system_message refund")
	failed += _expect(_has_type(r.get("actions", []), "skill_book_update"), "skill_book_update")
	failed += _expect(_has_type(r.get("actions", []), "inventory_update"), "inventory_update")
	failed += _expect(_has_type(r.get("actions", []), "skill_respec"), "skill_respec action")
	# Second respec: nothing left
	var r2: Dictionary = srv.try_skill_respec()
	failed += _expect(not bool(r2.get("ok", true)), "second respec fails")
	failed += _expect(str(r2.get("reason", "")) == "nothing", "second reason nothing")
	failed += _expect(srv.inventory.get_gold() == gold0 - 50, "gold unchanged on second fail")
	# Insufficient gold
	if srv.has_method("_reset_skill_book"):
		srv._reset_skill_book()
	book.grant_skill_points(3)
	srv.try_learn_skill("heal_light")
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var r3: Dictionary = srv.try_skill_respec()
	failed += _expect(not bool(r3.get("ok", true)), "insufficient gold fails")
	failed += _expect(str(r3.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(book.is_known("heal_light"), "skill kept when gold fail")
	failed += _expect(srv.inventory.get_gold() == 10, "gold untouched when fail")
	return failed
