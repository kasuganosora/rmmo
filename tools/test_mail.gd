extends SceneTree
## Headless: MockServer mail send-to-self / claim / delete / fail paths.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_mail: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.mailbox == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.mailbox == null:
		print("test_mail: FAIL no mailbox after init")
		quit(1)
		return

	srv._session_character_id = "1"
	srv.mailbox.clear()
	srv._mail_welcome_sent = false
	srv.inventory.clear()
	srv.inventory.add_gold(500)
	srv.inventory.add_item("potion_hp_small", 5)

	failed += _expect(srv.has_method("try_mail_send"), "has try_mail_send")
	failed += _expect(srv.has_method("try_mail_claim"), "has try_mail_claim")
	failed += _expect(srv.has_method("try_mail_delete"), "has try_mail_delete")
	failed += _expect(srv.has_method("try_mail_read"), "has try_mail_read")
	failed += _expect(srv.has_method("snapshot_mail"), "has snapshot_mail")

	var snap0: Dictionary = srv.snapshot_mail()
	failed += _expect(typeof(snap0.get("mails", null)) == TYPE_ARRAY, "snap mails array")
	failed += _expect(int(snap0.get("count", -1)) == 0, "empty count")
	failed += _expect(int(snap0.get("max_mail", 0)) >= 30, "cap >= 30")

	# Welcome inject once
	if srv.has_method("_mail_inject_welcome"):
		srv._mail_inject_welcome()
		failed += _expect(srv.mailbox.count() == 1, "welcome mail once")
		srv._mail_inject_welcome()
		failed += _expect(srv.mailbox.count() == 1, "welcome not duplicated")
		srv.mailbox.clear()
		srv._mail_welcome_sent = true

	var self_name := "你"
	if srv.has_method("_party_self_name"):
		self_name = str(srv._party_self_name())

	var gold0: int = srv.inventory.get_gold()
	var qty0: int = srv.inventory.get_qty("potion_hp_small")

	var send1: Dictionary = srv.try_mail_send(self_name, "测试主题", "测试正文", 50, "potion_hp_small", 2)
	failed += _expect(bool(send1.get("ok", false)), "send-to-self ok")
	failed += _expect(_has(send1, "mail_update"), "send mail_update")
	failed += _expect(_has(send1, "inventory_update"), "send inventory_update")
	failed += _expect(_has(send1, "system_message"), "send system_message")
	failed += _expect(srv.inventory.get_gold() == gold0 - 50, "gold deducted")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == qty0 - 2, "item deducted")
	failed += _expect(srv.mailbox.count() == 1, "one mail in inbox")

	var snap1: Dictionary = srv.snapshot_mail()
	var mails: Array = snap1.get("mails", [])
	failed += _expect(mails.size() == 1, "snap one mail")
	var mail: Dictionary = mails[0] if mails.size() > 0 and typeof(mails[0]) == TYPE_DICTIONARY else {}
	var mid := str(mail.get("id", ""))
	failed += _expect(mid != "", "mail id")
	failed += _expect(str(mail.get("subject", "")) == "测试主题", "subject")
	failed += _expect(int(mail.get("gold", 0)) == 50, "mail gold")
	failed += _expect(bool(mail.get("read", true)) == false, "unread")
	failed += _expect(bool(mail.get("claimed", true)) == false, "unclaimed")
	failed += _expect(mail.has("created_at"), "has created_at")
	failed += _expect(mail.has("from") and mail.has("to") and mail.has("body"), "shape fields")
	failed += _expect(typeof(mail.get("items", null)) == TYPE_ARRAY, "items array")

	var rd: Dictionary = srv.try_mail_read(mid)
	failed += _expect(bool(rd.get("ok", false)), "read ok")
	failed += _expect(_has(rd, "mail_update"), "read mail_update")
	var after_read: Dictionary = srv.mailbox.get_mail(mid)
	failed += _expect(bool(after_read.get("read", false)), "marked read")

	var gold1: int = srv.inventory.get_gold()
	var qty1: int = srv.inventory.get_qty("potion_hp_small")
	var cl: Dictionary = srv.try_mail_claim(mid)
	failed += _expect(bool(cl.get("ok", false)), "claim ok")
	failed += _expect(_has(cl, "mail_update"), "claim mail_update")
	failed += _expect(_has(cl, "inventory_update"), "claim inventory_update")
	failed += _expect(srv.inventory.get_gold() == gold1 + 50, "gold claimed")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == qty1 + 2, "item claimed")
	var after_claim: Dictionary = srv.mailbox.get_mail(mid)
	failed += _expect(bool(after_claim.get("claimed", false)), "marked claimed")

	var cl2: Dictionary = srv.try_mail_claim(mid)
	failed += _expect(not bool(cl2.get("ok", true)), "claim again fails")
	failed += _expect(str(cl2.get("reason", "")) == "already_claimed", "reason already_claimed")

	var dl: Dictionary = srv.try_mail_delete(mid)
	failed += _expect(bool(dl.get("ok", false)), "delete ok")
	failed += _expect(srv.mailbox.count() == 0, "inbox empty after delete")
	var dl2: Dictionary = srv.try_mail_delete(mid)
	failed += _expect(not bool(dl2.get("ok", true)), "delete missing fails")

	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv.inventory.add_item("potion_hp_small", 1)
	var bad_gold: Dictionary = srv.try_mail_send(self_name, "x", "y", 999, "", 1)
	failed += _expect(not bool(bad_gold.get("ok", true)), "reject no gold")
	failed += _expect(str(bad_gold.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(_has(bad_gold, "system_message"), "no gold message")

	var bad_item: Dictionary = srv.try_mail_send(self_name, "x", "y", 0, "potion_hp_small", 9)
	failed += _expect(not bool(bad_item.get("ok", true)), "reject no item")
	failed += _expect(str(bad_item.get("reason", "")) == "no_item", "reason no_item")

	var bad_to: Dictionary = srv.try_mail_send("不存在的旅人", "x", "y", 0, "", 1)
	failed += _expect(not bool(bad_to.get("ok", true)), "reject unknown to")
	failed += _expect(str(bad_to.get("reason", "")) == "not_found", "reason not_found")

	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("potion_hp_small", 3)
	var send_r: Dictionary = srv.try_mail_send("旅人甲", "问候", "你好", 10, "potion_hp_small", 1)
	failed += _expect(bool(send_r.get("ok", false)), "send to remote stub ok")
	failed += _expect(srv.mailbox.count() == 0, "remote mail not in local inbox")
	failed += _expect(srv.inventory.get_gold() == 90, "remote send gold deducted")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 2, "remote send item deducted")

	# Bag full on claim
	srv.mailbox.clear()
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("potion_hp_small", 3)
	var send_bf: Dictionary = srv.try_mail_send(self_name, "满包", "测", 0, "potion_hp_small", 1)
	failed += _expect(bool(send_bf.get("ok", false)), "send for bag-full test")
	var mails_bf: Array = srv.snapshot_mail().get("mails", [])
	var mid_bf := ""
	if mails_bf.size() > 0 and typeof(mails_bf[0]) == TYPE_DICTIONARY:
		mid_bf = str(mails_bf[0].get("id", ""))
	var old_max: int = int(srv.inventory.max_slots)
	srv.inventory.max_slots = 1
	srv.inventory.clear()
	srv.inventory.add_item("potion_mp_small", 1)
	failed += _expect(srv.inventory.slot_count() >= 1, "bag occupied")
	var claim_full: Dictionary = srv.try_mail_claim(mid_bf)
	failed += _expect(not bool(claim_full.get("ok", true)), "claim rejects bag full")
	failed += _expect(str(claim_full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(_has(claim_full, "system_message"), "bag full chinese message")
	var msg_bf := _first_text(claim_full)
	failed += _expect(msg_bf.find("背包") >= 0, "bag full message mentions 背包")
	srv.inventory.max_slots = old_max

	# Inbox full
	srv.mailbox.clear()
	srv.inventory.clear()
	srv.inventory.add_gold(1000)
	var cap: int = int(srv.mailbox.max_mail())
	failed += _expect(cap == 30, "cap is 30")
	for i in range(cap):
		var r: Dictionary = srv.mailbox.try_add("系统", self_name, "填充%d" % i, "", 0, [])
		if not bool(r.get("ok", false)):
			failed += _expect(false, "fill mail %d" % i)
			break
	failed += _expect(srv.mailbox.count() == cap, "filled to cap")
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var full_send: Dictionary = srv.try_mail_send(self_name, "溢出", "x", 1, "", 1)
	failed += _expect(not bool(full_send.get("ok", true)), "full reject")
	failed += _expect(str(full_send.get("reason", "")) == "full", "reason full")
	failed += _expect(srv.inventory.get_gold() == 10, "gold not taken on full")

	# Survives transfer
	srv.mailbox.clear()
	srv.inventory.clear()
	srv.inventory.add_gold(20)
	srv.try_mail_send(self_name, "持久", "keep", 5, "", 1)
	failed += _expect(srv.mailbox.count() == 1, "pre-transfer count")
	failed += _expect(srv.mailbox.count() == 1, "survives session transfer")

	srv.mailbox.clear()
	srv._mail_welcome_sent = false
	failed += _expect(srv.mailbox.count() == 0, "cleared for new session")

	if failed == 0:
		print("test_mail: PASS")
		quit(0)
		return
	print("test_mail: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first_text(result: Dictionary) -> String:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			return str(a.get("text", ""))
	return ""


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
