extends RefCounted
## Domain module: daily board / attendance (list, claim, date tracking).

var ctrl
func _init(c):
	ctrl = c

const Mailbox = preload("res://scripts/net/combat/mailbox.gd")

func try_daily_board_list() -> Array:
	if ctrl.quest_journal == null:
		return []
	if ctrl.quest_journal.has_method("try_daily_board_list"):
		return ctrl.quest_journal.try_daily_board_list()
	return []



func snapshot_daily() -> Dictionary:
	if ctrl.quest_journal != null and ctrl.quest_journal.has_method("snapshot_daily"):
		return ctrl.quest_journal.snapshot_daily()
	return {"daily_date": "", "daily": []}



func _attendance_today_ymd() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0))]



func force_attendance_ymd(ymd: String) -> void:
	ctrl._attendance_last_ymd = str(ymd).strip_edges()



func _attendance_try_grant() -> Array:
	var actions: Array = []
	var today = _attendance_today_ymd()
	if today.is_empty():
		return actions
	if ctrl._attendance_last_ymd == today:
		return actions
	if ctrl.mailbox == null:
		ctrl.mailbox = Mailbox.new()
	var to_name = ctrl._party_self_name()
	var attach: Array = [{"id": "potion_hp_small", "qty": 1}]
	var add_r: Dictionary = ctrl.mailbox.try_add(
		"系统",
		to_name,
		"每日签到奖励",
		"感谢你今日登录！请领取签到奖励：金币与回复药水。",
		50,
		attach
	)
	if not bool(add_r.get("ok", false)):
		# Inbox full — skip claim so we can retry next enter; do not stamp last ymd.
		actions.append({"type": "system_message", "text": "邮箱已满，今日签到奖励未能送达。"})
		ctrl._pending_tick_actions.append_array(actions)
		return actions
	ctrl._attendance_last_ymd = today
	actions.append({"type": "system_message", "text": "今日签到奖励已发送至邮箱。"})
	actions.append(ctrl._mail_update_action())
	ctrl._pending_tick_actions.append_array(actions)
	return actions


