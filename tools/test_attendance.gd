extends SceneTree
## Headless: daily attendance mail once per local YYYY-MM-DD.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_attendance: FAIL no MockServer")
		quit(1)
		return
	if srv.mailbox == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.mailbox == null:
		print("test_attendance: FAIL no mailbox")
		quit(1)
		return

	srv._session_character_id = "1"
	var _probe: String = str(srv._attendance_last_ymd)
	failed += _expect(true, "has _attendance_last_ymd (access ok)")
	failed += _expect(srv.has_method("force_attendance_ymd"), "has force_attendance_ymd")
	failed += _expect(srv.has_method("_attendance_try_grant"), "has _attendance_try_grant")
	failed += _expect(srv.has_method("_attendance_today_ymd"), "has _attendance_today_ymd")

	var today: String = str(srv._attendance_today_ymd())
	failed += _expect(today.length() == 10 and today.find("-") == 4, "ymd shape %s" % today)

	# Fresh day: clear mailbox + last
	srv.mailbox.clear()
	srv._mail_welcome_sent = true
	srv.force_attendance_ymd("")
	srv._pending_tick_actions.clear()

	var acts1: Array = srv._attendance_try_grant()
	failed += _expect(not acts1.is_empty(), "first grant returns actions")
	failed += _expect(_msg_has_arr(acts1, "今日签到奖励已发送至邮箱"), "system message")
	failed += _expect(_has_arr(acts1, "mail_update"), "mail_update action")
	failed += _expect(str(srv._attendance_last_ymd) == today, "last ymd stamped")
	failed += _expect(srv.mailbox.count() == 1, "one attendance mail")

	var mail: Dictionary = {}
	var mails: Array = srv.snapshot_mail().get("mails", [])
	if mails.size() > 0 and typeof(mails[0]) == TYPE_DICTIONARY:
		mail = mails[0]
	failed += _expect(str(mail.get("from", "")) == "系统", "from 系统")
	failed += _expect(str(mail.get("subject", "")).find("签到") >= 0, "subject 签到")
	failed += _expect(int(mail.get("gold", 0)) == 50, "gold 50")
	failed += _expect(bool(mail.get("claimed", true)) == false, "unclaimed")
	var items: Array = mail.get("items", [])
	var found_potion := false
	for it in items:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("id", "")) == "potion_hp_small" and int(it.get("qty", 0)) >= 1:
			found_potion = true
	failed += _expect(found_potion, "potion_hp_small x1")

	# Same day again: no duplicate
	var count1: int = srv.mailbox.count()
	var acts2: Array = srv._attendance_try_grant()
	failed += _expect(acts2.is_empty(), "same day no actions")
	failed += _expect(srv.mailbox.count() == count1, "same day no extra mail")
	failed += _expect(str(srv._attendance_last_ymd) == today, "last unchanged")

	# Force yesterday → grant again
	srv.force_attendance_ymd("2000-01-01")
	var acts3: Array = srv._attendance_try_grant()
	failed += _expect(not acts3.is_empty(), "new day grants")
	failed += _expect(srv.mailbox.count() == count1 + 1, "second day mail")
	failed += _expect(str(srv._attendance_last_ymd) == today, "restamped today")

	# force_attendance_ymd to today blocks
	srv.force_attendance_ymd(today)
	var before: int = srv.mailbox.count()
	var acts4: Array = srv._attendance_try_grant()
	failed += _expect(acts4.is_empty(), "force today blocks")
	failed += _expect(srv.mailbox.count() == before, "no mail when forced today")

	# Claim attachment path still works via existing mail API
	var mid := ""
	for m in srv.snapshot_mail().get("mails", []):
		if typeof(m) == TYPE_DICTIONARY and int(m.get("gold", 0)) == 50:
			mid = str(m.get("id", ""))
			break
	failed += _expect(mid != "", "find attendance mail id")
	if mid != "" and srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.add_gold(0)
		var gold0: int = srv.inventory.get_gold()
		var qty0: int = srv.inventory.get_qty("potion_hp_small")
		var cl: Dictionary = srv.try_mail_claim(mid)
		failed += _expect(bool(cl.get("ok", false)), "claim attendance ok")
		failed += _expect(srv.inventory.get_gold() == gold0 + 50, "claimed gold")
		failed += _expect(srv.inventory.get_qty("potion_hp_small") == qty0 + 1, "claimed potion")

	# Cleanup
	srv.mailbox.clear()
	srv.force_attendance_ymd("")

	if failed == 0:
		print("test_attendance: PASS")
		quit(0)
		return
	print("test_attendance: FAIL count=%d" % failed)
	quit(1)


func _has_arr(actions: Array, typ: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has_arr(actions: Array, frag: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			if str(a.get("text", "")).find(frag) >= 0:
				return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
