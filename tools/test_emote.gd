extends SceneTree
## Headless: MockServer emote catalog / unknown / wave / cooldown.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_emote: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("emote_catalog"), "has emote_catalog")
	failed += _expect(srv.has_method("try_emote"), "has try_emote")

	var cat: Array = srv.emote_catalog()
	failed += _expect(cat.size() >= 8, "catalog size>=8 (%d)" % cat.size())
	var has_wave := false
	for row in cat:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == "wave":
			has_wave = true
			break
	failed += _expect(has_wave, "catalog has wave")

	# Reset cooldown for clean run
	srv._emote_cd_until = 0.0

	var unk: Dictionary = srv.try_emote("not_a_real_emote")
	failed += _expect(not bool(unk.get("ok", true)), "unknown fails")
	failed += _expect(str(unk.get("reason", "")) == "unknown", "reason unknown")
	failed += _expect(_msg_has(unk, "未知表情"), "msg 未知表情")

	srv._emote_cd_until = 0.0
	var ok1: Dictionary = srv.try_emote("wave")
	failed += _expect(bool(ok1.get("ok", false)), "wave succeeds")
	failed += _expect(_has(ok1, "emote"), "wave emote action")
	var em := _first(ok1, "emote")
	failed += _expect(str(em.get("emote_id", "")) == "wave", "emote_id wave")
	failed += _expect(str(em.get("text", "")).strip_edges() != "", "emote text set")
	failed += _expect(float(em.get("duration_sec", 0.0)) > 0.0, "duration_sec > 0")
	failed += _expect(str(em.get("actor_id", "")).strip_edges() != "", "actor_id set")

	# Immediate second call must hit cooldown
	var cd: Dictionary = srv.try_emote("laugh")
	failed += _expect(not bool(cd.get("ok", true)), "immediate second fails")
	failed += _expect(str(cd.get("reason", "")) == "cooldown", "reason cooldown")
	failed += _expect(_msg_has(cd, "冷却"), "msg 冷却")

	if failed == 0:
		print("test_emote: PASS")
		quit(0)
		return
	print("test_emote: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first(result: Dictionary, typ: String) -> Dictionary:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return a
	return {}


func _msg_has(result: Dictionary, needle: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
