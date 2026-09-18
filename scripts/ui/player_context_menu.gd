extends RefCounted
## Shared action ids / Chinese labels for remote-player right-click menu.

enum Action {
	HEADER = 0,
	VIEW = 1,
	INVITE = 2,
	TRADE = 3,
	WHISPER = 4,
	FOLLOW = 5,
	ADD_FRIEND = 6,
	DUEL = 7,
	INVITE_GUILD = 8,
}


static func item_defs(following_target_id: String = "") -> Array:
	## Ordered menu rows after the disabled name header.
	var follow_text := "取消跟随" if following_target_id.strip_edges() != "" else "跟随"
	return [
		{"id": Action.VIEW, "text": "查看"},
		{"id": Action.INVITE, "text": "邀请组队"},
		{"id": Action.TRADE, "text": "交易"},
		{"id": Action.DUEL, "text": "决斗"},
		{"id": Action.WHISPER, "text": "密语"},
		{"id": Action.FOLLOW, "text": follow_text},
		{"id": Action.ADD_FRIEND, "text": "加为好友"},
		{"id": Action.INVITE_GUILD, "text": "邀请入会"},
	]


static func label_for(action_id: int, following_target_id: String = "") -> String:
	for d in item_defs(following_target_id):
		if int(d.get("id", -1)) == action_id:
			return str(d.get("text", ""))
	return ""
